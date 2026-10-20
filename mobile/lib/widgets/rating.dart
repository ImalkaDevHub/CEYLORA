import 'package:flutter/material.dart';

/// "★ 4.3 (12)" or "No reviews yet".
class RatingSummary extends StatelessWidget {
  final double? rating;
  final int count;
  const RatingSummary({super.key, required this.rating, required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (rating == null || count == 0) {
      return Text('No reviews yet', style: theme.textTheme.bodySmall);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.star, size: 16, color: Color(0xFFF59E0B)),
        const SizedBox(width: 4),
        Text(rating!.toStringAsFixed(1),
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(width: 4),
        Text('($count)', style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// Five filled/outlined stars for a whole-number rating.
class StarRow extends StatelessWidget {
  final int rating;
  final double size;
  const StarRow({super.key, required this.rating, this.size = 16});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(i <= rating ? Icons.star : Icons.star_border,
              size: size, color: const Color(0xFFF59E0B)),
      ],
    );
  }
}

/// Tap a star to choose 1–5.
class StarPicker extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const StarPicker({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 1; i <= 5; i++)
          IconButton(
            tooltip: '$i ${i == 1 ? 'star' : 'stars'}',
            onPressed: () => onChanged(i),
            icon: Icon(i <= value ? Icons.star : Icons.star_border,
                size: 32, color: const Color(0xFFF59E0B)),
          ),
      ],
    );
  }
}
