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

// Side menu: kept as a classic `Drawer` rather than `NavigationDrawer`
// (intent 0005, AC8). NavigationDrawer is built for switching between a
// flat set of top-level destinations with one selected. This menu instead
// pushes pages on top of the current one, opens the About dialog, and has
// a nested "Available Events" ExpansionTile, none of which map onto
// NavigationDrawerDestination. The Drawer already takes its M3 surface and
// shape from the theme; header, spacing and text use theme values only.

// import 'package:ebrevet_card/mylogger.dart';
import 'package:ebrevet_card/event.dart';
import 'package:ebrevet_card/my_activated_events_page.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_settings.dart';
import 'app_tokens.dart';
import 'settings_page.dart';
import 'log_page.dart';
import 'profile_page.dart';
import 'event_list_page.dart';

class SideMenuDrawer extends StatelessWidget {
  final Function? onClose;
  const SideMenuDrawer({super.key, this.onClose});

  @override
  Widget build(BuildContext context) {
    var textTheme = Theme.of(context).textTheme;
    var scheme = Theme.of(context).colorScheme;
    var tokens = AppTokens.of(context);
    var onHeader = scheme.onPrimaryContainer;
    var menuTitleStyle = textTheme.titleLarge?.copyWith(color: onHeader);
    var menuItemStyle = textTheme.titleMedium;
    var subtitleStyle = textTheme.titleSmall?.copyWith(color: onHeader);
    var headerColor = scheme.primaryContainer;

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: headerColor,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('eBrevet Main Menu', style: menuTitleStyle),
                SizedBox(
                  height: tokens.spaceSmall,
                ),
                // Opens the Profile page (intent 0006).
                InkWell(
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context)
                        .push(MaterialPageRoute(
                          builder: (context) => const ProfilePage(),
                        ))
                        .then((value) => onClose?.call());
                  },
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      widthFactor: 1,
                      child: Text(
                          'Rider: ${AppSettings.firstName.value} ${AppSettings.lastName.value} (${AppSettings.rusaID.value})',
                          style: subtitleStyle),
                    ),
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: Text(
              'Settings',
              style: menuItemStyle,
            ),
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context)
                  .push(MaterialPageRoute(
                    builder: (context) => const SettingsPage(),
                  ))
                  .then((value) => onClose?.call());
            },
          ),
          ListTile(
            leading: const Icon(Icons.pedal_bike),
            title: Text(
              'My Rides',
              style: menuItemStyle,
            ),
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => const MyActivatedEventsPage(),
              ));
              //.then((value) => onClose?.call());
            },
          ),
          ExpansionTile(
            leading: const Icon(Icons.pedal_bike),
            title: Text('Available Events', style: menuItemStyle),
            children: [
              for (var filter in EventFilter.values)
                ListTile(
                  leading: const Icon(Icons.arrow_right),
                  title: Text(filter.description),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            ScheduledEventsPage(eventFilter: filter),
                      ),
                    );
                  },
                ),
            ],
          ),

          // if (AppSettings.isMagicRusaID)  // Everyone can see log
          ListTile(
            leading: const Icon(Icons.newspaper),
            title: Text(
              'Activity Log',
              style: menuItemStyle,
            ),
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => const LogPage(),
              ));
            },
          ),
          ListTile(
            leading: const Icon(Icons.info),
            title: Text(
              'About eBrevet',
              style: menuItemStyle,
            ),
            onTap: () {
              Navigator.pop(context);
              aboutDialog(context);
            },
          ),
        ],
      ),
    );
  }

  void aboutDialog(BuildContext context) {
    var cYear = DateTime.now().year;
    showAboutDialog(
        context: context,
        applicationName: 'eBrevet',
        applicationIcon: Image.asset(
          'assets/images/eBrevet-128.png',
          width: 64,
        ),
        applicationVersion:
            "v${AppSettings.version ?? '?'} (${AppSettings.buildNumber})",
        applicationLegalese:
            '(c)$cYear Chris Nadovich. This is free software licensed under GPLv3.',
        children: [
          SizedBox(
            height: AppTokens.of(context).spaceMedium,
          ),
          const Text(
            'A self-auditing electronic brevet card for Randonneuring.',
            textAlign: TextAlign.center,
          ),
          InkWell(
            onTap: () =>
                launchUrl(Uri.parse('https://github.com/ctnadovich/ebrevet')),
            child: Text(
              'Documentation and Source Code',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.underline),
            ),
          ),
        ]);
  }
}
