import 'dart:math' as math;

import '../models/media_file.dart';

/// Прямоугольник плитки в альбоме медиа (порт MediaMessageCell.swift).
class MediaTileRect {
  final double left;
  final double top;
  final double width;
  final double height;
  final double playIconSize;

  const MediaTileRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    this.playIconSize = 40,
  });
}

/// Раскладка превью для 1–10 медиа-файлов в одном сообщении.
class MediaMessageLayout {
  static const maxFiles = 10;
  static const maxPreviewHeight = 560.0;

  final double totalWidth;
  final double totalHeight;
  final List<MediaTileRect> tiles;

  const MediaMessageLayout({
    required this.totalWidth,
    required this.totalHeight,
    required this.tiles,
  });

  static double _aspect(MediaFile file) {
    final w = file.widthValue;
    final h = file.heightValue;
    if (w <= 0 || h <= 0) return 1;
    return w / h;
  }

  /// Ряды без пустот: каждая строка на всю [width], последний тайл ряда
  /// забирает остаток пикселей (без щели справа).
  static MediaMessageLayout justified({
    required List<MediaFile> files,
    required double width,
    double gap = 2,
    double targetRowHeight = 168,
  }) {
    final list = files.take(maxFiles).toList();
    if (list.isEmpty) {
      return const MediaMessageLayout(totalWidth: 0, totalHeight: 0, tiles: []);
    }
    if (list.length == 1) {
      return _layout1(list.first, width, maxPreviewHeight);
    }

    final aspects = [
      for (final f in list) _aspect(f).clamp(0.2, 5.0),
    ];
    final rows = <List<int>>[];
    var row = <int>[];
    var aspectSum = 0.0;

    for (var i = 0; i < list.length; i++) {
      final a = aspects[i];
      final nextSum = aspectSum + a;
      final gaps = row.isEmpty ? 0.0 : row.length * gap;
      final rowWidthAtTarget = nextSum * targetRowHeight + gaps;
      if (row.isNotEmpty && rowWidthAtTarget > width) {
        rows.add(row);
        row = <int>[i];
        aspectSum = a;
      } else {
        row.add(i);
        aspectSum = nextSum;
      }
    }
    if (row.isNotEmpty) rows.add(row);

    final tiles = List<MediaTileRect?>.filled(list.length, null);
    var y = 0.0;
    for (var r = 0; r < rows.length; r++) {
      final indices = rows[r];
      final gapsTotal = (indices.length - 1) * gap;
      var sumA = 0.0;
      for (final i in indices) {
        sumA += aspects[i];
      }
      final usable = (width - gapsTotal).clamp(1.0, width);
      // Высота из пропорций; при упоре в max — всё равно делим ширину без дыр.
      final height = (usable / sumA).clamp(48.0, maxPreviewHeight);

      var x = 0.0;
      for (var k = 0; k < indices.length; k++) {
        final i = indices[k];
        final isLast = k == indices.length - 1;
        final w = isLast
            ? (width - x).clamp(1.0, width)
            : (usable * (aspects[i] / sumA));
        tiles[i] = MediaTileRect(
          left: x,
          top: y,
          width: w,
          height: height,
          playIconSize: height < 96 ? 32 : 44,
        );
        x += w + gap;
      }
      y += height + (r == rows.length - 1 ? 0 : gap);
    }

    return MediaMessageLayout(
      totalWidth: width,
      totalHeight: y,
      tiles: [
        for (final t in tiles) t!,
      ],
    );
  }

  static MediaMessageLayout compute({
    required List<MediaFile> files,
    required double width,
    required bool albumLandscape,
    double maxHeight = maxPreviewHeight,
  }) {
    final count = files.length.clamp(1, maxFiles);
    final list = files.take(count).toList();

    switch (count) {
      case 1:
        return _layout1(list.first, width, maxHeight);
      case 2:
        return _layout2(list, width, maxHeight);
      case 3:
        return _layout3(list, width, albumLandscape);
      case 4:
        return _layout4(width);
      case 5:
        return _layout5(width, albumLandscape);
      case 6:
        return _layout6(width);
      case 7:
        return _layout7(width, albumLandscape);
      case 8:
        return _layout8(width);
      case 9:
        return _layout9(width);
      default:
        return _layout10(width);
    }
  }

  static MediaMessageLayout _layout1(MediaFile file, double maxWidth, double maxHeight) {
    final aspect = _aspect(file).clamp(0.2, 5.0);
    final iw = file.widthValue;
    final ih = file.heightValue;

    double previewWidth;
    if (iw > 0 && ih > 0) {
      final scale = math.min(maxWidth / iw, maxHeight / ih);
      previewWidth = (iw * math.min(scale, 1.0)).clamp(48.0, maxWidth);
      if (scale < 1.0) previewWidth = (iw * scale).clamp(48.0, maxWidth);
    } else {
      previewWidth = math.min(280.0, maxWidth);
    }

    final imageHeight = (previewWidth / aspect).clamp(48.0, maxHeight);
    final w = math.min(previewWidth, imageHeight * aspect);
    return MediaMessageLayout(
      totalWidth: w,
      totalHeight: imageHeight,
      tiles: [
        MediaTileRect(
          left: 0,
          top: 0,
          width: w,
          height: imageHeight,
          playIconSize: 60,
        ),
      ],
    );
  }

  static MediaMessageLayout _layout2(
    List<MediaFile> files,
    double width,
    double maxHeight,
  ) {
    final ar1 = _aspect(files[0]);
    final ar2 = _aspect(files[1]);
    final horizontal = ar1 > 1 && ar2 > 1;

    if (horizontal) {
      final h1 = (width / ar1).clamp(0.0, maxHeight / 2);
      final h2 = (width / ar2).clamp(0.0, maxHeight / 2);
      return MediaMessageLayout(
        totalWidth: width,
        totalHeight: h1 + h2,
        tiles: [
          MediaTileRect(left: 0, top: 0, width: width, height: h1),
          MediaTileRect(left: 0, top: h1, width: width, height: h2),
        ],
      );
    }

    final sharedHeight = (width / (ar1 + ar2)).clamp(0.0, maxHeight);
    final w1 = sharedHeight * ar1;
    final w2 = sharedHeight * ar2;
    return MediaMessageLayout(
      totalWidth: width,
      totalHeight: sharedHeight,
      tiles: [
        MediaTileRect(left: 0, top: 0, width: w1, height: sharedHeight),
        MediaTileRect(left: w1, top: 0, width: w2, height: sharedHeight),
      ],
    );
  }

  static MediaMessageLayout _layout3(
    List<MediaFile> files,
    double width,
    bool albumLandscape,
  ) {
    final tiles = <MediaTileRect>[];
    for (var i = 0; i < 3; i++) {
      if (i == 0) {
        if (albumLandscape) {
          tiles.add(MediaTileRect(left: 0, top: 0, width: width, height: width / 2));
        } else {
          tiles.add(MediaTileRect(left: 0, top: 0, width: width / 2, height: width));
        }
      } else if (albumLandscape) {
        tiles.add(MediaTileRect(
          left: width / 2 * (i - 1),
          top: width / 2,
          width: width / 2,
          height: width / 2,
        ));
      } else {
        tiles.add(MediaTileRect(
          left: width / 2,
          top: width / 2 * (i - 1),
          width: width / 2,
          height: width / 2,
        ));
      }
    }
    return MediaMessageLayout(totalWidth: width, totalHeight: width, tiles: tiles);
  }

  static MediaMessageLayout _layout4(double width) {
    final half = width / 2;
    return MediaMessageLayout(
      totalWidth: width,
      totalHeight: width,
      tiles: [
        for (var i = 0; i < 4; i++)
          MediaTileRect(
            left: half * (i < 2 ? i : i - 2),
            top: i < 2 ? 0 : half,
            width: half,
            height: half,
          ),
      ],
    );
  }

  static MediaMessageLayout _layout5(double width, bool albumLandscape) {
    final half = width / 2;
    final totalHeight = width + half;
    final tiles = <MediaTileRect>[];

    for (var i = 0; i < 5; i++) {
      if (i == 0) {
        if (albumLandscape) {
          tiles.add(MediaTileRect(left: 0, top: 0, width: width, height: half));
        } else {
          tiles.add(MediaTileRect(left: 0, top: 0, width: half, height: width));
        }
      } else if (albumLandscape) {
        if (i < 3) {
          tiles.add(MediaTileRect(
            left: half * (i - 1),
            top: half,
            width: half,
            height: half,
          ));
        } else {
          tiles.add(MediaTileRect(
            left: half * (i - 3),
            top: width,
            width: half,
            height: half,
          ));
        }
      } else if (i < 3) {
        tiles.add(MediaTileRect(
          left: half,
          top: half * (i - 1),
          width: half,
          height: half,
        ));
      } else {
        tiles.add(MediaTileRect(
          left: half * (i - 3),
          top: width,
          width: half,
          height: half,
        ));
      }
    }

    return MediaMessageLayout(
      totalWidth: width,
      totalHeight: totalHeight,
      tiles: tiles,
    );
  }

  static MediaMessageLayout _layout6(double width) {
    final half = width / 2;
    final totalHeight = width + half;
    final tiles = <MediaTileRect>[];

    for (var i = 0; i < 6; i++) {
      double top;
      double left;
      if (i < 2) {
        top = 0;
        left = half * i;
      } else if (i < 4) {
        top = half;
        left = half * (i - 2);
      } else {
        top = width;
        left = half * (i - 4);
      }
      tiles.add(MediaTileRect(left: left, top: top, width: half, height: half));
    }

    return MediaMessageLayout(
      totalWidth: width,
      totalHeight: totalHeight,
      tiles: tiles,
    );
  }

  static MediaMessageLayout _layout7(double width, bool albumLandscape) {
    final half = width / 2;
    final quarter = width / 4;
    final totalHeight = width + quarter;
    final tiles = <MediaTileRect>[];

    for (var i = 0; i < 7; i++) {
      if (i == 0) {
        if (albumLandscape) {
          tiles.add(MediaTileRect(left: 0, top: 0, width: width, height: half));
        } else {
          tiles.add(MediaTileRect(left: 0, top: 0, width: half, height: width));
        }
      } else if (i < 3) {
        if (albumLandscape) {
          tiles.add(MediaTileRect(
            left: half * (i - 1),
            top: half,
            width: half,
            height: half,
          ));
        } else {
          tiles.add(MediaTileRect(
            left: half,
            top: half * (i - 1),
            width: half,
            height: half,
          ));
        }
      } else {
        tiles.add(MediaTileRect(
          left: quarter * (i - 3),
          top: width,
          width: quarter,
          height: quarter,
          playIconSize: 32,
        ));
      }
    }

    return MediaMessageLayout(
      totalWidth: width,
      totalHeight: totalHeight,
      tiles: tiles,
    );
  }

  static MediaMessageLayout _layout8(double width) {
    final half = width / 2;
    final quarter = width / 4;
    final totalHeight = width + quarter;
    final tiles = <MediaTileRect>[];

    for (var i = 0; i < 8; i++) {
      if (i < 2) {
        tiles.add(MediaTileRect(
          left: half * i,
          top: 0,
          width: half,
          height: half,
        ));
      } else if (i < 4) {
        tiles.add(MediaTileRect(
          left: half * (i - 2),
          top: half,
          width: half,
          height: half,
        ));
      } else {
        tiles.add(MediaTileRect(
          left: quarter * (i - 4),
          top: width,
          width: quarter,
          height: quarter,
          playIconSize: 32,
        ));
      }
    }

    return MediaMessageLayout(
      totalWidth: width,
      totalHeight: totalHeight,
      tiles: tiles,
    );
  }

  static MediaMessageLayout _layout9(double width) {
    final quarter = width / 4;
    final totalHeight = width + halfWidth(width);
    final tiles = <MediaTileRect>[];

    for (var i = 0; i < 9; i++) {
      if (i == 0) {
        tiles.add(MediaTileRect(
          left: 0,
          top: 0,
          width: width,
          height: width,
          playIconSize: 40,
        ));
      } else if (i < 5) {
        tiles.add(MediaTileRect(
          left: quarter * (i - 1),
          top: width,
          width: quarter,
          height: quarter,
          playIconSize: 32,
        ));
      } else {
        tiles.add(MediaTileRect(
          left: quarter * (i - 5),
          top: width + quarter,
          width: quarter,
          height: quarter,
          playIconSize: 32,
        ));
      }
    }

    return MediaMessageLayout(
      totalWidth: width,
      totalHeight: totalHeight,
      tiles: tiles,
    );
  }

  static MediaMessageLayout _layout10(double width) {
    final half = width / 2;
    final quarter = width / 4;
    final tiles = <MediaTileRect>[];

    for (var i = 0; i < 10; i++) {
      if (i < 2) {
        tiles.add(MediaTileRect(
          left: half * i,
          top: 0,
          width: half,
          height: half,
          playIconSize: i < 2 ? 40 : 32,
        ));
      } else if (i < 6) {
        tiles.add(MediaTileRect(
          left: quarter * (i - 2),
          top: half,
          width: quarter,
          height: quarter,
          playIconSize: 32,
        ));
      } else {
        tiles.add(MediaTileRect(
          left: quarter * (i - 6),
          top: half + quarter,
          width: quarter,
          height: quarter,
          playIconSize: 32,
        ));
      }
    }

    return MediaMessageLayout(
      totalWidth: width,
      totalHeight: width,
      tiles: tiles,
    );
  }

  static double halfWidth(double width) => width / 2;
}

/// Альбом «широкий», если суммарная ширина больше высоты (как model.size в iOS).
bool mediaAlbumIsLandscape(List<MediaFile> files) {
  var totalW = 0.0;
  var totalH = 0.0;
  for (final f in files) {
    totalW += f.widthValue > 0 ? f.widthValue : 1;
    totalH += f.heightValue > 0 ? f.heightValue : 1;
  }
  return totalW > totalH;
}
