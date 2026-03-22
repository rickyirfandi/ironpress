import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:ironpress/ironpress.dart';

import 'stat_row.dart';

class BeforeAfterCard extends StatelessWidget {
  const BeforeAfterCard({
    super.key,
    required this.original,
    required this.compressed,
    required this.result,
  });

  final Uint8List original;
  final Uint8List compressed;
  final CompressResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 200,
            child: Row(
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(original, fit: BoxFit.cover),
                      Positioned(
                        left: 8,
                        top: 8,
                        child: _Chip(
                          label: 'Original',
                          detail: formatBytes(result.originalSize),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(width: 2, color: theme.dividerColor),
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(compressed, fit: BoxFit.cover),
                      Positioned(
                        left: 8,
                        top: 8,
                        child: _Chip(
                          label: 'Compressed',
                          detail: formatBytes(result.compressedSize),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                StatRow(
                  icon: Icons.compress,
                  label: 'Reduction',
                  value: result.reductionPercent,
                ),
                StatRow(
                  icon: Icons.photo_size_select_large,
                  label: 'Dimensions',
                  value: '${result.width} x ${result.height}',
                ),
                StatRow(
                  icon: Icons.tune,
                  label: 'Quality used',
                  value: 'q${result.qualityUsed}',
                ),
                if (result.iterations > 1)
                  StatRow(
                    icon: Icons.loop,
                    label: 'Iterations',
                    value: '${result.iterations}',
                  ),
                if (result.resizedToFit)
                  const StatRow(
                    icon: Icons.aspect_ratio,
                    label: 'Auto-resized',
                    value: 'Yes',
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.detail});

  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: const BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 10),
          ),
          Text(
            detail,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
