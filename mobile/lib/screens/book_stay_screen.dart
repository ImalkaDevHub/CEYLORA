import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/accommodation.dart';
import '../providers/accommodations_provider.dart';
import '../providers/bookings_provider.dart';
import '../providers/trips_provider.dart';
import '../services/api_client.dart';
import '../utils/format.dart';
import 'booking_detail_screen.dart';

/// Choose trip, dates, rooms and guests; see the live price and availability; confirm.
class BookStayScreen extends StatefulWidget {
  final String accommodationId;

  /// Pre-selects this trip (when booking from a trip); otherwise the first open trip.
  final String? tripId;
  const BookStayScreen({super.key, required this.accommodationId, this.tripId});

  @override
  State<BookStayScreen> createState() => _BookStayScreenState();
}

class _BookStayScreenState extends State<BookStayScreen> {
  static const maxRooms = 10;
  static const quoteDelay = Duration(milliseconds: 300);

  final _notes = TextEditingController();
  Timer? _quoteTimer;

  String? _tripId;
  DateTime? _checkIn;
  DateTime? _checkOut;
  int _rooms = 1;
  int _guests = 1;

  AvailabilityQuote? _quote;
  String? _quoteError;
  bool _quoting = false;
  int _quoteSeq = 0; // a newer request makes older answers irrelevant

  String? _bookingError;

  @override
  void initState() {
    super.initState();
    _tripId = widget.tripId;
  }

  @override
  void dispose() {
    _quoteTimer?.cancel();
    _notes.dispose();
    super.dispose();
  }

  DateTime get _today => DateUtils.dateOnly(DateTime.now());

  Accommodation? get _stay =>
      context.read<AccommodationsProvider>().byId(widget.accommodationId);

  int get _maxGuests => _rooms * (_stay?.maxGuestsPerRoom ?? 1);

  Future<void> _pickCheckIn() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _checkIn ?? _today.add(const Duration(days: 1)),
      firstDate: _today,
      lastDate: DateTime(_today.year + 2, _today.month, _today.day),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _checkIn = picked;
      // Keep the range valid when the start moves past the end.
      if (_checkOut == null || !_checkOut!.isAfter(picked)) {
        _checkOut = picked.add(const Duration(days: 1));
      }
      _bookingError = null;
    });
    _scheduleQuote();
  }

  Future<void> _pickCheckOut() async {
    final first = (_checkIn ?? _today).add(const Duration(days: 1));
    final picked = await showDatePicker(
      context: context,
      initialDate: _checkOut ?? first,
      firstDate: first,
      lastDate: DateTime(first.year + 2, first.month, first.day),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _checkOut = picked;
      _bookingError = null;
    });
    _scheduleQuote();
  }

  void _setRooms(int value) {
    if (value < 1 || value > maxRooms) return;
    setState(() {
      _rooms = value;
      if (_guests > _maxGuests) _guests = _maxGuests;
      _bookingError = null;
    });
    _scheduleQuote();
  }

  void _setGuests(int value) {
    if (value < 1 || value > _maxGuests) return;
    setState(() => _guests = value);
  }

  /// Asks for a fresh quote shortly after the last change.
  void _scheduleQuote() {
    _quoteTimer?.cancel();
    final checkIn = _checkIn, checkOut = _checkOut;
    final seq = ++_quoteSeq;
    if (checkIn == null || checkOut == null) return;
    setState(() {
      _quote = null;
      _quoteError = null;
      _quoting = true;
    });
    _quoteTimer = Timer(quoteDelay, () => _runQuote(seq, checkIn, checkOut, _rooms));
  }

  Future<void> _runQuote(int seq, DateTime checkIn, DateTime checkOut, int rooms) async {
    if (!mounted) return;
    final stays = context.read<AccommodationsProvider>();
    try {
      final quote = await stays.quote(
          id: widget.accommodationId,
          checkIn: checkIn,
          checkOut: checkOut,
          rooms: rooms);
      if (!mounted || seq != _quoteSeq) return;
      setState(() {
        _quote = quote;
        _quoting = false;
      });
    } on ApiException catch (e) {
      if (!mounted || seq != _quoteSeq) return;
      setState(() {
        _quoteError = e.message;
        _quoting = false;
      });
    }
  }

  bool get _canConfirm {
    final quote = _quote;
    final bookings = context.read<BookingsProvider>();
    return _tripId != null &&
        quote != null &&
        quote.isAvailable &&
        _guests >= 1 &&
        _guests <= _maxGuests &&
        !bookings.creating;
  }

  Future<void> _confirm() async {
    final bookings = context.read<BookingsProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _bookingError = null);

    final (booking, error) = await bookings.create(
      tripId: _tripId!,
      accommodationId: widget.accommodationId,
      checkIn: _checkIn!,
      checkOut: _checkOut!,
      rooms: _rooms,
      guests: _guests,
      notes: _notes.text,
    );
    if (!mounted) return;
    if (booking != null) {
      messenger.showSnackBar(const SnackBar(content: Text('Booking confirmed.')));
      navigator.pushReplacement(MaterialPageRoute(
          builder: (_) => BookingDetailScreen(bookingId: booking.id)));
      return;
    }
    if (error != null) {
      setState(() => _bookingError = error);
      // Someone may have taken the rooms; show what is really available now.
      _scheduleQuote();
    }
  }

  @override
  Widget build(BuildContext context) {
    final stay = context.watch<AccommodationsProvider>().byId(widget.accommodationId);
    final trips = context.watch<TripsProvider>().trips
        .where((t) => t.status != 'Cancelled')
        .toList();
    final creating = context.watch<BookingsProvider>().creating;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (stay == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Book a stay')),
        body: const Center(child: Text('This stay is no longer available.')),
      );
    }

    // The chosen trip may be missing from the list (e.g. cancelled); fall back to the first.
    if (_tripId == null || !trips.any((t) => t.id == _tripId)) {
      _tripId = trips.isEmpty ? null : trips.first.id;
    }

    return Scaffold(
      appBar: AppBar(title: Text('Book ${stay.name}')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (_bookingError != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(8)),
                child: Text(_bookingError!,
                    style: TextStyle(color: scheme.onErrorContainer)),
              ),
              const SizedBox(height: 16),
            ],
            if (trips.isEmpty)
              Text(
                  'You need an open trip to book a stay. Create one in My trips first.',
                  style: theme.textTheme.bodyLarge)
            else
              DropdownButtonFormField<String>(
                key: ValueKey(_tripId),
                initialValue: _tripId,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'For trip', border: OutlineInputBorder()),
                items: [
                  for (final t in trips)
                    DropdownMenuItem(
                        value: t.id,
                        child: Text(t.title, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: creating
                    ? null
                    : (v) => setState(() {
                          _tripId = v;
                          _bookingError = null;
                        }),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                    child: _DateField(
                        label: 'Check-in',
                        value: _checkIn,
                        onTap: creating ? null : _pickCheckIn)),
                const SizedBox(width: 12),
                Expanded(
                    child: _DateField(
                        label: 'Check-out',
                        value: _checkOut,
                        onTap: creating ? null : _pickCheckOut)),
              ],
            ),
            const SizedBox(height: 16),
            _Stepper(
              label: 'Rooms',
              value: _rooms,
              min: 1,
              max: maxRooms,
              onChanged: creating ? null : _setRooms,
            ),
            _Stepper(
              label: 'Guests',
              value: _guests,
              min: 1,
              max: _maxGuests,
              hint: 'Up to $_maxGuests for $_rooms room${_rooms == 1 ? '' : 's'}',
              onChanged: creating ? null : _setGuests,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notes,
              enabled: !creating,
              maxLength: 500,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                  labelText: 'Notes for the host (optional)',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            _QuoteCard(
              stay: stay,
              hasDates: _checkIn != null && _checkOut != null,
              quote: _quote,
              error: _quoteError,
              loading: _quoting,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _canConfirm ? _confirm : null,
              child: creating
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Confirm booking'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final VoidCallback? onTap;
  const _DateField({required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.calendar_today, size: 18),
        ),
        child: Text(value == null ? 'Select' : formatPickedDate(value!)),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final String? hint;
  final ValueChanged<int>? onChanged;
  const _Stepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodyLarge),
                if (hint != null) Text(hint!, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Fewer $label'.toLowerCase(),
            onPressed: onChanged == null || value <= min
                ? null
                : () => onChanged!(value - 1),
            icon: const Icon(Icons.remove_circle_outline),
          ),
          SizedBox(
            width: 28,
            child: Text('$value',
                textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
          ),
          IconButton(
            tooltip: 'More $label'.toLowerCase(),
            onPressed: onChanged == null || value >= max
                ? null
                : () => onChanged!(value + 1),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }
}

class _QuoteCard extends StatelessWidget {
  final Accommodation stay;
  final bool hasDates;
  final AvailabilityQuote? quote;
  final String? error;
  final bool loading;
  const _QuoteCard({
    required this.stay,
    required this.hasDates,
    required this.quote,
    required this.error,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget child;
    if (!hasDates) {
      child = Text('Pick your dates to see the price and availability.',
          style: theme.textTheme.bodyMedium);
    } else if (loading) {
      child = const Row(
        children: [
          SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 12),
          Text('Checking availability…'),
        ],
      );
    } else if (error != null) {
      child = Text(error!, style: TextStyle(color: scheme.error));
    } else if (quote == null) {
      child = const SizedBox.shrink();
    } else if (!quote!.isAvailable) {
      child = Text(
        quote!.maxRoomsAvailable == 0
            ? 'Sold out for some of these nights. Try other dates.'
            : 'Only ${quote!.maxRoomsAvailable} room${quote!.maxRoomsAvailable == 1 ? ' is' : 's are'} free for the whole stay. Reduce rooms or change dates.',
        style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600),
      );
    } else {
      final q = quote!;
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              '${q.nights} night${q.nights == 1 ? '' : 's'} × ${q.rooms} room${q.rooms == 1 ? '' : 's'} × ${formatLkr(q.pricePerNight)}',
              style: theme.textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text('Total ${formatLkr(q.totalPrice)}',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text('Available for your dates', style: theme.textTheme.bodySmall),
        ],
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(padding: const EdgeInsets.all(16), child: SizedBox(width: double.infinity, child: child)),
    );
  }
}
