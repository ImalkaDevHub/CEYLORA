import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/destination.dart';
import '../providers/destinations_provider.dart';
import '../services/api_client.dart';
import '../utils/format.dart';
import '../widgets/destination_image.dart';

class DestinationDetailScreen extends StatefulWidget {
  final String destinationId;
  const DestinationDetailScreen({super.key, required this.destinationId});

  @override
  State<DestinationDetailScreen> createState() =>
      _DestinationDetailScreenState();
}

class _DestinationDetailScreenState extends State<DestinationDetailScreen> {
  late Future<DestinationSummary> _summary;

  @override
  void initState() {
    super.initState();
    _summary = _loadSummary();
  }

  Future<DestinationSummary> _loadSummary() =>
      context.read<DestinationsProvider>().summaryFor(widget.destinationId);

  void _retry() => setState(() => _summary = _loadSummary());

  @override
  Widget build(BuildContext context) {
    final destination =
        context.read<DestinationsProvider>().byId(widget.destinationId);
    final theme = Theme.of(context);

    if (destination == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Destination')),
        body: const Center(child: Text('This destination is no longer available.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(destination.name)),
      body: ListView(
        children: [
          DestinationImage(
              url: destination.imageUrl, height: 220, width: double.infinity),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(destination.name,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Icon(Icons.place_outlined, size: 18),
                    Text(destination.region),
                    Chip(
                      label: Text(categoryLabel(destination.category)),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (destination.description.isNotEmpty)
                  Text(destination.description,
                      style: theme.textTheme.bodyLarge),
                const SizedBox(height: 24),
                Text('Experiences',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                FutureBuilder<DestinationSummary>(
                  future: _summary,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (snap.hasError) {
                      final message = snap.error is ApiException
                          ? (snap.error as ApiException).message
                          : 'Could not load experience prices.';
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(message),
                          TextButton(
                              onPressed: _retry, child: const Text('Try again')),
                        ],
                      );
                    }
                    return _SummaryCard(summary: snap.data!);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final DestinationSummary summary;
  const _SummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (summary.experienceCount == 0) {
      return Text('No experiences listed yet.', style: theme.textTheme.bodyMedium);
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _Row('Experiences', '${summary.experienceCount}'),
            _Row('Cheapest', formatLkr(summary.minPrice)),
            _Row('Most expensive', formatLkr(summary.maxPrice)),
            _Row('Average', formatLkr(summary.averagePrice)),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
