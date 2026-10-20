/// Values of CEYLORA.Domain.Entities.TravelCategory (sent/received by name).
const travelCategories = <String>[
  'Beach',
  'Nature',
  'Culture',
  'Adventure',
  'Wildlife',
  'CityLife',
];

/// "CityLife" -> "City life".
String categoryLabel(String category) => category == 'CityLife'
    ? 'City life'
    : category;

/// Mirrors DestinationResponseDto.
class Destination {
  final String id;
  final String name;
  final String region;
  final String description;
  final String category;
  final String? imageUrl;
  final bool isActive;

  const Destination({
    required this.id,
    required this.name,
    required this.region,
    required this.description,
    required this.category,
    required this.imageUrl,
    required this.isActive,
  });

  factory Destination.fromJson(Map<String, dynamic> json) => Destination(
        id: json['id'] as String,
        name: json['name'] as String,
        region: (json['region'] as String?) ?? '',
        description: (json['description'] as String?) ?? '',
        category: json['category'] as String,
        imageUrl: _cleanUrl(json['imageUrl'] as String?),
        isActive: (json['isActive'] as bool?) ?? true,
      );

  /// Only http(s) image URLs are used; anything else falls back to the placeholder.
  static String? _cleanUrl(String? url) {
    if (url == null) return null;
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      return null;
    }
    return uri.toString();
  }
}

/// Mirrors `PagedResult<DestinationResponseDto>`.
class DestinationPage {
  final List<Destination> items;
  final int totalCount;
  final int page;
  final int pageSize;

  const DestinationPage({
    required this.items,
    required this.totalCount,
    required this.page,
    required this.pageSize,
  });

  factory DestinationPage.fromJson(Map<String, dynamic> json) =>
      DestinationPage(
        items: (json['items'] as List<dynamic>)
            .map((e) => Destination.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        totalCount: json['totalCount'] as int,
        page: json['page'] as int,
        pageSize: json['pageSize'] as int,
      );
}

/// Mirrors DestinationSummaryDto (experience count and price range, LKR).
class DestinationSummary {
  final int experienceCount;
  final double minPrice;
  final double maxPrice;
  final double averagePrice;

  const DestinationSummary({
    required this.experienceCount,
    required this.minPrice,
    required this.maxPrice,
    required this.averagePrice,
  });

  factory DestinationSummary.fromJson(Map<String, dynamic> json) =>
      DestinationSummary(
        experienceCount: json['experienceCount'] as int,
        minPrice: (json['minPrice'] as num).toDouble(),
        maxPrice: (json['maxPrice'] as num).toDouble(),
        averagePrice: (json['averagePrice'] as num).toDouble(),
      );
}
