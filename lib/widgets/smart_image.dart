import 'dart:io';
import 'package:flutter/material.dart';
import '../services/content_package_service.dart';

class SmartImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  // NEW — lets callers show something more meaningful than a generic
  // "broken image" icon when the file is missing or fails to load (e.g.
  // an industry-specific icon instead).
  final Widget? errorWidget;

  const SmartImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: ContentPackageService.instance.resolveLocalPath(url),
      builder: (context, snapshot) {
        final localPath = snapshot.data;

        if (localPath != null) {
          return Image.file(
            File(localPath),
            width: width,
            height: height,
            fit: fit,
            errorBuilder: (context, error, stackTrace) =>
            errorWidget ?? const Icon(Icons.image_not_supported, color: Colors.grey),
          );
        }

        return Image.network(
          url,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (context, error, stackTrace) =>
          errorWidget ?? const Icon(Icons.image_not_supported, color: Colors.grey),
        );
      },
    );
  }
}
