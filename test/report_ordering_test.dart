// Regression net for the unawaited_futures fixes (intent 0008): wrapping the
// check-in upload in unawaited() must not change its ordering. The caller gets
// control back before the POST completes, and onUploadDone runs afterwards,
// on success and on failure.

import 'dart:async';

import 'package:ebrevet_card/my_settings.dart';
import 'package:ebrevet_card/report.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await MySetting.initSharedPreferences();
    useMockServerForTests();
  });

  // AC3, AC8 (intent 0008)
  test('report upload runs in the background; onUploadDone fires after it',
      () async {
    final ride = fixtureRide((await mockEvents()).first, km: 200);
    final gate = Completer<void>();
    final order = <String>[];

    final client = MockClient((request) async {
      order.add('post');
      await gate.future;
      return http.Response('{"status":"OK"}', 200);
    });

    await http.runWithClient(() async {
      await Report.constructReportAndSend(ride,
          onUploadDone: () => order.add('done'));
      order.add('returned');
      await pumpEventQueue();
      // The POST is in flight and blocked; the caller already has control.
      expect(order, ['returned', 'post']);
      gate.complete();
      await pumpEventQueue();
    }, () => client);

    expect(order, ['returned', 'post', 'done']);
    expect(ride.outcomes.lastUpload, isNotNull);
  });

  // AC3, AC8 (intent 0008)
  test('onUploadDone still fires when the upload fails', () async {
    final ride = fixtureRide((await mockEvents()).first, km: 200);
    var done = false;

    final client = MockClient((request) async => throw Exception('offline'));

    await http.runWithClient(() async {
      await Report.constructReportAndSend(ride,
          onUploadDone: () => done = true);
      await pumpEventQueue();
    }, () => client);

    expect(done, isTrue);
    expect(ride.outcomes.lastUpload, isNull);
  });
}
