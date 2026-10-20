import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/destination.dart';
import '../providers/destinations_provider.dart';
import '../providers/trips_provider.dart' show LoadState;
import '../widgets/destination_image.dart';
import 'destination_detail_screen.dart';

/// Destinations tab: search, category filter, sort, infinite scroll.
class DestinationsScreen extends StatefulWidget {
  const DestinationsScreen({super.key});

  @override
  State<DestinationsScreen> createState() => _DestinationsScreenState();
}

class _DestinationsScreenState extends State<DestinationsScreen> {
  final _scroll = ScrollController();
  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _searchController.text = context.read<DestinationsProvider>().search;
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
      context.read<DestinationsProvider>().loadMore();
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    // Wait for a pause in typing instead of hitting the API on every keystroke.
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) context.read<DestinationsProvider>().setSearch(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<DestinationsProvider>();

    Widget body;
    if (p.state == LoadState.loading && p.items.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (p.state == LoadState.failed) {
      body = _Message(
        icon: Icons.cloud_off,
        text: p.error ?? 'Could not load destinations.',
        action: FilledButton(onPressed: p.load, child: const Text('Try again')),
      );
    } else if (p.items.isEmpty) {
      body = _Message(
        icon: Icons.travel_explore,
        text: (p.search.isNotEmpty || p.category != null)
            ? 'No destinations match your search.'
            : 'No destinations available yet.',
      );
    } else {
      body = ListView.separated(
        key: const Key('destinations-list'),
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: p.items.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          if (i < p.items.length) return _DestinationCard(item: p.items[i]);
          return _ListFooter(provider: p);
        },
      );
    }

    return Column(
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
                    hintText: 'Search name or region',
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
              PopupMenuButton<DestinationSort>(
                tooltip: 'Sort',
                icon: const Icon(Icons.sort),
                initialValue: p.sort,
                onSelected: p.setSort,
                itemBuilder: (_) => [
                  for (final s in DestinationSort.values)
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
              _CategoryChip(
                label: 'All',
                selected: p.category == null,
                onTap: () => p.setCategory(null),
              ),
              for (final c in travelCategories)
                _CategoryChip(
                  label: categoryLabel(c),
                  selected: p.category == c,
                  onTap: () => p.setCategory(c),
                ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(onRefresh: p.load, child: body),
        ),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _CategoryChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }
}

class _DestinationCard extends StatelessWidget {
  final Destination item;
  const _DestinationCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => DestinationDetailScreen(destinationId: item.id))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DestinationImage(url: item.imageUrl, height: 150, width: double.infinity),
            Padding(
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
                        label: Text(categoryLabel(item.category)),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(item.region, style: theme.textTheme.bodySmall),
                  if (item.description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(item.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// End-of-list row: spinner while loading more, retry on failure, count otherwise.
class _ListFooter extends StatelessWidget {
  final DestinationsProvider provider;
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
        child: Text(
          'Showing ${provider.items.length} of ${provider.total}',
          style: Theme.of(context).textTheme.bodySmall,
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
