import 'dart:io';

import 'package:ebrevet_card/app_settings.dart';
import 'package:ebrevet_card/files.dart';
import 'package:ebrevet_card/mock/mock_server.dart';
import 'package:ebrevet_card/my_settings.dart';
import 'package:ebrevet_card/scheduled_events.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

/// Fresh prefs (with [prefs] stored), an empty temp documents directory,
/// empty in-memory event caches and the mock server (intent 0015 tests).
/// Returns the temp directory; [tearDownEventSources] removes it.
Future<Directory> setUpEventSources(
    [Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues(prefs);
  await MySetting.initSharedPreferences();
  final docs = Directory.systemTemp.createTempSync('ebrevet_sources_');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          _pathProviderChannel, (call) async => docs.path);
  ScheduledEvents.resetMemory();
  useMockServerForTests();
  // Feed dates relative to the real clock, so no event is "too old".
  MockServer.now = DateTime.now;
  return docs;
}

void tearDownEventSources(Directory docs) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_pathProviderChannel, null);
  ScheduledEvents.resetMemory();
  MockServer.now = DateTime.now;
  try {
    docs.deleteSync(recursive: true);
  } catch (_) {}
}

ScheduledEventsSource regionSource(String id,
        {ScheduleEventsSourceID category =
            ScheduleEventsSourceID.fromRegion}) =>
    ScheduledEventsSource(category, regionID: id);

final customSource = ScheduledEventsSource(ScheduleEventsSourceID.fromURL);

/// Refreshes [source] from the mock server (never the network), recording
/// every requested URL in [requested] if given.
Future<void> refreshFromMock(ScheduledEventsSource source,
    {List<Uri>? requested}) {
  return http.runWithClient(() => ScheduledEvents.refreshSource(source),
      () => _RecordingClient(requested));
}

class _RecordingClient extends http.BaseClient {
  final List<Uri>? requested;
  final http.Client _inner = MockServer.client();
  _RecordingClient(this.requested);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requested?.add(request.url);
    return _inner.send(request);
  }
}

/// The legacy single cache file (before intent 0015).
FileStorage get legacyStorage =>
    FileStorage(AppSettings.scheduleEventsFilename);
