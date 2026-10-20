/// Mirrors ReviewResponseDto.
class Review {
  final String id;
  final String accommodationId;
  final String travelerId;
  final String travelerName;
  final int rating;
  final String comment;
  final DateTime createdAt;

  const Review({
    required this.id,
    required this.accommodationId,
    required this.travelerId,
    required this.travelerName,
    required this.rating,
    required this.comment,
    required this.createdAt,
  });

  factory Review.fromJson(Map<String, dynamic> json) => Review(
        id: json['id'] as String,
        accommodationId: json['accommodationId'] as String,
        travelerId: json['travelerId'] as String,
        travelerName: (json['travelerName'] as String?) ?? '',
        rating: (json['rating'] as num).toInt(),
        comment: (json['comment'] as String?) ?? '',
        createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
      );
}

/// Mirrors `PagedResult<ReviewResponseDto>`.
class ReviewPage {
  final List<Review> items;
  final int totalCount;
  final int page;
  final int pageSize;

  const ReviewPage({
    required this.items,
    required this.totalCount,
    required this.page,
    required this.pageSize,
  });

  factory ReviewPage.fromJson(Map<String, dynamic> json) => ReviewPage(
        items: (json['items'] as List<dynamic>)
            .map((e) => Review.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        totalCount: (json['totalCount'] as num).toInt(),
        page: (json['page'] as num).toInt(),
        pageSize: (json['pageSize'] as num).toInt(),
      );
}
