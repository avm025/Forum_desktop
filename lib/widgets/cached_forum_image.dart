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
  /// Нейтральный фон вместо градиента/иконки на время загрузки.
  final bool blankWhileLoading;
  /// Свой placeholder (например, уже готовый thumbnail).
  final Widget? placeholder;
  final Duration fadeInDuration;
  final Duration fadeOutDuration;

  const CachedForumImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.blankWhileLoading = false,
    this.placeholder,
    this.fadeInDuration = const Duration(milliseconds: 500),
    this.fadeOutDuration = const Duration(milliseconds: 1000),
  });

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return _loadingPlaceholder(width, height);
    }

    Widget image = CachedNetworkImage(
      imageUrl: url,
      httpHeaders: ApiConfig.fileHeaders,
      width: width,
      height: height,
      fit: fit,
      fadeInDuration: fadeInDuration,
      fadeOutDuration: fadeOutDuration,
      placeholder: (_, __) => _loadingPlaceholder(width, height),
      errorWidget: (_, __, ___) => _errorPlaceholder(width, height),
    );

    if (borderRadius != null) {
      image = ClipRRect(borderRadius: borderRadius!, child: image);
    }
    return image;
  }

  Widget _loadingPlaceholder(double? w, double? h) {
    if (placeholder != null) {
      return SizedBox(width: w, height: h, child: placeholder);
    }
    if (blankWhileLoading) {
      return SizedBox(
        width: w,
        height: h,
        child: const ColoredBox(color: Colors.transparent),
      );
    }
    return _decoratedPlaceholder(w, h, error: false);
  }

  Widget _errorPlaceholder(double? w, double? h) {
    return _decoratedPlaceholder(w, h, error: true);
  }

  Widget _decoratedPlaceholder(double? w, double? h, {required bool error}) {
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
