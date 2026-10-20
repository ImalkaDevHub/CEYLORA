import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/booking.dart';
import '../providers/bookings_provider.dart';
import '../utils/format.dart';
import '../widgets/booking_status_chip.dart';
import '../widgets/review_dialog.dart';
import 'accommodation_detail_screen.dart';

class BookingDetailScreen extends StatelessWidget {
  final String bookingId;
  const BookingDetailScreen({super.key, required this.bookingId});

  Future<void> _cancel(BuildContext context) async {
    final provider = context.read<BookingsProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Cancel this booking?'),
        content: const Text('The rooms will be released for other travelers.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialog).pop(false),
              child: const Text('Keep booking')),
          FilledButton(
              onPressed: () => Navigator.of(dialog).pop(true),
              child: const Text('Cancel booking')),
        ],
      ),
    );
    if (confirmed != true) return;

    final error = await provider.cancel(bookingId);
    messenger.showSnackBar(SnackBar(content: Text(error ?? 'Booking cancelled.')));
  }

  Future<void> _review(BuildContext context, BookingItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    final saved = await showReviewDialog(context,
        accommodationId: item.accommodationId,
        accommodationName: item.accommodationName);
    if (saved == true) {
      messenger.showSnackBar(const SnackBar(content: Text('Thanks for your review!')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BookingsProvider>();
    final booking = provider.byId(bookingId);
    final theme = Theme.of(context);

    if (booking == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Booking')),
        body: const Center(child: Text('This booking is no longer available.')),
      );
    }

    final cancelling = provider.isCancelling(booking.id);
    final today = DateTime.now();

    return Scaffold(
      appBar: AppBar(title: const Text('Booking details')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(formatLkr(booking.totalAmount),
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ),
                BookingStatusChip(booking.status),
              ],
            ),
            const SizedBox(height: 8),
            Text('For ${booking.tripTitle}', style: theme.textTheme.bodyLarge),
            Text('Booked ${formatDate(booking.createdAt)}',
                style: theme.textTheme.bodySmall),
            if (booking.isCancelled && booking.cancelledAt != null)
              Text('Cancelled ${formatDate(booking.cancelledAt!)}',
                  style: theme.textTheme.bodySmall),
            if (booking.notes != null && booking.notes!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Notes: ${booking.notes}', style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: 24),
            Text('Stays', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final item in booking.items)
              _ItemCard(
                item: item,
                canReview: booking.isConfirmed && item.hasEnded(today),
                onReview: () => _review(context, item),
              ),
            const SizedBox(height: 16),
            if (booking.isConfirmed)
              OutlinedButton.icon(
                onPressed: cancelling ? null : () => _cancel(context),
                icon: cancelling
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.cancel_outlined),
                label: const Text('Cancel booking'),
              ),
          ],
        ),
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  final BookingItem item;
  final bool canReview;
  final VoidCallback onReview;
  const _ItemCard(
      {required this.item, required this.canReview, required this.onReview});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.accommodationName,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            if (item.destinationName.isNotEmpty)
              Text(item.destinationName, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Text(
                '${formatPickedDate(item.checkIn)} → ${formatPickedDate(item.checkOut)} · ${item.nights} night${item.nights == 1 ? '' : 's'}',
                style: theme.textTheme.bodyMedium),
            Text(
                '${item.rooms} room${item.rooms == 1 ? '' : 's'} · ${item.guests} guest${item.guests == 1 ? '' : 's'}',
                style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text('${formatLkr(item.nightlyRate)} per room per night',
                style: theme.textTheme.bodySmall),
            Text('Subtotal ${formatLkr(item.subtotal)}',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => AccommodationDetailScreen(
                          accommodationId: item.accommodationId))),
                  child: const Text('View stay'),
                ),
                if (canReview)
                  TextButton(
                      onPressed: onReview, child: const Text('Write a review')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
