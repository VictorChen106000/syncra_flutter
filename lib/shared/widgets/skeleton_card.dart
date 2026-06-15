import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/theme/brand_theme.dart';

/// Generic shimmering placeholder for any list page during data fetches.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, this.height = 96, this.borderRadius = 20});

  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Shimmer.fromColors(
        baseColor: brand.border.withValues(alpha: 0.45),
        highlightColor: brand.surface,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: brand.surface,
            borderRadius: BorderRadius.circular(borderRadius),
          ),
        ),
      ),
    );
  }
}

class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 3, this.itemHeight = 96});

  final int count;
  final double itemHeight;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < count; i++) SkeletonCard(height: itemHeight),
      ],
    );
  }
}
