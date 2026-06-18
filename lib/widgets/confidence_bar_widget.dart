import 'package:flutter/material.dart';

/// Horizontal confidence bar for a single class probability.
class ConfidenceBarWidget extends StatelessWidget {
  final String label;
  final double probability; // 0.0–1.0
  final bool isSelected;

  const ConfidenceBarWidget({
    super.key,
    required this.label,
    required this.probability,
    this.isSelected = false,
  });

  Color _barColor() {
    if (probability < 0.50) return Colors.green;
    if (probability < 0.75) return Colors.amber;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              Text('${(probability * 100).toStringAsFixed(1)}%'),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: probability,
            backgroundColor: Colors.grey.shade200,
            color: _barColor(),
            minHeight: 8,
          ),
        ],
      ),
    );
  }
}
