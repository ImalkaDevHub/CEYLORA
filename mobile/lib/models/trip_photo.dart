/// A photo the traveler attached to a trip. Photos live on this device only.
class TripPhoto {
  final String tripId;

  /// Absolute path of the stored copy inside the app's private storage.
  final String path;
  final DateTime takenAt;

  const TripPhoto({
    required this.tripId,
    required this.path,
    required this.takenAt,
  });

  @override
  bool operator ==(Object other) =>
      other is TripPhoto && other.tripId == tripId && other.path == path;

  @override
  int get hashCode => Object.hash(tripId, path);
}
