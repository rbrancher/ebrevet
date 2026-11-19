// Mock mode: build with --dart-define=EBREVET_MOCK=true
//
// Used by web previews and tests. In mock mode:
//  - every package:http call is served by MockServer (no real servers contacted)
//  - GPS is replaced by MockLocation
//  - the store-version check (upgrader) is disabled
const bool kMockMode = bool.fromEnvironment('EBREVET_MOCK');
