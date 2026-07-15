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

      do {
        let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
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
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "THUMB_FAILED",
            message: error.localizedDescription,
            details: nil
          ))
        }
      }
    }
  }
}
