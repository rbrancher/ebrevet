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

// Full-screen rider edit form (intent 0007). One form edits first name,
// last name and Rider ID. The same form body ([RiderForm]) is used by the
// Profile page's Edit action and by the first-run Required Settings screen.

import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'app_tokens.dart';
import 'my_settings.dart';
import 'mylogger.dart';

/// Writes the changed rider fields. If the Rider ID changes, developer
/// options are cleared unless the new ID is the magic developer ID (then a
/// warning is logged). An unchanged ID clears nothing.
Future<void> saveRiderSettings({
  required String firstName,
  required String lastName,
  required String rusaID,
}) async {
  if (firstName != AppSettings.firstName.value) {
    await AppSettings.firstName.setValue(firstName);
  }
  if (lastName != AppSettings.lastName.value) {
    await AppSettings.lastName.setValue(lastName);
  }
  if (rusaID != AppSettings.rusaID.value) {
    await AppSettings.rusaID.setValue(rusaID);
    if (rusaID != AppSettings.magicRUSAID) {
      await MySetting.clearDeveloperOptions();
    } else {
      MyLogger.entry("Developer Options Enabled", severity: Severity.warning);
    }
  }
}

/// The shared form body: three text fields prefilled from [AppSettings],
/// validated with the settings' own validators, plus a warning when the
/// Rider ID is being changed. Use a `GlobalKey<RiderFormState>` to call
/// [RiderFormState.save] and read [RiderFormState.isDirty].
class RiderForm extends StatefulWidget {
  /// Called whenever a field changes.
  final VoidCallback? onChanged;

  const RiderForm({super.key, this.onChanged});

  @override
  State<RiderForm> createState() => RiderFormState();
}

class RiderFormState extends State<RiderForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _first =
      TextEditingController(text: AppSettings.firstName.value);
  late final TextEditingController _last =
      TextEditingController(text: AppSettings.lastName.value);
  late final TextEditingController _id =
      TextEditingController(text: AppSettings.rusaID.value);

  /// True if any field differs from the stored setting.
  bool get isDirty =>
      _first.text != AppSettings.firstName.value ||
      _last.text != AppSettings.lastName.value ||
      _id.text != AppSettings.rusaID.value;

  /// True if the Rider ID is being changed from a stored, non-empty ID.
  bool get isChangingRiderID =>
      AppSettings.rusaID.value.isNotEmpty &&
      _id.text != AppSettings.rusaID.value;

  /// Validates and, if valid, writes the fields. Returns false (and writes
  /// nothing) if any field is invalid.
  Future<bool> save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return false;
    await saveRiderSettings(
        firstName: _first.text, lastName: _last.text, rusaID: _id.text);
    return true;
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _id.dispose();
    super.dispose();
  }

  void _changed(String _) {
    setState(() {});
    widget.onChanged?.call();
  }

  Widget _field(TextEditingController c, MySetting<String> setting,
      {TextInputType? keyboardType, TextInputAction? action}) {
    return TextFormField(
      controller: c,
      decoration: InputDecoration(
        labelText: setting.title,
        prefixIcon: setting.icon,
        border: const OutlineInputBorder(),
      ),
      keyboardType: keyboardType,
      textInputAction: action ?? TextInputAction.next,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: setting.validator,
      onChanged: _changed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final gap = SizedBox(height: tokens.spaceMedium);

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _field(_first, AppSettings.firstName,
              keyboardType: TextInputType.name),
          gap,
          _field(_last, AppSettings.lastName, keyboardType: TextInputType.name),
          gap,
          _field(_id, AppSettings.rusaID,
              keyboardType: TextInputType.number, action: TextInputAction.done),
          if (isChangingRiderID) ...[
            gap,
            Card(
              key: const Key('rider-id-warning'),
              margin: EdgeInsets.zero,
              color: scheme.errorContainer,
              child: Padding(
                padding: EdgeInsets.all(tokens.spaceMedium),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber, color: scheme.onErrorContainer),
                    SizedBox(width: tokens.spaceSmall),
                    Expanded(
                      child: Text(
                        'Start codes depend on your Rider ID. Rides saved '
                        'under your old Rider ID will not count in your '
                        'profile stats.',
                        style: textTheme.bodyMedium
                            ?.copyWith(color: scheme.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Full-screen dialog for editing the rider. Pops `true` after saving.
class RiderEditPage extends StatefulWidget {
  const RiderEditPage({super.key});

  @override
  State<RiderEditPage> createState() => _RiderEditPageState();
}

class _RiderEditPageState extends State<RiderEditPage> {
  final _form = GlobalKey<RiderFormState>();

  bool get _dirty => _form.currentState?.isDirty ?? false;

  Future<void> _save() async {
    if (await (_form.currentState?.save() ?? Future.value(false))) {
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep editing')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Discard')),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return PopScope<bool>(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Cancel',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: const Text('Edit rider'),
          actions: [
            TextButton(onPressed: _save, child: const Text('Save')),
            SizedBox(width: tokens.spaceSmall),
          ],
        ),
        body: ListView(
          padding: EdgeInsets.all(tokens.spaceMedium),
          children: [
            RiderForm(key: _form, onChanged: () => setState(() {})),
          ],
        ),
      ),
    );
  }
}
