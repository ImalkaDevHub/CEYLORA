import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/trips_provider.dart';
import '../utils/format.dart';
import '../widgets/status_chip.dart';
import '../widgets/trip_photos_section.dart';

class TripDetailScreen extends StatelessWidget {
  final String tripId;
  const TripDetailScreen({super.key, required this.tripId});

  Future<void> _submit(BuildContext context) async {
    final provider = context.read<TripsProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final error = await provider.submit(tripId);
    messenger.showSnackBar(SnackBar(
      content: Text(error ?? 'Trip submitted.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TripsProvider>();
    final trip = provider.byId(tripId);
    final theme = Theme.of(context);

    if (trip == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Trip')),
        body: const Center(child: Text('This trip is no longer available.')),
      );
    }

    final submitting = provider.isSubmitting(trip.id);

    return Scaffold(
      appBar: AppBar(title: const Text('Trip details')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(trip.title,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                StatusChip(trip.status),
              ],
            ),
            const SizedBox(height: 24),
            _InfoRow(
                icon: Icons.event,
                label: 'Dates',
                value:
                    '${formatDate(trip.startDate)} → ${formatDate(trip.endDate)}'),
            _InfoRow(
                icon: Icons.schedule,
                label: 'Length',
                value: '${trip.days} ${trip.days == 1 ? 'day' : 'days'}'),
            _InfoRow(
                icon: Icons.payments_outlined,
                label: 'Budget',
                value: formatLkr(trip.budget)),
            if (trip.travelerName.isNotEmpty)
              _InfoRow(
                  icon: Icons.person_outline,
                  label: 'Traveler',
                  value: trip.travelerName),
            const SizedBox(height: 24),
            if (trip.isDraft)
              FilledButton.icon(
                onPressed: submitting ? null : () => _submit(context),
                icon: submitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send),
                label: const Text('Submit trip'),
              )
            else
              Text(
                'This trip is ${trip.status.toLowerCase()} and can no longer be edited.',
                style: theme.textTheme.bodyMedium,
              ),
            const SizedBox(height: 32),
            TripPhotosSection(tripId: trip.id),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          SizedBox(
              width: 80,
              child: Text(label, style: theme.textTheme.bodySmall)),
          Expanded(child: Text(value, style: theme.textTheme.bodyLarge)),
        ],
      ),
    );
  }
}
