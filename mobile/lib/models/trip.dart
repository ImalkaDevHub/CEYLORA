/// Mirrors CEYLORA.Application.DTOs.Trips.TripResponseDto.
class Trip {
  final String id;
  final String title;
  final DateTime startDate;
  final DateTime endDate;
  final double budget;
  final String status;
  final String travelerName;

  const Trip({
    required this.id,
    required this.title,
    required this.startDate,
    required this.endDate,
    required this.budget,
    required this.status,
    required this.travelerName,
  });

  factory Trip.fromJson(Map<String, dynamic> json) => Trip(
        id: json['id'] as String,
        title: json['title'] as String,
        startDate: DateTime.parse(json['startDate'] as String).toUtc(),
        endDate: DateTime.parse(json['endDate'] as String).toUtc(),
        budget: (json['budget'] as num).toDouble(),
        status: json['status'] as String,
        travelerName: (json['travelerName'] as String?) ?? '',
      );

  bool get isDraft => status == 'Draft';

  /// Inclusive number of calendar days.
  int get days => endDate.difference(startDate).inDays + 1;
}
