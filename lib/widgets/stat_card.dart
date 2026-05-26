import 'package:flutter/material.dart';

import '../theme/eve_palette.dart';

class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: EvePalette.coal,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                color: EvePalette.bone,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: EvePalette.muted)),
          ],
        ),
      ),
    );
  }
}
