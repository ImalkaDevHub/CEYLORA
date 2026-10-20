import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/bookings_provider.dart';
import '../screens/accommodations_screen.dart';
import '../screens/bookings_screen.dart';

/// "Stays" block on the trip screen: this trip's bookings and a way to add another.
class TripBookingsSection extends StatefulWidget {
  final String tripId;

  /// A cancelled trip cannot take new bookings.
  final bool canBook;
  const TripBookingsSection(
      {super.key, required this.tripId, required this.canBook});

  @override
  State<TripBookingsSection> createState() => _TripBookingsSectionState();
}

class _TripBookingsSectionState extends State<TripBookingsSection> {
  @override
  void initState() {
    super.initState();
    // The bookings list is shared; load it the first time a trip needs it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final p = context.read<BookingsProvider>();
      if (p.items.isEmpty) p.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bookings = context.watch<BookingsProvider>().forTrip(widget.tripId);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                  bookings.isEmpty ? 'Stays' : 'Stays (${bookings.length})',
                  style: theme.textTheme.titleMedium),
            ),
            if (widget.canBook)
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => AccommodationsScreen(tripId: widget.tripId))),
                icon: const Icon(Icons.hotel_outlined),
                label: const Text('Book a stay'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (bookings.isEmpty)
          Text('No stays booked for this trip yet.',
              style: theme.textTheme.bodyMedium)
        else
          for (final b in bookings)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: BookingCard(booking: b),
            ),
      ],
    );
  }
}
