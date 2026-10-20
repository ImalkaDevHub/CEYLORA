import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/accommodation.dart';
import '../providers/accommodations_provider.dart';
import '../providers/trips_provider.dart' show LoadState;
import '../utils/format.dart';
import '../widgets/rating.dart';
import 'accommodation_detail_screen.dart';
import 'bookings_screen.dart';

/// Stays: search, type filter, sort, infinite scroll. Used as a tab, and (with [tripId])
/// as a picker pushed from a trip so the chosen stay is booked for that trip.
class AccommodationsScreen extends StatefulWidget {
  final String? tripId;
  const AccommodationsScreen({super.key, this.tripId});

  @override
  State<AccommodationsScreen> createState() => _AccommodationsScreenState();
}

class _AccommodationsScreenState extends State<AccommodationsScreen> {
  final _scroll = ScrollController();
  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _searchController.text = context.read<AccommodationsProvider>().search;
    // A pushed picker may be the first place stays are needed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final p = context.read<AccommodationsProvider>();
      if (p.state == LoadState.idle) p.load();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 300) {
      context.read<AccommodationsProvider>().loadMore();
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    // Wait for a pause in typing instead of hitting the API on every keystroke.
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) context.read<AccommodationsProvider>().setSearch(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AccommodationsProvider>();
    final picking = widget.tripId != null;

    Widget body;
    if (p.state == LoadState.loading && p.items.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (p.state == LoadState.failed) {
      body = _Message(
        icon: Icons.cloud_off,
        text: p.error ?? 'Could not load stays.',
        action: FilledButton(onPressed: p.load, child: const Text('Try again')),
      );
    } else if (p.items.isEmpty) {
      body = _Message(
        icon: Icons.hotel_outlined,
        text: (p.search.isNotEmpty || p.type != null)
            ? 'No stays match your search.'
            : 'No stays available yet.',
      );
    } else {
      body = ListView.separated(
        key: const Key('stays-list'),
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: p.items.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          if (i < p.items.length) {
            return _StayCard(item: p.items[i], tripId: widget.tripId);
          }
          return _ListFooter(provider: p);
        },
      );
    }

    final content = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  onChanged: _onSearchChanged,
                  onSubmitted: (v) {
                    _debounce?.cancel();
                    p.setSearch(v);
                  },
                  decoration: InputDecoration(
                    hintText: 'Search stays or places',
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _debounce?.cancel();
                              _searchController.clear();
                              p.setSearch('');
                              setState(() {});
                            },
                          ),
                  ),
                ),
              ),
              PopupMenuButton<StaySort>(
                tooltip: 'Sort',
                icon: const Icon(Icons.sort),
                initialValue: p.sort,
                onSelected: p.setSort,
                itemBuilder: (_) => [
                  for (final s in StaySort.values)
                    PopupMenuItem(value: s, child: Text(s.label)),
                ],
              ),
            ],
          ),
        ),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              _TypeChip(
                  label: 'All',
                  selected: p.type == null,
                  onTap: () => p.setType(null)),
              for (final t in accommodationTypes)
                _TypeChip(
                    label: t, selected: p.type == t, onTap: () => p.setType(t)),
            ],
          ),
        ),
        if (!picking)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const BookingsScreen())),
                icon: const Icon(Icons.event_available_outlined),
                label: const Text('My bookings'),
              ),
            ),
          ),
        Expanded(child: RefreshIndicator(onRefresh: p.load, child: body)),
      ],
    );

    return Scaffold(
      appBar: picking ? AppBar(title: const Text('Choose a stay')) : null,
      body: content,
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TypeChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
            label: Text(label), selected: selected, onSelected: (_) => onTap()),
      );
}

class _StayCard extends StatelessWidget {
  final Accommodation item;
  final String? tripId;
  const _StayCard({required this.item, required this.tripId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) =>
                AccommodationDetailScreen(accommodationId: item.id, tripId: tripId))),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 8),
                  Chip(
                      label: Text(item.type),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  const Icon(Icons.place_outlined, size: 14),
                  const SizedBox(width: 4),
                  Expanded(
                      child: Text(item.destinationName,
                          style: theme.textTheme.bodySmall)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  RatingSummary(
                      rating: item.averageRating, count: item.reviewCount),
                  const Spacer(),
                  Text('${formatLkr(item.pricePerNight)} / night',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ListFooter extends StatelessWidget {
  final AccommodationsProvider provider;
  const _ListFooter({required this.provider});

  @override
  Widget build(BuildContext context) {
    if (provider.loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (provider.moreError != null) {
      return Center(
        child: TextButton.icon(
          onPressed: provider.loadMore,
          icon: const Icon(Icons.refresh),
          label: Text('${provider.moreError} Tap to retry'),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Center(
        child: Text('Showing ${provider.items.length} of ${provider.total}',
            style: Theme.of(context).textTheme.bodySmall),
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
        const SizedBox(height: 40),
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
