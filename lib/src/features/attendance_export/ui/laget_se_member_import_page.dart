import 'package:flutter/material.dart';
import 'package:teamzone_app/src/features/attendance_export/export_models.dart';
import 'package:teamzone_app/src/features/attendance_export/export_services.dart';
import 'package:teamzone_app/src/features/attendance_export/laget_se/laget_se_adapter.dart';
import 'package:teamzone_app/src/features/attendance_export/laget_se/laget_se_member_import.dart';

String _roleLabel(String role) => role == 'leader' ? 'Ledare' : 'Spelare';
String _describe(LagetSeMember member) =>
    '${member.name} · ${_roleLabel(member.role)} · ID ${member.id}';

/// Compares an imported laget.se member list with the team and lets the
/// administrator approve each link. Nothing is saved without approval.
/// Pops with the updated settings when something was saved.
class LagetSeMemberImportPage extends StatefulWidget {
  const LagetSeMemberImportPage({
    required this.settings,
    required this.file,
    required this.services,
    super.key,
  });
  final TeamIntegrationSettings settings;
  final LagetSeMemberFile file;
  final AttendanceExportServices services;

  @override
  State<LagetSeMemberImportPage> createState() =>
      _LagetSeMemberImportPageState();
}

class _LagetSeMemberImportPageState extends State<LagetSeMemberImportPage> {
  late final MemberImportPlan _plan = buildMemberImportPlan(
    settings: widget.settings,
    file: widget.file,
  );

  /// person id -> chosen laget.se person (null = no link).
  late final Map<String, LagetSeMember?> _choices = {
    for (final proposal in _plan.proposals)
      if (proposal.kind == MemberProposalKind.certain ||
          proposal.kind == MemberProposalKind.update ||
          proposal.needsDecision)
        proposal.member.personId: proposal.suggested,
  };
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    TeamIntegrationSettings? latest;
    var saved = 0;
    final failed = <String>[];
    for (final proposal in _plan.proposals) {
      final choice = _choices[proposal.member.personId];
      if (choice == null) continue;
      try {
        latest = await widget.services.saveMemberLink(
          teamId: widget.settings.teamId,
          provider: lagetSeProvider,
          personId: proposal.member.personId,
          externalId: choice.id,
          externalName: choice.name,
          externalRole: choice.role,
          expectedRevision: proposal.existing?.revision ?? 0,
        );
        saved++;
      } catch (_) {
        failed.add(proposal.member.name);
      }
    }
    // The file also tells which laget.se team it came from; the sync agent
    // needs that name, so save it when the team has none yet.
    final slug = widget.file.teamSlug;
    if (widget.settings.externalTeamRef == null &&
        RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(slug)) {
      try {
        final current =
            latest ??
            await widget.services.getTeamIntegration(
              teamId: widget.settings.teamId,
              provider: lagetSeProvider,
            );
        latest = await widget.services.setTeamIntegration(
          teamId: widget.settings.teamId,
          provider: lagetSeProvider,
          enabled: current.enabled,
          externalTeamRef: slug,
          expectedRevision: current.revision,
        );
      } catch (_) {
        failed.add('lagets laget.se-adress');
      }
    }
    if (!mounted) return;
    if (failed.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$saved kopplingar sparade.')));
      Navigator.of(context).pop(latest);
      return;
    }
    setState(() {
      _busy = false;
      _error =
          '$saved kopplingar sparades. Kunde inte spara: ${failed.join(', ')}. '
          'Läs in inställningarna igen och kontrollera dem.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final conflicts = conflictingChoices(_choices);
    final selected = _choices.values.whereType<LagetSeMember>().length;
    final certain = _plan.ofKind(MemberProposalKind.certain).toList();
    final updates = _plan.ofKind(MemberProposalKind.update).toList();
    final decide = _plan.proposals.where((p) => p.needsDecision).toList();
    final noMatch = _plan.ofKind(MemberProposalKind.noMatch).toList();
    final notInFile = _plan.ofKind(MemberProposalKind.linkedNotInFile).toList();
    final unchanged = _plan.ofKind(MemberProposalKind.unchanged).length;

    Widget heading(String text, [String? help]) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: theme.textTheme.titleMedium),
          if (help != null) Text(help, style: theme.textTheme.bodySmall),
        ],
      ),
    );

    Widget approve(MemberProposal proposal, String subtitle) {
      final suggested = proposal.suggested!;
      return CheckboxListTile(
        key: ValueKey('import-approve-${proposal.member.personId}'),
        contentPadding: EdgeInsets.zero,
        title: Text(proposal.member.name),
        subtitle: Text(subtitle),
        value: _choices[proposal.member.personId] != null,
        onChanged: _busy
            ? null
            : (value) => setState(
                () => _choices[proposal.member.personId] = value == true
                    ? suggested
                    : null,
              ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Importera medlemslista')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '${widget.file.members.length} personer från laget.se'
            '${widget.file.teamSlug.isEmpty ? '' : ' (${widget.file.teamSlug})'}. '
            'Inget sparas förrän du godkänner. Förslagen bygger på namn; '
            'exporten använder sedan bara laget.se-ID.',
          ),
          if (unchanged > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('$unchanged kopplingar stämmer redan.'),
            ),
          if (certain.isNotEmpty) ...[
            heading(
              'Säkra förslag (${certain.length})',
              'Samma namn hos exakt en person i både laget.se och Teamzone.',
            ),
            for (final proposal in certain)
              approve(proposal, _describe(proposal.suggested!)),
          ],
          if (updates.isNotEmpty) ...[
            heading(
              'Ändrade uppgifter i laget.se (${updates.length})',
              'Samma laget.se-ID, men namn eller roll har ändrats.',
            ),
            for (final proposal in updates)
              approve(
                proposal,
                '${proposal.existing!.externalName} · '
                '${_roleLabel(proposal.existing!.externalRole)} → '
                '${_describe(proposal.suggested!)}',
              ),
          ],
          if (decide.isNotEmpty) ...[
            heading(
              'Välj själv (${decide.length})',
              'Flera möjliga personer eller bara liknande namn.',
            ),
            for (final proposal in decide)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: DropdownButtonFormField<LagetSeMember?>(
                  key: ValueKey('import-choose-${proposal.member.personId}'),
                  isExpanded: true,
                  initialValue: _choices[proposal.member.personId],
                  decoration: InputDecoration(
                    labelText: proposal.member.name,
                    helperText: proposal.kind == MemberProposalKind.ambiguous
                        ? 'Samma namn finns flera gånger'
                        : 'Liknande namn',
                  ),
                  items: [
                    const DropdownMenuItem<LagetSeMember?>(
                      value: null,
                      child: Text('Koppla inte'),
                    ),
                    for (final candidate in proposal.candidates)
                      DropdownMenuItem<LagetSeMember?>(
                        value: candidate,
                        child: Text(
                          _describe(candidate),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(
                          () => _choices[proposal.member.personId] = value,
                        ),
                ),
              ),
          ],
          if (noMatch.isNotEmpty) ...[
            heading(
              'Ingen träff i laget.se (${noMatch.length})',
              'Koppla dem manuellt i listan om de finns under ett annat namn.',
            ),
            Text(noMatch.map((p) => p.member.name).join(', ')),
          ],
          if (_plan.unmatchedExternal.isNotEmpty) ...[
            heading(
              'Finns i laget.se men inte i Teamzone-truppen '
              '(${_plan.unmatchedExternal.length})',
            ),
            Text(
              _plan.unmatchedExternal
                  .map((m) => '${m.name} (${_roleLabel(m.role).toLowerCase()})')
                  .join(', '),
            ),
          ],
          if (notInFile.isNotEmpty) ...[
            heading(
              'Kopplade men saknas i filen (${notInFile.length})',
              'Kopplingen ändras inte. Ta bort den manuellt om den är fel.',
            ),
            Text(notInFile.map((p) => p.member.name).join(', ')),
          ],
          if (conflicts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                'Samma laget.se-person är vald för flera i Teamzone '
                '(ID ${conflicts.join(', ')}). Välj om innan du sparar.',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: const Text('Avbryt'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const Key('import-save'),
                onPressed: _busy || selected == 0 || conflicts.isNotEmpty
                    ? null
                    : _save,
                child: Text(_busy ? 'Sparar…' : 'Spara $selected kopplingar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
