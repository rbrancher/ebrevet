import 'dart:convert';
import 'dart:io';

import 'package:ebrevet_card/event.dart';
import 'package:ebrevet_card/mock/mock_server.dart';

/// Fixed clock used by tests so generated events are deterministic.
final DateTime testNow = DateTime.utc(2026, 6, 1, 12, 0);

/// Point MockServer at the fixture on disk and a fixed clock/secret.
void useMockServerForTests({String secret = 'ci-dummy-secret'}) {
  MockServer.loadFixture =
      () async => File('assets/mock/future_events.json').readAsString();
  MockServer.now = () => testNow;
  MockServer.signingSecret = () => secret;
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
