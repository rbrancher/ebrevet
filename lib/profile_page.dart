// Copyright (C) 2026 eBrevet autonomous AI-SDLC
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

// Read-only rider profile with ride stats (intent 0006). Shows who the app
// thinks the rider is and a summary of finished rides saved on this phone.
// The Edit action opens the rider edit form (intent 0007).

import 'package:flutter/material.dart';

import 'activated_event.dart';
import 'app_settings.dart';
import 'app_tokens.dart';
import 'my_activated_events.dart';
import 'my_activated_events_page.dart';
import 'profile_stats.dart';
import 'rider_edit_page.dart';

/// Up to two initials from the rider's first and last name, or '' if no
/// name is set.
String riderInitials(String first, String last) => [first, last]
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .map((s) => s.characters.first.toUpperCase())
    .join();

String get _currentInitials =>
    riderInitials(AppSettings.firstName.value, AppSettings.lastName.value);

void _openProfile(BuildContext context, {VoidCallback? onClose}) {
  Navigator.of(context)
      .push(MaterialPageRoute(builder: (context) => const ProfilePage()))
      .then((_) => onClose?.call());
}

/// App bar action that opens the Profile page: an initials avatar, or a
/// generic account icon if no name is set.
class ProfileAvatarButton extends StatelessWidget {
  final VoidCallback? onClose;
  const ProfileAvatarButton({super.key, this.onClose});

  @override
  Widget build(BuildContext context) {
    final initials = _currentInitials;
    final scheme = Theme.of(context).colorScheme;
    // The tooltip is shown on long press; the label is read by screen
    // readers (once, not twice).
    return Tooltip(
      message: 'Profile',
      excludeFromSemantics: true,
      child: MergeSemantics(
        child: Semantics(
          label: 'Profile',
          child: _button(context, initials, scheme),
        ),
      ),
    );
  }

  Widget _button(BuildContext context, String initials, ColorScheme scheme) {
    return IconButton(
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      onPressed: () => _openProfile(context, onClose: onClose),
      icon: ExcludeSemantics(
        child: initials.isEmpty
            ? const Icon(Icons.account_circle)
            : CircleAvatar(
                radius: 16,
                backgroundColor: scheme.primaryContainer,
                foregroundColor: scheme.onPrimaryContainer,
                child: Text(initials,
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(color: scheme.onPrimaryContainer)),
              ),
      ),
    );
  }
}

class ProfilePage extends StatefulWidget {
  /// Rides to summarise. Defaults to the rides saved on this phone.
  final List<ActivatedEvent>? rides;

  const ProfilePage({super.key, this.rides});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Future<void> _edit() async {
    await Navigator.of(context).push(MaterialPageRoute(
        fullscreenDialog: true, builder: (context) => const RiderEditPage()));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final tokens = AppTokens.of(context);
    final stats = ProfileStats.from(
        widget.rides ?? MyActivatedEvents.myActivatedEventsList,
        AppSettings.rusaID.value);

    final name = AppSettings.fullName.trim();
    final riderID = AppSettings.rusaID.value.trim();
    final initials = _currentInitials;

    Widget sectionHeader(String text) => Padding(
          padding: EdgeInsets.fromLTRB(tokens.spaceMedium, tokens.spaceLarge,
              tokens.spaceMedium, tokens.spaceSmall),
          child: Text(text,
              style: textTheme.titleMedium?.copyWith(color: scheme.primary)),
        );

    Widget statCard(String value, String label) => Expanded(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(tokens.spaceMedium),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: tokens.numeric),
                  SizedBox(height: tokens.spaceSmall / 2),
                  Text(label,
                      style: textTheme.labelMedium
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ),
        );

    final header = Padding(
      padding: EdgeInsets.all(tokens.spaceMedium),
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: scheme.primaryContainer,
            foregroundColor: scheme.onPrimaryContainer,
            child: initials.isEmpty
                ? const Icon(Icons.person, size: 32)
                : Text(initials,
                    style: textTheme.headlineSmall
                        ?.copyWith(color: scheme.onPrimaryContainer)),
          ),
          SizedBox(width: tokens.spaceMedium),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name.isEmpty ? 'No name set' : name,
                    style: textTheme.headlineSmall),
                SizedBox(height: tokens.spaceSmall / 2),
                Text('Rider ID: ${riderID.isEmpty ? 'not set' : riderID}',
                    style: textTheme.bodyLarge
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );

    final statsGroup = stats.isEmpty
        ? Card(
            child: Padding(
              padding: EdgeInsets.all(tokens.spaceMedium),
              child: Column(
                children: [
                  Icon(Icons.directions_bike,
                      size: 48, color: scheme.onSurfaceVariant),
                  SizedBox(height: tokens.spaceSmall),
                  Text('No finished rides yet', style: textTheme.titleMedium),
                  SizedBox(height: tokens.spaceSmall / 2),
                  Text(
                    'Finish a brevet with eBrevet and your rides will '
                    'show up here.',
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              statCard('${stats.rides}', 'Rides'),
              statCard('${stats.totalKm}', 'Total km'),
              statCard('${stats.longestKm}', 'Longest ride (km)'),
            ],
          );

    final months = AppSettings.keepPastEventMonths.value;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.medium(
            title: const Text('Profile'),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: 'Edit',
                onPressed: _edit,
              ),
            ],
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              header,
              sectionHeader('Ride stats'),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: tokens.spaceSmall),
                child: statsGroup,
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(tokens.spaceMedium,
                    tokens.spaceSmall, tokens.spaceMedium, 0),
                child: Text(
                  'Stats come from rides saved on this phone. History is '
                  'pruned after $months months (the "keep past events" '
                  'setting), so these are not lifetime totals.',
                  style: textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              sectionHeader('Distances completed'),
              for (final b in DistanceBucket.values)
                _bucketTile(context, b, stats.buckets[b]!),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.pedal_bike),
                title: const Text('My Rides'),
                subtitle: const Text('Every ride saved on this phone'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (context) => const MyActivatedEventsPage())),
              ),
              SizedBox(height: tokens.spaceLarge),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _bucketTile(BuildContext context, DistanceBucket b, int count) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = AppTokens.of(context);
    final done = count > 0;
    return ListTile(
      leading: Icon(done ? Icons.check_circle : Icons.radio_button_unchecked,
          color: done ? scheme.primary : scheme.onSurfaceVariant),
      title: Text(b.label),
      trailing: done
          ? Text('$count', style: tokens.numeric)
          : Text('Not yet',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant)),
    );
  }
}
