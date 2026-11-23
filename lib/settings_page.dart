// Copyright (C) 2023 Chris Nadovich
// This file is part of eBrevet <https://github.com/ctnadovich/ebrevet>.
//
// eBrevet is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// eBrevet is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with eBrevet.  If not, see <http://www.gnu.org/licenses/>.

// import 'dart:nativewrappers/_internal/vm/lib/ffi_allocation_patch.dart';

import 'package:ebrevet_card/scheduled_events.dart';
import 'package:ebrevet_card/mylogger.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'day_night.dart';
import 'app_settings.dart';
import 'settings_tiles.dart';
import 'my_settings.dart';
import 'region.dart';
import 'app_tokens.dart';
import 'rider_edit_page.dart';
import 'region_picker_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
  });
  @override
  SettingsPageState createState() {
    return SettingsPageState();
  }
}

class SettingsPageState extends State<SettingsPage> {
  final spacerBox = const SizedBox(
    height: 16,
  );

  @override
  Widget build(BuildContext context) {
    var dayNight = context.watch<DayNight>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          IconButton(
              icon: dayNight.icon,
              onPressed: () {
                dayNight.toggleMode();
              })
        ],
      ),
      body: Container(
        color: Theme.of(context).colorScheme.primaryContainer,
        padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
        child: ListView(
          children: [
            Column(
              children: [
                const EventSearchSettings(),
                spacerBox,
                OptionalAppSettings(
                  onClear: () => setState(() {}),
                ),
                spacerBox,
                spacerBox,
                if (AppSettings.isMagicRusaID)
                  AdvancedSettings(
                    onClear: () => setState(() {}),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class EventSearchSettings extends StatefulWidget {
  // final void Function() onClear;

  final bool initiallyExpanded;

  const EventSearchSettings({super.key, this.initiallyExpanded = false});

  @override
  State<EventSearchSettings> createState() => _EventSearchSettingsState();
}

class _EventSearchSettingsState extends State<EventSearchSettings> {
  final spacerBox = const SizedBox(
    height: 16,
  );

  @override
  Widget build(BuildContext context) {
    var sourceSelection = context.watch<SourceSelection>();
    final sources = EventSources.list;
    final n = sources.length;

    // A configured region can be missing from the region map (e.g. removed
    // from the region list). It stays configured (intent 0015): the message
    // below says so, and the rider can remove it in the region picker.
    final bool anyUnknown = sources.any((s) => s.isUnknownRegion);
    if (anyUnknown) {
      MyLogger.entry('Configured for region not in map.');
    }
    final customConfigured = sources.any((s) => s.isCustom);

    return Material(
      color: Colors.transparent,
      child: ExpansionTile(
        title: const Text('Event Info Source'),
        subtitle: const Text("Select where to obtain event info. "),
        initiallyExpanded: widget.initiallyExpanded,
        children: [
          // Summary row (intent 0016); the picker edits the source list.
          ListTile(
            key: const Key('event-sources-summary'),
            title: Text(n == 1 ? '1 region' : '$n regions'),
            subtitle: Text([
              for (var i = 0; i < n; i++) '${i + 1}. ${sourceLabel(sources[i])}'
            ].join('\n')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(
              builder: (context) => const RegionPickerPage(),
            ))
                .then((_) {
              if (mounted) setState(() {});
            }),
          ),
          if (anyUnknown) const Text(unknownRegionMessage),
          // The custom source's URL and secret, while it is configured.
          if (customConfigured) ...[
            DialogInputSettingsTile(
              AppSettings.eventInfoURL,
              onChanged: sourceSelection.customSettingsChanged,
            ),
            DialogInputSettingsTile(
              AppSettings.customRegionSecret,
              onChanged: sourceSelection.customSettingsChanged,
            ),
          ],
          spacerBox
        ],
      ),
    );
  }
}

class OptionalAppSettings extends StatefulWidget {
  final void Function() onClear;

  const OptionalAppSettings({
    super.key,
    required this.onClear,
  });

  @override
  State<OptionalAppSettings> createState() => _OptionalAppSettingsState();
}

class _OptionalAppSettingsState extends State<OptionalAppSettings> {
  @override
  Widget build(BuildContext context) {
    var spacerBox = const SizedBox(
      height: 16,
    );
    return Material(
      color: Colors.transparent,
      child: ExpansionTile(
        title: const Text('Preferences'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 8, 8),
            child: Container(
                padding: const EdgeInsets.all(16),
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: Column(children: [
                  SwitchSettingsTile(AppSettings.allowCheckinComment),
                  SwitchSettingsTile(AppSettings.enablePostCheckinDialog),
                  SwitchSettingsTile(AppSettings.notifyOtherRiderComments),
                  SwitchSettingsTile(AppSettings.canDeletePastEvents),
                  DialogInputSettingsTile(AppSettings.gpsRefreshPeriod),
                  SwitchSettingsTile(AppSettings.finishConfetti),
                  // Always shown (intent 0016): the region picker lists
                  // whatever regions are loaded.
                  Column(
                    children: [
                      spacerBox,
                      Text(
                          "There are ${Region.numberOfUsRegions} RUSA regions, "
                          "and ${Region.numberOfNonUsRegions} International regions loaded. "
                          "If your region is not in either the RUSA or Intl list, "
                          "try getting the latest region list from the server."),
                      spacerBox,
                      FilledButton.tonal(
                        onPressed: () async {
                          await Region.fetchRegionsFromServer();
                          setState(() {});
                        },
                        child: const Text('Get Latest Region List'),
                      ),
                    ],
                  ),
                ])),
          ),
        ],
      ),
    );
  }
}

class AdvancedSettings extends StatefulWidget {
  final void Function() onClear;

  const AdvancedSettings({
    super.key,
    required this.onClear,
  });

  @override
  State<AdvancedSettings> createState() => _AdvancedSettingsState();
}

class _AdvancedSettingsState extends State<AdvancedSettings> {
  @override
  Widget build(BuildContext context) {
    var sourceSelection = context.read<SourceSelection>();
    return Material(
      color: Colors.transparent,
      child: ExpansionTile(
        title: const Text('Developer Options'),
        subtitle: Text(
          "Using these may disqualify your ride.",
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 8, 8),
            child: Container(
                padding: const EdgeInsets.all(16),
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: Column(children: [
                  SwitchSettingsTile(AppSettings.openTimeOverride),
                  SwitchSettingsTile(AppSettings.prerideDateWindowOverride),
                  SwitchSettingsTile(AppSettings.canCheckInLate),
                  SwitchSettingsTile(AppSettings.controlProximityOverride),
                  DialogInputSettingsTile(
                      AppSettings.keepInFutureEventListAfterFinishHours),
                  DialogInputSettingsTile(AppSettings.keepPastEventMonths),
                  DialogInputSettingsTile(AppSettings.proximityRadius),
                  SwitchSettingsTile(AppSettings.authenticateEventsData),
                  const SizedBox(
                    height: 16,
                  ),
                  OutlinedButton(
                    onPressed: () =>
                        MySetting.clear().then((_) => widget.onClear()),
                    child: const Text('Clear All Settings'),
                  ),
                  const SizedBox(
                    height: 16,
                  ),
                  OutlinedButton(
                    onPressed: () {
                      // The selected source only (intent 0015).
                      ScheduledEvents.clearSource(EventSources.selected);
                      sourceSelection.refresh();
                    },
                    child: const Text('Clear Event List'),
                  ),
                ])),
          ),
        ],
      ),
    );
  }
}

/// First-run screen (intent 0007): the shared rider form ([RiderForm]) with
/// a Continue action that saves and then calls [onContinue]. Rider details
/// are edited from the Profile page after first run, not from Settings.
class RequiredAppSettings extends StatefulWidget {
  final void Function()? onContinue;

  const RequiredAppSettings({
    super.key,
    this.onContinue,
  });

  @override
  State<RequiredAppSettings> createState() => _RequiredAppSettingsState();
}

class _RequiredAppSettingsState extends State<RequiredAppSettings> {
  final _form = GlobalKey<RiderFormState>();

  Future<void> _continue() async {
    if (await (_form.currentState?.save() ?? Future.value(false))) {
      widget.onContinue?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return ListView(
      children: [
        Text(
          'Required Settings',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        Text(
          'Enter your First Name, Last Name, and Rider ID',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        SizedBox(height: tokens.spaceMedium),
        RiderForm(key: _form),
        SizedBox(height: tokens.spaceMedium),
        FilledButton(onPressed: _continue, child: const Text('Continue')),
      ],
    );
  }
}
