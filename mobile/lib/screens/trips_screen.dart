import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/trip.dart';
import '../providers/trips_provider.dart';
import '../utils/format.dart';
import '../widgets/status_chip.dart';
import 'create_trip_screen.dart';
import 'trip_detail_screen.dart';

/// "My Trips" tab body: list with pull-to-refresh and a create button.
class TripsScreen extends StatelessWidget {
  const TripsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final trips = context.watch<TripsProvider>();

    Widget body;
    if (trips.state == LoadState.loading && trips.trips.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (trips.state == LoadState.failed && trips.trips.isEmpty) {
      body = _Message(
        icon: Icons.cloud_off,
        text: trips.error ?? 'Could not load your trips.',
        action: FilledButton(
            onPressed: trips.load, child: const Text('Try again')),
      );
    } else if (trips.trips.isEmpty) {
      body = const _Message(
        icon: Icons.luggage_outlined,
        text: 'No trips yet. Tap "New trip" to plan your first one.',
      );
    } else {
      body = ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        itemCount: trips.trips.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _TripCard(trip: trips.trips[i]),
      );
    }

    return Scaffold(
      body: RefreshIndicator(onRefresh: trips.load, child: body),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CreateTripScreen())),
        icon: const Icon(Icons.add),
        label: const Text('New trip'),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  final Trip trip;
  const _TripCard({required this.trip});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => TripDetailScreen(tripId: trip.id))),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(trip.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 8),
                  StatusChip(trip.status),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                  '${formatDate(trip.startDate)} → ${formatDate(trip.endDate)}'
                  ' · ${trip.days} ${trip.days == 1 ? 'day' : 'days'}',
                  style: theme.textTheme.bodyMedium),
              const SizedBox(height: 4),
              Text(formatLkr(trip.budget), style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;
  const _Message({required this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    // ListView so pull-to-refresh still works on the empty/error states.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 80),
        Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
        const SizedBox(height: 16),
        Text(text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge),
        if (action != null) ...[const SizedBox(height: 16), Center(child: action)],
      ],
    );
  }
}
