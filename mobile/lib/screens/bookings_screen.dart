import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/booking.dart';
import '../providers/bookings_provider.dart';
import '../providers/trips_provider.dart' show LoadState;
import '../utils/format.dart';
import '../widgets/booking_status_chip.dart';
import 'booking_detail_screen.dart';

/// "My bookings": every booking the traveler has made, newest first.
class BookingsScreen extends StatefulWidget {
  const BookingsScreen({super.key});

  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<BookingsProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<BookingsProvider>();

    Widget body;
    if (p.state == LoadState.loading && p.items.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (p.state == LoadState.failed && p.items.isEmpty) {
      body = _Message(
        icon: Icons.cloud_off,
        text: p.error ?? 'Could not load your bookings.',
        action: FilledButton(onPressed: p.load, child: const Text('Try again')),
      );
    } else if (p.items.isEmpty) {
      body = const _Message(
        icon: Icons.event_busy_outlined,
        text: 'No bookings yet. Find a stay in the Stays tab and book it for a trip.',
      );
    } else {
      body = ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: p.items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) => BookingCard(booking: p.items[i]),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('My bookings')),
      body: RefreshIndicator(onRefresh: p.load, child: body),
    );
  }
}

/// One booking as a tappable card (used here and on the trip screen).
class BookingCard extends StatelessWidget {
  final Booking booking;
  const BookingCard({super.key, required this.booking});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final first = booking.items.isEmpty ? null : booking.items.first;
    final more = booking.items.length - 1;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => BookingDetailScreen(bookingId: booking.id))),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                        first == null
                            ? 'Booking'
                            : more > 0
                                ? '${first.accommodationName} + $more more'
                                : first.accommodationName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 8),
                  BookingStatusChip(booking.status),
                ],
              ),
              const SizedBox(height: 4),
              if (booking.items.isNotEmpty)
                Text(
                    '${formatPickedDate(booking.firstCheckIn)} → ${formatPickedDate(booking.lastCheckOut)}',
                    style: theme.textTheme.bodyMedium),
              const SizedBox(height: 2),
              Text('For ${booking.tripTitle}', style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              Text(formatLkr(booking.totalAmount),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
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
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 60),
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
