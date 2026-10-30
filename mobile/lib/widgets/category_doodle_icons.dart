import 'package:flutter/material.dart';

/// Renders real high-quality 3D category images for Workmate4u task categories.
class CategoryDoodleIcon extends StatelessWidget {
  final String categoryId;
  final double size;
  final double borderRadius;
  final Color? color;

  const CategoryDoodleIcon({
    super.key,
    required this.categoryId,
    this.size = 28,
    this.borderRadius = 8,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final key = _normalize(categoryId);
    final assetPath = 'assets/images/categories/$key.png';

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        errorBuilder: (context, error, stackTrace) {
          return Image.asset(
            'assets/images/categories/$key.jpg',
            width: size,
            height: size,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, __, ___) {
              return Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(borderRadius),
                ),
                child: Center(
                  child: Icon(
                    Icons.dashboard_rounded,
                    size: size * 0.55,
                    color: const Color(0xFF4F46E5),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  static String _normalize(String input) {
    final lower = input.toLowerCase().trim();
    if (lower == 'repair' ||
        lower == 'engineering & repair' ||
        lower == 'engineering_repair') {
      return 'repair';
    }
    return lower
        .replaceAll('&', '')
        .replaceAll('  ', ' ')
        .trim()
        .replaceAll(' ', '_');
  }
}
