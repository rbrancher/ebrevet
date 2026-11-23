# eBrevet architecture (orientation for humans and agents)

The app is a Flutter app of about 11k lines. `lib/` is flat, with one subfolder, `lib/mock/`.
- **State:** `provider` with a few ChangeNotifiers, plus static singletons for app-wide data.
- **Persistence:** `shared_preferences` for settings, and JSON files through `FileStorage` (`files.dart`).
  - On native, `FileStorage` writes to the documents directory.
  - On web, it writes to browser storage instead.

## Startup
`main.dart`:
1. `main()`. In mock mode, it wraps everything in `http.runWithClient(MockServer.client)`.
2. `initSettings()` runs these steps in order:
   1. prefs
   2. package info
   3. `Region.fetchRegionsFromDisk`
   4. `ScheduledEvents.refreshEventsFromDisk`: on first run after an upgrade it migrates the old single-source settings to the source list (`EventSources`) and adopts the legacy `futureEvents.json` cache. Then it loads every configured source's cache.
   5. `MyActivatedEvents.load`
3. `runApp(MultiProvider(DayNight, ControlState, SourceSelection))`, which shows `ScheduledEventsPage` (`event_list_page.dart`).

## Data flow
```
region list (randonneuring.org/ebrevet/region_list, or the built-in map in region.dart)
   └─ Region: club, server URL, secret (from gitignored region_data.dart)
scheduled events feed (<region server>/scheduled_events/<region>/<nonce>)
   └─ ScheduledEvents.refreshScheduledEventsFromServer
        checks: nonce + HMAC-SHA256 signature (signJson) + minimum_app_version
        → Event.fromJson / Control.fromMap → that source's cache
          (ScheduledEvents.cacheFor(source), futureEvents-<source key>.json)
        ScheduledEvents.events = the selected source's events;
        ScheduledEvents.findEvent looks across all configured sources
rider taps RIDE / PRE-RIDE + enters start code (Signature.startCode)
   └─ ActivatedEvent (activated_event.dart), stored by MyActivatedEvents → pastEvents.json
check-in at a control (control_card.dart → checkin.dart)
   rules: proximity (location.dart, AppSettings.proximityRadius) + open/close window
   └─ Report (report.dart) POSTs a signed report to event.checkinPostURL
finish → EventOutcomes (outcome.dart) → certificate (cert_page.dart) with finish code
```

## Module map
| Area | Files |
|---|---|
| Entry and theme | `main.dart`, `day_night.dart` |
| Settings | `app_settings.dart` (all settings and constants), `my_settings.dart` (MySetting<T> on prefs), `settings_page.dart`, `settings_tiles.dart` |
| Regions | `region.dart` (built-in region map plus refresh), `region_data.dart` (secrets, gitignored; CI uses `harness/ci/region_data.stub.dart`) |
| Event feed | `scheduled_events.dart` (fetch, verify, per-source caches, `EventSources` source list and selection, `SourceSelection`), `event.dart`, `control.dart` |
| Ride state | `activated_event.dart`, `my_activated_events.dart`, `outcome.dart`, `control_state.dart` |
| Check-in rules and codes | `checkin.dart`, `signature.dart` (start, check-in, report and finish codes), `location.dart` |
| Server reporting | `report.dart` (POST check-ins, fetch other riders' status) |
| UI: event list | `event_list_page.dart`, `event_card.dart`, `event_header_card.dart`, `my_activated_events_page.dart`, `route_geometry.dart`, `route_sketch.dart`, `route_map.dart` (OSM tile map, `flutter_map`), `route_map_page.dart` (full-screen interactive map), `ride_summary_sheet.dart` (collapsible ride summary over that map), `route_polyline.dart` (encoded polyline decoder for the feed's optional `route_polyline`), `route_service.dart` (road route from a public cycling router, full-screen map only) |
| UI: riding | `controls_view_page.dart`, `control_card.dart`, `checkin_progress.dart`, `map_icon_button.dart`, `time_till.dart` |
| UI: status and certs | `checkin_status_*.dart`, `cert_page.dart`, `confetti_dialog.dart`, `screen_shot.dart` |
| Infrastructure | `files.dart`, `mylogger.dart`, `log_page.dart`, `snackbarglobal.dart` (Flushbar), `exception.dart`, `utility.dart`, `side_menu.dart` |
| Mock mode | `mock/mock_mode.dart` (`kMockMode`), `mock/mock_server.dart` (fake feed, regions and check-in endpoint), `mock/mock_location.dart` (fake GPS) |

## Seams for testing and mock mode
- **Network:** every call uses top-level `package:http` functions, and `http.runWithClient` swaps the client. `MockServer.handle` routes `region_list`, `scheduled_events` and POST check-ins. Same-origin requests, such as `version.json` on web, pass through, as do GETs to the map tile host (`RouteMap.tileHost`).
- **Router:** `RouteMapPage` takes an optional `RouteService`, else `RouteService.factory`. Under `flutter test` the default is `NoRouteService`, which makes no requests. In mock mode `MockServer` answers the router host (`RouteService.routerHost`) with canned routes and never passes those requests through.
- **Map tiles:** `RouteMap` takes an optional `TileProvider`, else `RouteMap.tileProviderFactory`. Under `flutter test` the default is `NoTileProvider`, which makes no requests.
- **Location:** `RiderLocation.updateLocation` and `checkLocationPermissions` short-circuit to `MockLocation` when `kMockMode` is set.
- **Clock:** `MockServer.now` can be overridden. App code calls `DateTime.now()` directly, so tests for time-dependent rules should build events relative to a fixed time.
- **Fixture:** `assets/mock/future_events.json`, a legacy feed. `MockServer.shiftEvent` re-dates it and fills in missing fields.

## Known web limitations
- `screen_shot.dart` (sharing the certificate image) uses `dart:io` and does not work on web.
- `upgrader` (store version check) is disabled in mock mode.
- `geolocator` is never called in mock mode.
