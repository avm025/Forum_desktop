import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/api_config.dart';
import '../theme/app_colors.dart';

/// Изображение с дисковым кэшем (cached_network_image).
/// Если файл уже в кэше — повторно с сервера не загружается.
class CachedForumImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  const CachedForumImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return _placeholder(width, height);
    }

    Widget image = CachedNetworkImage(
      imageUrl: url,
      httpHeaders: ApiConfig.fileHeaders,
      width: width,
      height: height,
      fit: fit,
      placeholder: (_, __) => _placeholder(width, height),
      errorWidget: (_, __, ___) => _placeholder(width, height, error: true),
    );

    if (borderRadius != null) {
      image = ClipRRect(borderRadius: borderRadius!, child: image);
    }
    return image;
  }

  Widget _placeholder(double? w, double? h, {bool error = false}) {
    final gradient = AppColors.avatarGradientFor(url);
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: Icon(
        error ? Icons.broken_image_outlined : Icons.image_outlined,
        color: Colors.white54,
        size: (w != null && h != null) ? (w < h ? w : h) * 0.35 : 40,
      ),
    );
  }
}
