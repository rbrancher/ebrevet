// Rider profile stats (intent 0006): a pure summary of the rides saved on
// this phone. Reads ActivatedEvents only; nothing here changes ride state.

import 'activated_event.dart';

/// Distance buckets by official event distance. Each standard distance
/// covers the range from itself up to (not including) the next one.
enum DistanceBucket {
  populaire('Populaire', 0),
  k200('200 km', 200),
  k300('300 km', 300),
  k400('400 km', 400),
  k600('600 km', 600),
  k1000('1000 km', 1000),
  k1200('1200+ km', 1200);

  final String label;
  final int minKm;
  const DistanceBucket(this.label, this.minKm);

  /// The bucket for an official distance of [km].
  static DistanceBucket of(int km) =>
      values.lastWhere((b) => km >= b.minKm, orElse: () => populaire);
}

class ProfileStats {
  /// Number of finished rides.
  final int rides;

  /// Sum of official distances of finished rides, in km.
  final int totalKm;

  /// Longest finished ride, in km.
  final int longestKm;

  /// Finished rides per distance bucket. Every bucket is present.
  final Map<DistanceBucket, int> buckets;

  const ProfileStats._(this.rides, this.totalKm, this.longestKm, this.buckets);

  /// Summarises [history] for [riderID]. Only finished rides
  /// (`isFinished`) under the same Rider ID (compared after trimming) count,
  /// whatever their start style.
  factory ProfileStats.from(Iterable<ActivatedEvent> history, String riderID) {
    final id = riderID.trim();
    final buckets = {for (final b in DistanceBucket.values) b: 0};
    var rides = 0, totalKm = 0, longestKm = 0;
    if (id.isNotEmpty) {
      for (final ride in history) {
        if (!ride.isFinished || ride.riderID.trim() != id) continue;
        final km = ride.event.distance;
        rides++;
        totalKm += km;
        if (km > longestKm) longestKm = km;
        final b = DistanceBucket.of(km);
        buckets[b] = buckets[b]! + 1;
      }
    }
    return ProfileStats._(rides, totalKm, longestKm, buckets);
  }

  /// No finished rides for this rider.
  bool get isEmpty => rides == 0;
}
