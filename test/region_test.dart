import 'package:ebrevet_card/region.dart';
import 'package:ebrevet_card/region_data.dart';
import 'package:flutter_test/flutter_test.dart';

// Pins today's region-secret selection (see the comment in Region()).
// With the documented Map<int, String> regionSecret template, a String region
// ID never matches, so every region uses RegionData.defaultSecret. Changing
// this would alter start codes and feed signature checks.
void main() {
  // AC5 (intent 0008)
  group('Region secret selection', () {
    test('club 938017 (default region) uses the default secret', () {
      final region = Region(regionID: '938017');
      expect(region.regionID, '938017');
      expect(region.secret, RegionData.defaultSecret);
    });

    test('an unknown region uses the default secret', () {
      final region = Region(regionID: 'no-such-region');
      expect(region.regionID, 'Unknown');
      expect(region.secret, RegionData.defaultSecret);
    });

    test('Region() with no ID is 938017 and uses the default secret', () {
      final region = Region();
      expect(region.regionID, '938017');
      expect(region.secret, RegionData.defaultSecret);
    });
  });
}
