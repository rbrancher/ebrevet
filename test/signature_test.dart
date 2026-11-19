import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:ebrevet_card/signature.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

// Regression net for rider-facing codes. If these change, riders' start codes
// and finish certificates stop matching what organizers compute.
void main() {
  setUp(useMockServerForTests);

  test('start code is first 4 hex chars of sha256(cue-event-rider-secret)',
      () async {
    final event = (await mockEvents()).first;
    const rider = '12345';
    final code = Signature.startCode(event, rider).cipherText;

    final plain =
        '${event.cueVersion}-${event.eventID}-$rider-${event.region.secret}';
    final expected =
        sha256.convert(utf8.encode(plain)).toString().substring(0, 4).toUpperCase();
    expect(code, expected);
    expect(code, hasLength(4));
  });

  test('start code golden value (stub secret)', () async {
    final event = (await mockEvents()).first;
    expect(event.eventID, '938017-382');
    expect(Signature.startCode(event, '12345').cipherText, 'E32C');
  });

  test('start code depends on cue version and rider', () async {
    final event = (await mockEvents()).first;
    final base = Signature.startCode(event, '12345').cipherText;
    expect(Signature.startCode(event, '12346').cipherText, isNot(base));
    expect(
        Signature.startCode(event, '12345', cueVersion: event.cueVersion + 1)
            .cipherText,
        isNot(base));
  });

  test('XY substitution round-trips', () {
    expect(Signature.substituteZeroOneXY('10A0'), 'YXAX');
    expect(Signature.substituteXYZeroOne('YXAX'), '10A0');
  });
}
