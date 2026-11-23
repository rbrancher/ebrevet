import 'dart:convert';
import 'dart:io';

import 'package:ebrevet_card/activated_event.dart';
import 'package:ebrevet_card/event.dart';
import 'package:ebrevet_card/mock/mock_server.dart';
import 'package:ebrevet_card/outcome.dart';

/// Fixed clock used by tests so generated events are deterministic.
final DateTime testNow = DateTime.utc(2026, 6, 1, 12, 0);

/// Point MockServer at the fixture on disk and a fixed clock/secret.
void useMockServerForTests({String secret = 'ci-dummy-secret'}) {
  MockServer.loadFixture =
      () async => File('assets/mock/future_events.json').readAsString();
  MockServer.now = () => testNow;
  MockServer.signingSecret = (_) => secret;
  MockServer.receivedReports.clear();
}

/// Events from the mock feed, parsed by the real app model.
Future<List<Event>> mockEvents() async {
  final feed = await MockServer.scheduledEvents();
  return [
    for (final e in feed['event_list'] as List)
      Event.fromJson(jsonDecode(jsonEncode(e)) as Map<String, dynamic>)
  ];
}

var _rideCounter = 0;

/// A ride (finished by default) on a copy of [base] with official distance
/// [km], for profile tests (intent 0006). Not added to MyActivatedEvents.
ActivatedEvent fixtureRide(
  Event base, {
  required int km,
  OverallOutcome outcome = OverallOutcome.finish,
  String riderID = '12345',
  StartStyle startStyle = StartStyle.massStart,
}) {
  final event = Event.fromJson(
      jsonDecode(jsonEncode(base.toJson)) as Map<String, dynamic>)
    ..distance = km
    ..eventID = '${base.eventID}-fixture-${_rideCounter++}';
  return ActivatedEvent(
      event, riderID, EventOutcomes(overallOutcome: outcome), startStyle);
}
