import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:teamzone_app/src/features/attendance_export/export_models.dart';
import 'package:teamzone_app/src/features/attendance_export/export_services.dart';
import 'package:teamzone_app/src/features/attendance_export/laget_se/laget_se_adapter.dart';
import 'package:teamzone_app/src/features/attendance_export/laget_se/laget_se_member_import.dart';
import 'package:teamzone_app/src/features/attendance_export/ui/laget_se_member_import_page.dart';
import 'package:teamzone_app/src/shared/widgets/app_states.dart';

/// Laginställningar → Integrationer → laget.se: enable the export and
/// manage member links. No laget.se credentials are asked for or stored.
class LagetSeSettingsPage extends StatefulWidget {
  const LagetSeSettingsPage({
    required this.teamId,
    required this.teamName,
    required this.services,
    super.key,
  });
  final String teamId, teamName;
  final AttendanceExportServices services;

  @override
  State<LagetSeSettingsPage> createState() => _LagetSeSettingsPageState();
}

class _LagetSeSettingsPageState extends State<LagetSeSettingsPage> {
  TeamIntegrationSettings? _settings;
  final _teamRef = TextEditingController();
  bool _enabled = false, _busy = false, _onlyMissing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _teamRef.dispose();
    super.dispose();
  }

  void _apply(TeamIntegrationSettings settings) => setState(() {
    _settings = settings;
    _enabled = settings.enabled;
    _teamRef.text = settings.externalTeamRef ?? '';
    _error = null;
  });

  Future<void> _load() async {
    try {
      _apply(
        await widget.services.getTeamIntegration(
          teamId: widget.teamId,
          provider: lagetSeProvider,
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Inställningarna kunde inte laddas.');
      }
    }
  }

  Future<void> _run(Future<TeamIntegrationSettings> Function() action) async {
    setState(() => _busy = true);
    try {
      final settings = await action();
      if (mounted) _apply(settings);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = switch (attendanceExportErrorCode(error)) {
            'external_id_taken' =>
              'Det laget.se-ID:t är redan kopplat till en annan person i laget.',
            'revision_conflict' =>
              'Någon annan har ändrat inställningarna. Läs in dem igen.',
            'invalid_external_id' => 'laget.se-ID får bara innehålla siffror.',
            _ => 'Ändringen kunde inte sparas. Försök igen.',
          },
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveSettings() => _run(
    () => widget.services.setTeamIntegration(
      teamId: widget.teamId,
      provider: lagetSeProvider,
      enabled: _enabled,
      externalTeamRef: _teamRef.text.trim().isEmpty
          ? null
          : _teamRef.text.trim(),
      expectedRevision: _settings!.revision,
    ),
  );

  Future<void> _importMembers() async {
    final LagetSeMemberFile file;
    try {
      // Read into memory only; Teamzone writes no copy of the file.
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      final bytes = picked?.files.singleOrNull?.bytes;
      if (bytes == null) return;
      file = parseLagetSeMemberFile(utf8.decode(bytes));
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
      return;
    } catch (_) {
      if (mounted) setState(() => _error = 'Filen kunde inte läsas.');
      return;
    }
    if (!mounted) return;
    final updated = await Navigator.of(context).push<TeamIntegrationSettings>(
      MaterialPageRoute(
        builder: (_) => LagetSeMemberImportPage(
          settings: _settings!,
          file: file,
          services: widget.services,
        ),
      ),
    );
    if (updated != null && mounted) _apply(updated);
  }

  Future<void> _editLink(IntegrationTeamMember member) async {
    final existing = _settings!.linkFor(member.personId);
    final edited = await showDialog<_LinkDraft>(
      context: context,
      builder: (_) => _MemberLinkDialog(member: member, existing: existing),
    );
    if (edited == null || !mounted) return;
    if (edited.delete) {
      await _run(
        () => widget.services.deleteMemberLink(
          teamId: widget.teamId,
          provider: lagetSeProvider,
          personId: member.personId,
          expectedRevision: existing!.revision,
        ),
      );
      return;
    }
    await _run(
      () => widget.services.saveMemberLink(
        teamId: widget.teamId,
        provider: lagetSeProvider,
        personId: member.personId,
        externalId: edited.externalId,
        externalName: edited.externalName,
        externalRole: edited.externalRole,
        expectedRevision: existing?.revision ?? 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('laget.se · ${widget.teamName}')),
      body: settings == null
          ? (_error == null
                ? const AppLoadingIndicator(label: 'Laddar…')
                : Center(
                    child: AppStateCard(
                      icon: Icons.sync_problem,
                      title: 'Kunde inte ladda',
                      message: _error!,
                      action: FilledButton(
                        onPressed: _load,
                        child: const Text('Försök igen'),
                      ),
                    ),
                  ))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Närvaroexport till laget.se',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Teamzone skapar en exportfil med registrerad närvaro. '
                  'Själva överföringen till laget.se görs med ett separat '
                  'verktyg. Teamzone lagrar inga inloggningsuppgifter till laget.se.',
                ),
                SwitchListTile(
                  key: const Key('laget-se-enabled'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Aktivera export till laget.se'),
                  value: _enabled,
                  onChanged: _busy ? null : (v) => setState(() => _enabled = v),
                ),
                TextField(
                  controller: _teamRef,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'Lagets namn i laget.se-adressen (valfritt)',
                    helperText:
                        'T.ex. EksjoFotbollJ18. Används inte för exporten ännu.',
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    onPressed: _busy ? null : _saveSettings,
                    child: const Text('Spara'),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 24),
                const Divider(),
                ..._memberSection(context, settings),
              ],
            ),
    );
  }

  List<Widget> _memberSection(
    BuildContext context,
    TeamIntegrationSettings settings,
  ) {
    final theme = Theme.of(context);
    final missing = settings.members
        .where((m) => settings.linkFor(m.personId) == null)
        .length;
    final memberIds = {for (final m in settings.members) m.personId};
    // Links for people no longer on the team (e.g. guests) stay editable.
    final orphanLinks = settings.links
        .where((link) => !memberIds.contains(link.personId))
        .toList();
    final members = [
      for (final member in settings.members)
        if (!_onlyMissing || settings.linkFor(member.personId) == null) member,
    ];
    return [
      Text('Medlemskopplingar', style: theme.textTheme.titleMedium),
      const SizedBox(height: 4),
      Text(
        '${settings.links.length} kopplade · $missing saknar koppling. '
        'Kopplingen görs med personens ID i laget.se och gäller bara det här laget.',
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        key: const Key('laget-se-import-members'),
        onPressed: _busy ? null : _importMembers,
        icon: const Icon(Icons.upload_file_outlined),
        label: const Text('Importera medlemslista från laget.se'),
      ),
      Text(
        'Skapa filen med synkverktyget: npm run members. Du godkänner varje koppling innan den sparas.',
        style: theme.textTheme.bodySmall,
      ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Visa bara de som saknar koppling'),
        value: _onlyMissing,
        onChanged: (v) => setState(() => _onlyMissing = v ?? false),
      ),
      for (final member in members)
        _MemberTile(
          member: member,
          link: settings.linkFor(member.personId),
          onTap: _busy ? null : () => _editLink(member),
        ),
      for (final link in orphanLinks)
        _MemberTile(
          member: IntegrationTeamMember(
            personId: link.personId,
            name: link.personName ?? link.externalName,
            roles: const {},
          ),
          link: link,
          onTap: _busy
              ? null
              : () => _editLink(
                  IntegrationTeamMember(
                    personId: link.personId,
                    name: link.personName ?? link.externalName,
                    roles: const {},
                  ),
                ),
        ),
    ];
  }
}

String lagetSeRoleLabel(String role) => role == 'leader' ? 'Ledare' : 'Spelare';

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member, required this.link, this.onTap});
  final IntegrationTeamMember member;
  final ExternalMemberLink? link;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final link = this.link;
    final theme = Theme.of(context);
    return ListTile(
      key: ValueKey('laget-se-member-${member.personId}'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        link == null ? Icons.link_off : Icons.link,
        color: link == null ? theme.colorScheme.error : null,
      ),
      title: Text(member.name),
      subtitle: Text(
        link == null
            ? 'Saknar laget.se-koppling'
            : '${link.externalName} · ${lagetSeRoleLabel(link.externalRole)} · ID ${link.externalId}',
      ),
      trailing: const Icon(Icons.edit_outlined),
      onTap: onTap,
    );
  }
}

class _LinkDraft {
  const _LinkDraft({
    this.externalId = '',
    this.externalName = '',
    this.externalRole = 'player',
    this.delete = false,
  });
  final String externalId, externalName, externalRole;
  final bool delete;
}

class _MemberLinkDialog extends StatefulWidget {
  const _MemberLinkDialog({required this.member, this.existing});
  final IntegrationTeamMember member;
  final ExternalMemberLink? existing;
  @override
  State<_MemberLinkDialog> createState() => _MemberLinkDialogState();
}

class _MemberLinkDialogState extends State<_MemberLinkDialog> {
  late final _id = TextEditingController(text: widget.existing?.externalId);
  late final _name = TextEditingController(
    text: widget.existing?.externalName ?? widget.member.name,
  );
  late String _role =
      widget.existing?.externalRole ??
      (widget.member.roles.contains('leader') &&
              !widget.member.roles.contains('player')
          ? 'leader'
          : 'player');
  String? _idError, _nameError;

  @override
  void dispose() {
    _id.dispose();
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final id = _id.text.trim();
    final name = _name.text.trim();
    setState(() {
      _idError = isLagetSeId(id)
          ? null
          : 'Ange personens laget.se-ID (siffror).';
      _nameError = name.isEmpty ? 'Ange namnet som det står i laget.se.' : null;
    });
    if (_idError != null || _nameError != null) return;
    Navigator.of(
      context,
    ).pop(_LinkDraft(externalId: id, externalName: name, externalRole: _role));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('laget.se-koppling · ${widget.member.name}'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('laget-se-member-id'),
            controller: _id,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'laget.se-ID',
              errorText: _idError,
            ),
          ),
          TextField(
            key: const Key('laget-se-member-name'),
            controller: _name,
            decoration: InputDecoration(
              labelText: 'Namn i laget.se',
              errorText: _nameError,
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'player', label: Text('Spelare')),
              ButtonSegment(value: 'leader', label: Text('Ledare')),
            ],
            selected: {_role},
            onSelectionChanged: (value) => setState(() => _role = value.first),
          ),
        ],
      ),
    ),
    actions: [
      if (widget.existing != null)
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(const _LinkDraft(delete: true)),
          child: const Text('Ta bort koppling'),
        ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Avbryt'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Spara')),
    ],
  );
}
