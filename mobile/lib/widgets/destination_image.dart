import 'package:flutter/material.dart';

/// Network image with a neutral placeholder for missing URLs, loading and errors.
class DestinationImage extends StatelessWidget {
  final String? url;
  final double? height;
  final double? width;
  final BorderRadius borderRadius;

  const DestinationImage({
    super.key,
    required this.url,
    this.height,
    this.width,
    this.borderRadius = BorderRadius.zero,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      height: height,
      width: width,
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(Icons.landscape_outlined, color: scheme.outline, size: 36),
    );

    return ClipRRect(
      borderRadius: borderRadius,
      child: url == null
          ? placeholder
          : Image.network(
              url!,
              height: height,
              width: width,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : placeholder,
              errorBuilder: (_, _, _) => placeholder,
            ),
    );
  }
}
