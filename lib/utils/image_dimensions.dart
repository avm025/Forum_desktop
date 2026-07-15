import 'dart:typed_data';

/// Размер изображения из заголовка PNG/JPEG (без декодирования всего файла).
class ImageDimensions {
  final double width;
  final double height;

  const ImageDimensions(this.width, this.height);

  String get widthStr => _format(width);
  String get heightStr => _format(height);

  static String _format(double v) {
    if (v == v.roundToDouble()) return '${v.toInt()}.0';
    return v.toString();
  }
}

ImageDimensions? readImageDimensions(Uint8List bytes) {
  if (bytes.length >= 24 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    final w = _readUint32Be(bytes, 16);
    final h = _readUint32Be(bytes, 20);
    if (w > 0 && h > 0) return ImageDimensions(w.toDouble(), h.toDouble());
  }

  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
    return _readJpegDimensions(bytes);
  }

  return null;
}

int _readUint32Be(Uint8List bytes, int offset) {
  return (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
}

ImageDimensions? _readJpegDimensions(Uint8List bytes) {
  var i = 2;
  while (i + 9 < bytes.length) {
    if (bytes[i] != 0xFF) {
      i++;
      continue;
    }
    final marker = bytes[i + 1];
    if (marker == 0xD8 || marker == 0xD9) {
      i += 2;
      continue;
    }
    if (i + 3 >= bytes.length) break;
    final segmentLen = (bytes[i + 2] << 8) | bytes[i + 3];
    if (segmentLen < 2) break;

    const sofMarkers = {0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF};
    if (sofMarkers.contains(marker) && i + 8 < bytes.length) {
      final h = (bytes[i + 5] << 8) | bytes[i + 6];
      final w = (bytes[i + 7] << 8) | bytes[i + 8];
      if (w > 0 && h > 0) return ImageDimensions(w.toDouble(), h.toDouble());
      return null;
    }

    i += 2 + segmentLen;
  }
  return null;
}
