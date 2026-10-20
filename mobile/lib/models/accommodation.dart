/// Values of CEYLORA.Domain.Entities.AccommodationType (sent/received by name).
const accommodationTypes = <String>[
  'Hotel',
  'Villa',
  'Guesthouse',
  'Resort',
  'Hostel',
];

/// The API sends stay dates as `yyyy-MM-dd` (a calendar date, no time zone). They are
/// read as plain local dates so they never shift by a day.
DateTime parseDateOnly(String value) {
  final parts = value.split('-');
  if (parts.length != 3) throw FormatException('Not a date: $value');
  return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
}

/// Mirrors AccommodationResponseDto.
class Accommodation {
  final String id;
  final String destinationId;
  final String destinationName;
  final String name;
  final String description;
  final String type;
  final double pricePerNight;
  final int maxGuestsPerRoom;
  final bool isActive;

  /// Mean of all reviews, or null when there are none.
  final double? averageRating;
  final int reviewCount;

  const Accommodation({
    required this.id,
    required this.destinationId,
    required this.destinationName,
    required this.name,
    required this.description,
    required this.type,
    required this.pricePerNight,
    required this.maxGuestsPerRoom,
    required this.isActive,
    required this.averageRating,
    required this.reviewCount,
  });

  factory Accommodation.fromJson(Map<String, dynamic> json) => Accommodation(
        id: json['id'] as String,
        destinationId: json['destinationId'] as String,
        destinationName: (json['destinationName'] as String?) ?? '',
        name: json['name'] as String,
        description: (json['description'] as String?) ?? '',
        type: json['type'] as String,
        pricePerNight: (json['pricePerNight'] as num).toDouble(),
        maxGuestsPerRoom: (json['maxGuestsPerRoom'] as num).toInt(),
        isActive: (json['isActive'] as bool?) ?? true,
        averageRating: (json['averageRating'] as num?)?.toDouble(),
        reviewCount: (json['reviewCount'] as num?)?.toInt() ?? 0,
      );
}

/// Mirrors `PagedResult<AccommodationResponseDto>`.
class AccommodationPage {
  final List<Accommodation> items;
  final int totalCount;
  final int page;
  final int pageSize;

  const AccommodationPage({
    required this.items,
    required this.totalCount,
    required this.page,
    required this.pageSize,
  });

  factory AccommodationPage.fromJson(Map<String, dynamic> json) =>
      AccommodationPage(
        items: (json['items'] as List<dynamic>)
            .map((e) => Accommodation.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        totalCount: (json['totalCount'] as num).toInt(),
        page: (json['page'] as num).toInt(),
        pageSize: (json['pageSize'] as num).toInt(),
      );
}

/// One night of room inventory.
class AvailabilityDay {
  final DateTime date;
  final int totalRooms;
  final int bookedRooms;
  final int availableRooms;

  const AvailabilityDay({
    required this.date,
    required this.totalRooms,
    required this.bookedRooms,
    required this.availableRooms,
  });

  factory AvailabilityDay.fromJson(Map<String, dynamic> json) => AvailabilityDay(
        date: parseDateOnly(json['date'] as String),
        totalRooms: (json['totalRooms'] as num).toInt(),
        bookedRooms: (json['bookedRooms'] as num).toInt(),
        availableRooms: (json['availableRooms'] as num).toInt(),
      );
}

/// Mirrors AvailabilityQuoteDto: can I stay from X to Y with N rooms, and what does it cost?
class AvailabilityQuote {
  final String accommodationId;
  final DateTime checkIn;
  final DateTime checkOut;
  final int nights;
  final int rooms;
  final double pricePerNight;
  final double totalPrice;
  final bool isAvailable;

  /// The most rooms that could be booked for the whole stay.
  final int maxRoomsAvailable;
  final List<AvailabilityDay> days;

  const AvailabilityQuote({
    required this.accommodationId,
    required this.checkIn,
    required this.checkOut,
    required this.nights,
    required this.rooms,
    required this.pricePerNight,
    required this.totalPrice,
    required this.isAvailable,
    required this.maxRoomsAvailable,
    required this.days,
  });

  factory AvailabilityQuote.fromJson(Map<String, dynamic> json) =>
      AvailabilityQuote(
        accommodationId: json['accommodationId'] as String,
        checkIn: parseDateOnly(json['checkIn'] as String),
        checkOut: parseDateOnly(json['checkOut'] as String),
        nights: (json['nights'] as num).toInt(),
        rooms: (json['rooms'] as num).toInt(),
        pricePerNight: (json['pricePerNight'] as num).toDouble(),
        totalPrice: (json['totalPrice'] as num).toDouble(),
        isAvailable: json['isAvailable'] as bool,
        maxRoomsAvailable: (json['maxRoomsAvailable'] as num).toInt(),
        days: ((json['days'] as List<dynamic>?) ?? const [])
            .map((e) => AvailabilityDay.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );
}
