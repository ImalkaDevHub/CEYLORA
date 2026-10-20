import 'accommodation.dart';

/// Mirrors BookingItemResponseDto: one stay inside a booking.
class BookingItem {
  final String id;
  final String accommodationId;
  final String accommodationName;
  final String destinationName;
  final DateTime checkIn;
  final DateTime checkOut;
  final int nights;
  final int rooms;
  final int guests;
  final double nightlyRate;
  final double subtotal;

  const BookingItem({
    required this.id,
    required this.accommodationId,
    required this.accommodationName,
    required this.destinationName,
    required this.checkIn,
    required this.checkOut,
    required this.nights,
    required this.rooms,
    required this.guests,
    required this.nightlyRate,
    required this.subtotal,
  });

  factory BookingItem.fromJson(Map<String, dynamic> json) => BookingItem(
        id: json['id'] as String,
        accommodationId: json['accommodationId'] as String,
        accommodationName: (json['accommodationName'] as String?) ?? '',
        destinationName: (json['destinationName'] as String?) ?? '',
        checkIn: parseDateOnly(json['checkIn'] as String),
        checkOut: parseDateOnly(json['checkOut'] as String),
        nights: (json['nights'] as num).toInt(),
        rooms: (json['rooms'] as num).toInt(),
        guests: (json['guests'] as num).toInt(),
        nightlyRate: (json['nightlyRate'] as num).toDouble(),
        subtotal: (json['subtotal'] as num).toDouble(),
      );

  /// A review is allowed once the stay is over (check-out day or later).
  bool hasEnded(DateTime today) => !checkOut.isAfter(DateTime(today.year, today.month, today.day));
}

/// Mirrors BookingResponseDto.
class Booking {
  final String id;
  final String tripId;
  final String tripTitle;
  final String status; // Confirmed | Cancelled
  final double totalAmount;
  final String? notes;
  final DateTime createdAt;
  final DateTime? cancelledAt;
  final List<BookingItem> items;

  const Booking({
    required this.id,
    required this.tripId,
    required this.tripTitle,
    required this.status,
    required this.totalAmount,
    required this.notes,
    required this.createdAt,
    required this.cancelledAt,
    required this.items,
  });

  factory Booking.fromJson(Map<String, dynamic> json) => Booking(
        id: json['id'] as String,
        tripId: json['tripId'] as String,
        tripTitle: (json['tripTitle'] as String?) ?? '',
        status: json['status'] as String,
        totalAmount: (json['totalAmount'] as num).toDouble(),
        notes: json['notes'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
        cancelledAt: json['cancelledAt'] == null
            ? null
            : DateTime.parse(json['cancelledAt'] as String).toUtc(),
        items: ((json['items'] as List<dynamic>?) ?? const [])
            .map((e) => BookingItem.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );

  bool get isConfirmed => status == 'Confirmed';
  bool get isCancelled => status == 'Cancelled';

  DateTime get firstCheckIn =>
      items.map((i) => i.checkIn).reduce((a, b) => a.isBefore(b) ? a : b);
  DateTime get lastCheckOut =>
      items.map((i) => i.checkOut).reduce((a, b) => a.isAfter(b) ? a : b);
}
