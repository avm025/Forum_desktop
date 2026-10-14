import AVFoundation
import Cocoa
import FlutterMacOS
import ImageIO
import UniformTypeIdentifiers

/// Конвертация видео перед upload (Global.convertVideo — max 960 px, mp4).
class ForumVideoConverterPlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "forum_app/video_converter",
      binaryMessenger: registrar.messenger
    )
    let instance = ForumVideoConverterPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "compressVideo":
      guard let args = call.arguments as? [String: Any],
            let inputPath = args["inputPath"] as? String else {
        result(FlutterError(
          code: "INVALID_ARGS",
          message: "inputPath required",
          details: nil
        ))
        return
      }
      let maxSide = args["maxSide"] as? Double ?? 960.0
      compressVideo(inputPath: inputPath, maxSide: maxSide, result: result)
    case "extractThumbnail":
      guard let args = call.arguments as? [String: Any],
            let inputPath = args["inputPath"] as? String,
            let outputPath = args["outputPath"] as? String else {
        result(FlutterError(
          code: "INVALID_ARGS",
          message: "inputPath and outputPath required",
          details: nil
        ))
        return
      }
      extractThumbnail(
        inputPath: inputPath,
        outputPath: outputPath,
        result: result
      )
    case "extractThumbnailFromUrl":
      guard let args = call.arguments as? [String: Any],
            let inputUrl = args["inputUrl"] as? String,
            let outputPath = args["outputPath"] as? String else {
        result(FlutterError(
          code: "INVALID_ARGS",
          message: "inputUrl and outputPath required",
          details: nil
        ))
        return
      }
      extractThumbnailFromUrl(
        inputUrl: inputUrl,
        outputPath: outputPath,
        result: result
      )
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func compressVideo(
    inputPath: String,
    maxSide: Double,
    result: @escaping FlutterResult
  ) {
    let inputURL = URL(fileURLWithPath: inputPath)
    let asset = AVURLAsset(url: inputURL)

    let outputURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("forum_video_\(UUID().uuidString).mp4")

    try? FileManager.default.removeItem(at: outputURL)

    guard let exportSession = AVAssetExportSession(
      asset: asset,
      presetName: AVAssetExportPreset960x540
    ) else {
      result(FlutterError(
        code: "EXPORT_FAILED",
        message: "Cannot create AVAssetExportSession",
        details: nil
      ))
      return
    }

    exportSession.outputURL = outputURL
    exportSession.outputFileType = .mp4
    exportSession.shouldOptimizeForNetworkUse = true

    exportSession.exportAsynchronously {
      DispatchQueue.main.async {
        switch exportSession.status {
        case .completed:
          let durationSec = Int(CMTimeGetSeconds(asset.duration).rounded())
          let dims = Self.scaledDimensions(for: asset, maxSide: maxSide)
          result([
            "outputPath": outputURL.path,
            "width": dims.width,
            "height": dims.height,
            "duration": durationSec,
          ])
        case .failed:
          result(FlutterError(
            code: "EXPORT_FAILED",
            message: exportSession.error?.localizedDescription ?? "export failed",
            details: nil
          ))
        case .cancelled:
          result(FlutterError(
            code: "EXPORT_CANCELLED",
            message: "export cancelled",
            details: nil
          ))
        default:
          result(FlutterError(
            code: "EXPORT_FAILED",
            message: "unexpected export status",
            details: nil
          ))
        }
      }
    }
  }

  private static func scaledDimensions(
    for asset: AVAsset,
    maxSide: Double
  ) -> (width: Double, height: Double) {
    guard let track = asset.tracks(withMediaType: .video).first else {
      return (960, 540)
    }

    let transformed = track.naturalSize.applying(track.preferredTransform)
    var width = abs(transformed.width)
    var height = abs(transformed.height)

    if width <= 0 || height <= 0 {
      return (960, 540)
    }

    let scale = min(1.0, maxSide / max(width, height))
    width = floor((width * scale) / 2.0) * 2.0
    height = floor((height * scale) / 2.0) * 2.0
    return (width, height)
  }

  private func extractThumbnail(
    inputPath: String,
    outputPath: String,
    result: @escaping FlutterResult
  ) {
    extractThumbnailAsset(
      asset: AVURLAsset(url: URL(fileURLWithPath: inputPath)),
      outputPath: outputPath,
      result: result
    )
  }

  private func extractThumbnailFromUrl(
    inputUrl: String,
    outputPath: String,
    result: @escaping FlutterResult
  ) {
    guard let url = URL(string: inputUrl) else {
      result(FlutterError(code: "INVALID_ARGS", message: "bad url", details: nil))
      return
    }
    extractThumbnailAsset(
      asset: AVURLAsset(url: url),
      outputPath: outputPath,
      result: result
    )
  }

  private func extractThumbnailAsset(
    asset: AVURLAsset,
    outputPath: String,
    result: @escaping FlutterResult
  ) {
    DispatchQueue.global(qos: .userInitiated).async {
      let generator = AVAssetImageGenerator(asset: asset)
      generator.appliesPreferredTrackTransform = true
      generator.maximumSize = CGSize(width: 640, height: 640)
      // Иначе на remote HLS/mp4 часто берётся «ближайший» чёрный keyframe.
      generator.requestedTimeToleranceBefore = .zero
      generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

      let durationSec = CMTimeGetSeconds(asset.duration)
      // Короткие video note — быстро 1–2 кадра; длинные/канальные — несколько точек.
      let candidates: [Double]
      if durationSec.isFinite && durationSec > 0 && durationSec <= 60 {
        let mid = min(max(durationSec * 0.35, 0.15), max(durationSec - 0.05, 0))
        candidates = [mid, 0.0]
      } else {
        var long: [Double] = [1.0, 2.0, 3.0, 5.0]
        if durationSec.isFinite && durationSec > 0 {
          long.append(min(durationSec * 0.1, 15.0))
          long.append(min(durationSec * 0.25, 30.0))
        }
        long.append(0.0)
        candidates = long
      }

      var lastError: Error?
      var chosen: CGImage?

      for sec in candidates {
        if durationSec.isFinite && durationSec > 0.05 && sec >= durationSec {
          continue
        }
        let time = CMTime(seconds: max(0, sec), preferredTimescale: 600)
        do {
          let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
          if !Self.isMostlyBlack(cgImage) {
            chosen = cgImage
            break
          }
          // Чёрный — оставляем как fallback, ищем дальше.
          if chosen == nil {
            chosen = cgImage
          }
        } catch {
          lastError = error
        }
      }

      guard let cgImage = chosen else {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "THUMB_FAILED",
            message: lastError?.localizedDescription ?? "No frame",
            details: nil
          ))
        }
        return
      }

      let outURL = URL(fileURLWithPath: outputPath)
      try? FileManager.default.removeItem(at: outURL)

      guard let destination = CGImageDestinationCreateWithURL(
        outURL as CFURL,
        UTType.jpeg.identifier as CFString,
        1,
        nil
      ) else {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "THUMB_FAILED",
            message: "Cannot create image destination",
            details: nil
          ))
        }
        return
      }

      let options = [
        kCGImageDestinationLossyCompressionQuality: 0.75,
      ] as CFDictionary
      CGImageDestinationAddImage(destination, cgImage, options)
      guard CGImageDestinationFinalize(destination) else {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "THUMB_FAILED",
            message: "Cannot write JPEG",
            details: nil
          ))
        }
        return
      }

      DispatchQueue.main.async {
        result(outputPath)
      }
    }
  }

  /// Кадр «почти чёрный» (типичный intro у канальных mp4) — не годится в превью.
  private static func isMostlyBlack(_ image: CGImage) -> Bool {
    let width = min(image.width, 48)
    let height = min(image.height, 48)
    guard width > 0, height > 0 else { return true }

    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var data = [UInt8](repeating: 0, count: height * bytesPerRow)
    guard let ctx = CGContext(
      data: &data,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: bytesPerRow,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
      return false
    }
    ctx.interpolationQuality = .low
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    var sum = 0
    var count = 0
    var bright = 0
    let step = 2
    for y in stride(from: 0, to: height, by: step) {
      for x in stride(from: 0, to: width, by: step) {
        let i = y * bytesPerRow + x * bytesPerPixel
        let r = Int(data[i])
        let g = Int(data[i + 1])
        let b = Int(data[i + 2])
        let lum = (r + g + b) / 3
        sum += lum
        count += 1
        if lum > 40 { bright += 1 }
      }
    }
    guard count > 0 else { return true }
    let avg = sum / count
    // Чёрный кадр: низкая средняя яркость и почти нет светлых пикселей.
    return avg < 18 && bright * 100 / count < 3
  }
}
