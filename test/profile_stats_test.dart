// Profile stats model (intent 0006): pure summary over ActivatedEvents.

import 'package:ebrevet_card/event.dart';
import 'package:ebrevet_card/outcome.dart';
import 'package:ebrevet_card/profile_stats.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  late Event base;

  setUpAll(() async {
    useMockServerForTests();
    base = (await mockEvents()).first;
  });

  // AC1 (intent 0006)
  test('counts rides, total km, longest ride and buckets', () {
    final stats = ProfileStats.from([
      fixtureRide(base, km: 200),
      fixtureRide(base, km: 200),
      fixtureRide(base, km: 300),
      fixtureRide(base, km: 600),
    ], '12345');
    expect(stats.rides, 4);
    expect(stats.totalKm, 1300);
    expect(stats.longestKm, 600);
    expect(stats.buckets, {
      DistanceBucket.populaire: 0,
      DistanceBucket.k200: 2,
      DistanceBucket.k300: 1,
      DistanceBucket.k400: 0,
      DistanceBucket.k600: 1,
      DistanceBucket.k1000: 0,
      DistanceBucket.k1200: 0,
    });
    expect(stats.isEmpty, isFalse);
  });

  // AC2 (intent 0006)
  test('only finished rides count', () {
    final notFinished =
        OverallOutcome.values.where((o) => o != OverallOutcome.finish).toList();
    expect(
        notFinished,
        containsAll([
          OverallOutcome.active,
          OverallOutcome.dnf,
          OverallOutcome.dns,
          OverallOutcome.dnqSkipped,
          OverallOutcome.dnqScrambled,
          OverallOutcome.dnqLateCheckIn,
          OverallOutcome.unknown,
        ]));
    for (final o in notFinished) {
      final stats =
          ProfileStats.from([fixtureRide(base, km: 300, outcome: o)], '12345');
      expect(stats.rides, 0, reason: o.name);
      expect(stats.totalKm, 0, reason: o.name);
      expect(stats.isEmpty, isTrue, reason: o.name);
    }
    final mixed = ProfileStats.from([
      fixtureRide(base, km: 400),
      for (final o in notFinished) fixtureRide(base, km: 1000, outcome: o),
    ], '12345');
    expect(mixed.rides, 1);
    expect(mixed.totalKm, 400);
    expect(mixed.longestKm, 400);
  });

  // AC3 (intent 0006)
  test('only rides under the current Rider ID count, compared trimmed', () {
    final rides = [
      fixtureRide(base, km: 200, riderID: '12345'),
      fixtureRide(base, km: 300, riderID: ' 12345 '),
      fixtureRide(base, km: 1000, riderID: '99999'),
    ];
    final stats = ProfileStats.from(rides, '12345 ');
    expect(stats.rides, 2);
    expect(stats.totalKm, 500);
    expect(stats.longestKm, 300);
    expect(ProfileStats.from(rides, '99999').totalKm, 1000);
    expect(ProfileStats.from(rides, '55555').isEmpty, isTrue);
    expect(ProfileStats.from(rides, '').isEmpty, isTrue);
  });

  // AC4 (intent 0006)
  test('finished pre-rides count like any start style', () {
    for (final style in StartStyle.values) {
      final stats = ProfileStats.from(
          [fixtureRide(base, km: 200, startStyle: style)], '12345');
      expect(stats.rides, 1, reason: style.name);
      expect(stats.buckets[DistanceBucket.k200], 1, reason: style.name);
    }
    final stats = ProfileStats.from([
      fixtureRide(base, km: 200, startStyle: StartStyle.preRide),
      fixtureRide(base, km: 300, startStyle: StartStyle.massStart),
    ], '12345');
    expect(stats.rides, 2);
    expect(stats.totalKm, 500);
  });

  // AC5 (intent 0006)
  group('distance buckets', () {
    const cases = {
      199: DistanceBucket.populaire,
      200: DistanceBucket.k200,
      299: DistanceBucket.k200,
      300: DistanceBucket.k300,
      999: DistanceBucket.k600,
      1000: DistanceBucket.k1000,
      1199: DistanceBucket.k1000,
      1200: DistanceBucket.k1200,
      1400: DistanceBucket.k1200,
    };
    for (final c in cases.entries) {
      test('${c.key} -> ${c.value.label}', () {
        expect(DistanceBucket.of(c.key), c.value);
        final stats =
            ProfileStats.from([fixtureRide(base, km: c.key)], '12345');
        expect(stats.buckets[c.value], 1);
        expect(stats.buckets.values.fold<int>(0, (a, b) => a + b), 1);
      });
    }

    test('seven buckets in order', () {
      expect(DistanceBucket.values.map((b) => b.label), [
        'Populaire',
        '200 km',
        '300 km',
        '400 km',
        '600 km',
        '1000 km',
        '1200+ km',
      ]);
    });
  });

  // AC6 (intent 0006)
  test('empty history or no finished rides for this ID is empty', () {
    final empty = ProfileStats.from([], '12345');
    expect(empty.isEmpty, isTrue);
    expect(empty.rides, 0);
    expect(empty.buckets.values.every((n) => n == 0), isTrue);
    expect(
        ProfileStats.from([
          fixtureRide(base, km: 200, outcome: OverallOutcome.dnf),
          fixtureRide(base, km: 300, riderID: '99999'),
        ], '12345')
            .isEmpty,
        isTrue);
  });
}
