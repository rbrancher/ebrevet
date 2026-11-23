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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'region.dart';
import 'scheduled_events.dart';

/// Shown for a configured region that is not in [Region.regionMap].
const String unknownRegionMessage = "Somehow the region selected is not in the "
    "list of regions this app knows about. Please try refreshing the region list.";

/// Shown when only one source is configured, so it cannot be removed.
const String lastSourceMessage =
    'At least one source is required. Add another source before removing '
    'this one.';

/// A short name for a configured source, for lists and summaries.
String sourceLabel(ScheduledEventsSource s) {
  if (s.isCustom) return s.description;
  if (s.isUnknownRegion) return 'Region ${s.regionID}';
  return s.region.regionName;
}

/// Full-screen picker for the configured event sources (intent 0016): the
/// configured list (reorder, remove) and the International, US and Custom
/// categories to add or remove sources. Every change is saved at once
/// through [SourceSelection.setSources].
class RegionPickerPage extends StatefulWidget {
  const RegionPickerPage({super.key});

  @override
  State<RegionPickerPage> createState() => _RegionPickerPageState();
}

class _RegionPickerPageState extends State<RegionPickerPage> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _save(List<ScheduledEventsSource> sources,
      {bool selectFirst = false}) async {
    await context
        .read<SourceSelection>()
        .setSources(sources, selectFirst: selectFirst);
    if (mounted) setState(() {});
  }

  Future<void> _add(ScheduledEventsSource source) async {
    final sources = EventSources.list;
    if (!EventSources.canAdd(sources, source)) return; // no duplicates
    await _save([...sources, source]);
  }

  Future<void> _remove(String key) async {
    final sources = EventSources.list;
    if (sources.length <= 1) return; // the last source stays
    await _save([
      for (final s in sources)
        if (s.key != key) s
    ]);
  }

  /// Before the events page switcher (slice c), the first source is the one
  /// shown, so a reorder selects the new first source.
  Future<void> _move(int from, int to) async {
    final sources = EventSources.list;
    if (from == to || to < 0 || to >= sources.length) return;
    final s = sources.removeAt(from);
    sources.insert(to, s);
    await _save(sources, selectFirst: true);
  }

  bool _matches(Map<String, String> r, String q) {
    if (q.isEmpty) return true;
    return [
      r['region_name'],
      r['club_name'],
      r['state_name'],
      r['state_code'],
      r['country_code'],
    ].any((v) => v != null && v.toLowerCase().contains(q));
  }

  @override
  Widget build(BuildContext context) {
    final sources = EventSources.list;
    final canRemove = sources.length > 1;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Event Regions'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SearchBar(
              key: const Key('region-search'),
              controller: _search,
              hintText: 'Search regions, states or countries',
              leading: const Icon(Icons.search),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
        ),
      ),
      body: CustomScrollView(
        key: const Key('region-picker-list'),
        slivers: [
          _header(context, 'Configured sources'),
          SliverReorderableList(
            itemCount: sources.length,
            onReorder: (from, to) => _move(from, to > from ? to - 1 : to),
            proxyDecorator: (child, index, animation) =>
                Material(elevation: 4, child: child),
            itemBuilder: (context, i) {
              final s = sources[i];
              return Material(
                key: ValueKey('configured-${s.key}'),
                color: Colors.transparent,
                child: ListTile(
                  contentPadding: const EdgeInsets.only(left: 4, right: 4),
                  leading: ReorderableDragStartListener(
                    index: i,
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Icon(Icons.drag_handle, semanticLabel: 'Drag'),
                    ),
                  ),
                  title: Text(sourceLabel(s)),
                  subtitle: Text(
                    s.isUnknownRegion ? unknownRegionMessage : s.description,
                    style: s.isUnknownRegion
                        ? TextStyle(color: scheme.error)
                        : null,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Move up',
                        icon: const Icon(Icons.arrow_upward),
                        onPressed: i > 0 ? () => _move(i, i - 1) : null,
                      ),
                      IconButton(
                        tooltip: 'Move down',
                        icon: const Icon(Icons.arrow_downward),
                        onPressed: i < sources.length - 1
                            ? () => _move(i, i + 1)
                            : null,
                      ),
                      IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: canRemove ? () => _remove(s.key) : null,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          if (!canRemove)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(lastSourceMessage,
                    key: Key('last-source-message'),
                    style: TextStyle(fontStyle: FontStyle.italic)),
              ),
            ),
          SliverList(
              delegate: SliverChildListDelegate(_categories(context, sources))),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, String title) => SliverToBoxAdapter(
        child: _headerText(context, title),
      );

  Widget _headerText(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(title,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );

  Widget _groupText(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Text(title, style: Theme.of(context).textTheme.labelLarge),
      );

  List<Widget> _categories(
      BuildContext context, List<ScheduledEventsSource> sources) {
    final configured = {for (final s in sources) s.key};
    final onlyOne = sources.length <= 1;

    final custom = ScheduledEventsSource(ScheduleEventsSourceID.fromURL);
    final customOn = configured.contains(custom.key);

    final q = _query.trim().toLowerCase();
    final ids = Region.regionMap.keys
        .where((id) => _matches(Region.regionMap[id]!, q))
        .toList()
      ..sort(Region.compareByStateName);
    bool isUS(String id) => Region.regionMap[id]!['country_code'] == 'US';

    Widget regionTile(String id, ScheduleEventsSourceID category) {
      final source = ScheduledEventsSource(category, regionID: id);
      final on = configured.contains(source.key);
      final r = Region.regionMap[id]!;
      final club = r['club_name'] ?? '';
      return CheckboxListTile(
        key: ValueKey('region-$id'),
        value: on,
        title: Text(r['region_name'] ?? id),
        subtitle:
            (club.isNotEmpty && club != r['region_name']) ? Text(club) : null,
        onChanged: (on && onlyOne)
            ? null
            : (v) => (v ?? false) ? _add(source) : _remove(source.key),
      );
    }

    List<Widget> grouped(List<String> group, ScheduleEventsSourceID category,
        String Function(String id) groupName) {
      final out = <Widget>[];
      String? last;
      for (final id in group) {
        final g = groupName(id);
        if (g != last) {
          out.add(_groupText(context, g));
          last = g;
        }
        out.add(regionTile(id, category));
      }
      return out;
    }

    final intl = ids.where((id) => !isUS(id)).toList();
    final us = ids.where(isUS).toList();

    return [
      _headerText(context, 'Custom'),
      CheckboxListTile(
        key: const ValueKey('custom-source'),
        value: customOn,
        title: Text(custom.description),
        subtitle: const Text('URL and secret are set in Settings'),
        onChanged: (customOn && onlyOne)
            ? null
            : (v) => (v ?? false) ? _add(custom) : _remove(custom.key),
      ),
      if (ids.isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('No matching regions', key: Key('no-matching-regions')),
        ),
      if (intl.isNotEmpty) ...[
        _headerText(context, 'International'),
        ...grouped(intl, ScheduleEventsSourceID.fromInternationalRegion,
            (id) => Region.regionMap[id]!['country_code'] ?? '?'),
      ],
      if (us.isNotEmpty) ...[
        _headerText(context, 'US'),
        ...grouped(us, ScheduleEventsSourceID.fromRegion,
            (id) => Region.regionMap[id]!['state_name'] ?? '?'),
      ],
      const SizedBox(height: 16),
    ];
  }
}
