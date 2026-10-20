import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/review.dart';
import '../providers/accommodations_provider.dart';
import '../providers/reviews_provider.dart';
import '../providers/trips_provider.dart' show LoadState;
import '../utils/format.dart';
import '../widgets/rating.dart';
import '../widgets/review_dialog.dart';
import 'book_stay_screen.dart';

class AccommodationDetailScreen extends StatefulWidget {
  final String accommodationId;

  /// When set, "Book this stay" books it for this trip; otherwise the traveler picks one.
  final String? tripId;
  const AccommodationDetailScreen(
      {super.key, required this.accommodationId, this.tripId});

  @override
  State<AccommodationDetailScreen> createState() =>
      _AccommodationDetailScreenState();
}

class _AccommodationDetailScreenState extends State<AccommodationDetailScreen> {
  String? _loadError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  Future<void> _refresh() async {
    final stays = context.read<AccommodationsProvider>();
    final reviews = context.read<ReviewsProvider>();
    reviews.load(widget.accommodationId);
    final error = await stays.fetch(widget.accommodationId);
    if (mounted) setState(() => _loadError = error);
  }

  Future<void> _writeReview(String name) async {
    final messenger = ScaffoldMessenger.of(context);
    final saved = await showReviewDialog(context,
        accommodationId: widget.accommodationId, accommodationName: name);
    if (saved == true) {
      messenger.showSnackBar(const SnackBar(content: Text('Thanks for your review!')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final stays = context.watch<AccommodationsProvider>();
    final reviews = context.watch<ReviewsProvider>().reviewsFor(widget.accommodationId);
    final stay = stays.byId(widget.accommodationId);
    final theme = Theme.of(context);

    if (stay == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Stay')),
        body: Center(
          child: _loadError == null
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_loadError!),
                    const SizedBox(height: 12),
                    FilledButton(
                        onPressed: _refresh, child: const Text('Try again')),
                  ],
                ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(stay.name)),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(stay.name,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                Chip(label: Text(stay.type), visualDensity: VisualDensity.compact),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.place_outlined, size: 18),
                const SizedBox(width: 4),
                Text(stay.destinationName),
              ],
            ),
            const SizedBox(height: 8),
            RatingSummary(rating: stay.averageRating, count: stay.reviewCount),
            const SizedBox(height: 16),
            Text('${formatLkr(stay.pricePerNight)} per room per night',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
                'Sleeps up to ${stay.maxGuestsPerRoom} guest${stay.maxGuestsPerRoom == 1 ? '' : 's'} per room',
                style: theme.textTheme.bodyMedium),
            if (stay.description.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(stay.description, style: theme.textTheme.bodyLarge),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: stay.isActive
                  ? () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => BookStayScreen(
                          accommodationId: stay.id, tripId: widget.tripId)))
                  : null,
              icon: const Icon(Icons.event_available),
              label: Text(stay.isActive ? 'Book this stay' : 'No longer available'),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: Text(
                      reviews.total == 0 ? 'Reviews' : 'Reviews (${reviews.total})',
                      style: theme.textTheme.titleMedium),
                ),
                OutlinedButton.icon(
                  onPressed: () => _writeReview(stay.name),
                  icon: const Icon(Icons.rate_review_outlined),
                  label: const Text('Write a review'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _ReviewsList(accommodationId: stay.id, reviews: reviews),
          ],
        ),
      ),
    );
  }
}

class _ReviewsList extends StatelessWidget {
  final String accommodationId;
  final StayReviews reviews;
  const _ReviewsList({required this.accommodationId, required this.reviews});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (reviews.state == LoadState.loading && reviews.items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (reviews.state == LoadState.failed && reviews.items.isEmpty) {
      return Row(
        children: [
          Expanded(child: Text(reviews.error ?? 'Could not load reviews.')),
          TextButton(
              onPressed: () =>
                  context.read<ReviewsProvider>().load(accommodationId),
              child: const Text('Try again')),
        ],
      );
    }
    if (reviews.items.isEmpty) {
      return Text(
          'No reviews yet. Stay here and be the first to share how it went.',
          style: theme.textTheme.bodyMedium);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in reviews.items) _ReviewTile(review: r),
        if (reviews.loadingMore)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (reviews.moreError != null)
          TextButton(
              onPressed: () =>
                  context.read<ReviewsProvider>().loadMore(accommodationId),
              child: Text('${reviews.moreError} Tap to retry'))
        else if (reviews.hasMore)
          TextButton(
              onPressed: () =>
                  context.read<ReviewsProvider>().loadMore(accommodationId),
              child: const Text('Show more reviews')),
      ],
    );
  }
}

class _ReviewTile extends StatelessWidget {
  final Review review;
  const _ReviewTile({required this.review});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StarRow(rating: review.rating),
              const SizedBox(width: 8),
              Expanded(
                child: Text(review.travelerName,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
              Text(formatDate(review.createdAt), style: theme.textTheme.bodySmall),
            ],
          ),
          if (review.comment.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(review.comment, style: theme.textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}
