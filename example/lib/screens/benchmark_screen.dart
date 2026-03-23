import 'package:flutter/material.dart';
import 'package:ironpress/ironpress.dart';

import '../shared/stat_row.dart';
import '../shared/test_image.dart';

class BenchmarkScreen extends StatefulWidget {
  const BenchmarkScreen({super.key});

  @override
  State<BenchmarkScreen> createState() => _BenchmarkScreenState();
}

class _BenchmarkScreenState extends State<BenchmarkScreen> {
  bool _loading = false;
  BenchmarkResult? _bench;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() => _loading = true);
    try {
      final bytes = await loadTestImage();
      final bench = await Ironpress.benchmarkBytes(bytes);
      setState(() => _bench = bench);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Benchmark')),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _bench == null
              ? const Center(child: Text('No data'))
              : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Image Info',
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            StatRow(
                              icon: Icons.image,
                              label: 'Format',
                              value: _bench!.format.name,
                            ),
                            StatRow(
                              icon: Icons.photo_size_select_large,
                              label: 'Dimensions',
                              value: '${_bench!.width} x ${_bench!.height}',
                            ),
                            StatRow(
                              icon: Icons.storage,
                              label: 'Original size',
                              value: formatBytes(_bench!.originalSize),
                            ),
                            StatRow(
                              icon: Icons.star,
                              label: 'Recommended quality',
                              value: 'q${_bench!.recommendedQuality}',
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Quality Sweep', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    // Bar chart
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            for (final entry in _bench!.entries)
                              _BarRow(
                                entry: entry,
                                maxSize: _bench!.originalSize,
                                isRecommended:
                                    entry.quality == _bench!.recommendedQuality,
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Data table
                    Card(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Quality')),
                            DataColumn(label: Text('Size')),
                            DataColumn(label: Text('Reduction')),
                            DataColumn(label: Text('Time')),
                          ],
                          rows: [
                            for (final entry in _bench!.entries)
                              DataRow(
                                color:
                                    entry.quality == _bench!.recommendedQuality
                                        ? WidgetStateProperty.all(
                                          theme.colorScheme.primaryContainer
                                              .withAlpha(80),
                                        )
                                        : null,
                                cells: [
                                  DataCell(Text('q${entry.quality}')),
                                  DataCell(Text(entry.sizeFormatted)),
                                  DataCell(Text(entry.reductionPercent)),
                                  DataCell(Text('${entry.encodeMs} ms')),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
    );
  }
}

class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.entry,
    required this.maxSize,
    required this.isRecommended,
  });

  final BenchmarkEntry entry;
  final int maxSize;
  final bool isRecommended;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = maxSize > 0 ? entry.sizeBytes / maxSize : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              'q${entry.quality}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: isRecommended ? FontWeight.bold : FontWeight.normal,
                color: isRecommended ? theme.colorScheme.primary : null,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Stack(
              children: [
                Container(
                  height: 18,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: fraction.clamp(0.0, 1.0),
                  child: Container(
                    height: 18,
                    decoration: BoxDecoration(
                      color:
                          isRecommended
                              ? theme.colorScheme.primary
                              : theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 56,
            child: Text(
              entry.sizeFormatted,
              style: const TextStyle(fontSize: 11),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
