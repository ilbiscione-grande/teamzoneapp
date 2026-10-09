import 'dart:async';

import 'package:flutter/material.dart';
import 'package:teamzone_app/src/features/attendance_export/export_basis.dart';
import 'package:teamzone_app/src/features/attendance_export/export_models.dart';
import 'package:teamzone_app/src/features/attendance_export/export_runner.dart';
import 'package:teamzone_app/src/features/attendance_export/export_services.dart';
import 'package:teamzone_app/src/features/attendance_export/laget_se/laget_se_adapter.dart';
import 'package:teamzone_app/src/features/calendar/calendar_services.dart';
import 'package:teamzone_app/src/shared/widgets/app_states.dart';

/// Exportera närvaro → laget.se for one ended event and one team.
class AttendanceExportPage extends StatefulWidget {
  const AttendanceExportPage({
    required this.eventId,
    required this.teamId,
    required this.calendar,
    required this.services,
    this.saver = const FilePickerExportFileSaver(),
    super.key,
  });
  final String eventId, teamId;
  final CalendarServices calendar;
  final AttendanceExportServices services;
  final ExportFileSaver saver;

  @override
  State<AttendanceExportPage> createState() => _AttendanceExportPageState();
}

class _AttendanceExportPageState extends State<AttendanceExportPage> {
  ExportContext? _context;
  AttendanceExportBasis? _basis;
  final _activityInput = TextEditingController();
  final _excluded = <String>{};
  bool _confirmed = false, _busy = false;
  String? _loadError, _activityError, _message;
  bool _messageIsError = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _activityInput.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final context = await widget.services.getExportContext(
        eventId: widget.eventId,
        teamId: widget.teamId,
        provider: lagetSeProvider,
      );
      final basis = await loadAttendanceExportBasis(
        calendar: widget.calendar,
        eventId: widget.eventId,
        teamId: widget.teamId,
        teamRoster: context.teamRoster,
      );
      if (!mounted) return;
      setState(() {
        _context = context;
        _basis = basis;
        _activityInput.text = context.activityLink?.externalActivityId ?? '';
      });
      _schedulePoll();
    } catch (_) {
      if (mounted) {
        setState(() => _loadError = 'Exportunderlaget kunde inte laddas.');
      }
    }
  }

  /// While the agent works on a job, refresh its status every few seconds.
  void _schedulePoll() {
    _poll?.cancel();
    if (_context?.latestSyncJob?.isRunning != true) return;
    _poll = Timer(const Duration(seconds: 4), _refreshContext);
  }

  Future<void> _refreshContext() async {
    try {
      final context = await widget.services.getExportContext(
        eventId: widget.eventId,
        teamId: widget.teamId,
        provider: lagetSeProvider,
      );
      if (!mounted) return;
      setState(() => _context = context);
    } catch (_) {
      // Keep the last known state; the next poll retries.
    }
    if (mounted) _schedulePoll();
  }

  Future<void> _syncAction(
    Future<void> Function() action,
    String failure,
  ) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
      await _refreshContext();
    } catch (error) {
      if (mounted) {
        setState(() {
          _messageIsError = true;
          _message = switch (attendanceExportErrorCode(error)) {
            'missing_team_ref' =>
              'Ange lagets namn i laget.se-adressen under Integrationer → laget.se.',
            'sync_in_progress' =>
              'Synkagenten arbetar redan med den här aktiviteten.',
            'preview_changed' =>
              'Förhandsgranskningen har ändrats. Kontrollera den igen.',
            'unknown_member' =>
              'Någon i underlaget saknar giltig laget.se-koppling.',
            _ => failure,
          };
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendToLaget(LagetSeExportResult result) => _syncAction(
    () => widget.services.requestSync(
      eventId: widget.eventId,
      teamId: widget.teamId,
      provider: lagetSeProvider,
      payload: result.file!.toJson(),
      summary: result.summary.toJson(),
      confirmedComplete: _confirmed,
    ),
    'Synken kunde inte startas. Försök igen.',
  );

  /// Links the chosen laget.se activity (reused by later exports) and sends
  /// the sync again, now straight to the preview.
  Future<void> _chooseCandidate(SyncActivityCandidate candidate) =>
      _syncAction(() async {
        final context = await widget.services.setActivityLink(
          eventId: widget.eventId,
          teamId: widget.teamId,
          provider: lagetSeProvider,
          externalActivityId: candidate.id,
          expectedRevision: _context!.activityLink?.revision ?? 0,
        );
        if (!mounted) return;
        setState(() {
          _context = context;
          _activityInput.text = candidate.id;
        });
        final result = generateLagetSeExport(
          basis: _basis!,
          context: context,
          excludedPersonIds: _excluded,
          confirmedComplete: _confirmed,
        );
        final file = result.file;
        if (file == null) {
          throw StateError('Underlaget är inte komplett längre.');
        }
        await widget.services.requestSync(
          eventId: widget.eventId,
          teamId: widget.teamId,
          provider: lagetSeProvider,
          payload: file.toJson(),
          summary: result.summary.toJson(),
          confirmedComplete: _confirmed,
        );
      }, 'Aktiviteten kunde inte kopplas. Försök igen.');

  Future<void> _approve(SyncJob job) => _syncAction(
    () => widget.services.approveSync(
      jobId: job.id,
      previewSha256: job.previewSha256!,
    ),
    'Godkännandet kunde inte sparas. Försök igen.',
  );

  Future<void> _cancelSync(SyncJob job) => _syncAction(
    () => widget.services.cancelSync(job.id),
    'Synken kunde inte avbrytas.',
  );

  Future<void> _saveActivityLink() async {
    final raw = _activityInput.text.trim();
    final id = raw.isEmpty ? null : parseLagetSeActivityId(raw);
    if (raw.isNotEmpty && id == null) {
      setState(
        () => _activityError =
            'Ange aktivitetens ID (siffror) eller hela länken från laget.se.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _activityError = null;
    });
    try {
      final context = await widget.services.setActivityLink(
        eventId: widget.eventId,
        teamId: widget.teamId,
        provider: lagetSeProvider,
        externalActivityId: id,
        expectedRevision: _context!.activityLink?.revision ?? 0,
      );
      if (!mounted) return;
      setState(() {
        _context = context;
        _activityInput.text = context.activityLink?.externalActivityId ?? '';
        // A changed activity means the earlier confirmation no longer holds.
        _confirmed = false;
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _activityError = switch (attendanceExportErrorCode(error)) {
            'external_activity_taken' =>
              'Den laget.se-aktiviteten är redan kopplad till en annan aktivitet i laget.',
            'revision_conflict' =>
              'Kopplingen har ändrats av någon annan. Läs in sidan igen.',
            _ => 'Kopplingen kunde inte sparas.',
          },
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final outcome =
        await AttendanceExportRunner(
          services: widget.services,
          saver: widget.saver,
        ).exportToLagetSe(
          basis: _basis!,
          context: _context!,
          excludedPersonIds: _excluded,
          confirmedComplete: _confirmed,
        );
    if (!mounted) return;
    final (text, isError) = switch (outcome.kind) {
      ExportOutcomeKind.blocked => (
        outcome.result.errors.map((e) => e.message).join('\n'),
        true,
      ),
      ExportOutcomeKind.cancelled => ('Ingen fil sparades.', false),
      ExportOutcomeKind.failed => (
        'Export misslyckades: filen kunde inte sparas. Ingen fil skapades.',
        true,
      ),
      ExportOutcomeKind.fileCreated => (
        'Exportfil skapad: ${outcome.fileName}. Närvaron är inte överförd '
            'till laget.se förrän synkverktyget har kört och verifierat filen.',
        false,
      ),
      ExportOutcomeKind.fileCreatedNotLogged => (
        'Exportfil skapad: ${outcome.fileName}, men exporten kunde inte '
            'loggas i Teamzone.',
        true,
      ),
    };
    setState(() {
      _busy = false;
      _message = text;
      _messageIsError = isError;
    });
    if (outcome.kind != ExportOutcomeKind.cancelled) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final exportContext = _context;
    final basis = _basis;
    return Scaffold(
      appBar: AppBar(title: const Text('Exportera närvaro → laget.se')),
      body: exportContext == null || basis == null
          ? (_loadError == null
                ? const AppLoadingIndicator(label: 'Laddar…')
                : Center(
                    child: AppStateCard(
                      icon: Icons.sync_problem,
                      title: 'Kunde inte ladda',
                      message: _loadError!,
                      action: FilledButton(
                        onPressed: _load,
                        child: const Text('Försök igen'),
                      ),
                    ),
                  ))
          : _body(context, exportContext, basis),
    );
  }

  Widget _body(
    BuildContext context,
    ExportContext exportContext,
    AttendanceExportBasis basis,
  ) {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    final result = generateLagetSeExport(
      basis: basis,
      context: exportContext,
      excludedPersonIds: _excluded,
      confirmedComplete: _confirmed,
    );
    final summary = result.summary;
    // Without an activity link, a direct sync may still be sent: the agent
    // locates the activity. A file always needs the link.
    final locate =
        exportContext.activityLink == null &&
        exportContext.externalTeamRef != null;
    final syncResult = locate
        ? generateLagetSeExport(
            basis: basis,
            context: exportContext,
            excludedPersonIds: _excluded,
            confirmedComplete: _confirmed,
            requireActivity: false,
          )
        : result;
    // Why "Skicka till laget.se" is disabled, in the order to fix them.
    final codes = {for (final issue in syncResult.errors) issue.code};
    final blockers = [
      if (!exportContext.enabled) 'aktivera laget.se under Integrationer',
      if (exportContext.externalTeamRef == null)
        'ange lagets namn i laget.se-adressen under Integrationer',
      if (codes.contains('event_not_ended') ||
          codes.contains('event_not_in_team'))
        'aktiviteten måste vara avslutad och höra till laget',
      if (codes.contains('missing_activity_id') ||
          codes.contains('invalid_activity_id') ||
          codes.contains('activity_link_wrong_team'))
        'koppla aktiviteten i laget.se (fältet ovan)',
      if (codes.contains('missing_member_links'))
        'koppla eller välj bort personer utan laget.se-ID',
      if (codes.any(
        (code) => const {
          'conflicting_links',
          'duplicate_external_id',
          'link_wrong_team',
          'invalid_member_id',
          'missing_member_name',
          'invalid_member_role',
          'duplicate_participant',
          'unknown_attendance_included',
          'contract_violation',
        }.contains(code),
      ))
        'rätta felen i rött ovan',
      if (!_confirmed) 'kryssa i att närvaron är färdigregistrerad',
      if (exportContext.latestSyncJob?.isRunning == true)
        'vänta, en synk pågår redan',
    ];
    final errors = syncResult.errors
        .where((issue) => issue.code != 'not_confirmed')
        .toList();
    final start = basis.startsAt.toLocal();
    final last = exportContext.exports.firstOrNull;
    final lastFile = exportContext.lastFileCreated;
    final unchanged =
        result.file != null &&
        lastFile != null &&
        lastFile.payloadSha256 == result.file!.sha256Hex();
    String date(DateTime value) =>
        '${localizations.formatMediumDate(value.toLocal())} '
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(value.toLocal()), alwaysUse24HourFormat: true)}';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(basis.eventTitle, style: theme.textTheme.titleLarge),
        Text('${exportContext.teamName} · ${date(start)}'),
        const SizedBox(height: 8),
        Text(switch (exportContext.state) {
          ExportState.notExported => 'Status: Inte exporterad',
          ExportState.fileCreated =>
            'Status: Exportfil skapad ${date(last!.createdAt)} (ej bekräftad i laget.se)',
          ExportState.failed =>
            'Status: Export misslyckades ${date(last!.createdAt)}',
          ExportState.verified =>
            'Status: Verifierad i laget.se ${date(last!.createdAt)}',
          ExportState.rejected =>
            'Status: Avvisad vid överföring ${date(last!.createdAt)}',
        }, key: const Key('export-status')),
        const SizedBox(height: 16),
        Text('Aktivitet i laget.se', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: const Key('laget-se-activity-input'),
                controller: _activityInput,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: 'Aktivitets-ID eller länk',
                  hintText: 'https://admin.laget.se/…/Calendar/Edit/30960339',
                  errorText: _activityError,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton(
                onPressed: _busy ? null : _saveActivityLink,
                child: const Text('Spara'),
              ),
            ),
          ],
        ),
        if (exportContext.activityLink != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Kopplad till laget.se-aktivitet '
              '${exportContext.activityLink!.externalActivityId}',
            ),
          )
        else if (exportContext.externalTeamRef != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Inte kopplad än. Vid "Skicka till laget.se" letar synkagenten '
              'upp aktiviteten i lagets kalender (samma datum och starttid). '
              'För att skapa en fil behöver länken anges här.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 16),
        Text('Sammanställning', style: theme.textTheme.titleMedium),
        _countRow('Närvarande spelare', summary.presentPlayers),
        _countRow('Frånvarande spelare', summary.absentPlayers),
        _countRow('Närvarande ledare', summary.presentLeaders),
        _countRow('Frånvarande ledare', summary.absentLeaders),
        _countRow('Okänd närvaro (tas inte med)', summary.unknown),
        _countRow('Saknar laget.se-koppling', summary.missingLinks),
        if (summary.excluded > 0)
          _countRow('Tas inte med (ditt val)', summary.excluded),
        if (result.selection.otherTeam.isNotEmpty)
          _countRow(
            'Tillhör annat lag (påverkas inte)',
            result.selection.otherTeam.length,
          ),
        if (result.selection.unknown.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Ingen registrerad närvaro: '
            '${result.selection.unknown.map((c) => c.name).join(', ')}',
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (result.selection.missingLinks.isNotEmpty ||
            result.selection.excluded.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Saknar koppling', style: theme.textTheme.titleMedium),
          const Text(
            'Koppla personerna under Inställningar → Lag → Integrationer → '
            'laget.se, eller välj uttryckligen att inte ta med dem.',
          ),
          for (final candidate in [
            for (final entry in result.selection.missingLinks) entry.candidate,
            ...result.selection.excluded,
          ])
            CheckboxListTile(
              key: ValueKey('export-exclude-${candidate.personId}'),
              contentPadding: EdgeInsets.zero,
              title: Text(candidate.name),
              subtitle: Text(
                candidate.membership == ExportMembership.team
                    ? 'Saknar laget.se-ID'
                    : 'Gäst · saknar laget.se-ID',
              ),
              secondary: const Icon(Icons.link_off),
              controlAffinity: ListTileControlAffinity.trailing,
              value: _excluded.contains(candidate.personId),
              onChanged: _busy
                  ? null
                  : (value) => setState(() {
                      value == true
                          ? _excluded.add(candidate.personId)
                          : _excluded.remove(candidate.personId);
                    }),
            ),
          const Text('Bockade personer tas inte med i filen.'),
        ],
        for (final issue in errors)
          _issue(context, issue.message, Icons.error_outline, true),
        for (final issue in result.warnings)
          _issue(context, issue.message, Icons.warning_amber_outlined, false),
        if (unchanged)
          _issue(
            context,
            'Underlaget är oförändrat sedan exportfilen skapades '
            '${date(lastFile.createdAt)}.',
            Icons.info_outline,
            false,
          ),
        const SizedBox(height: 8),
        CheckboxListTile(
          key: const Key('export-confirm-complete'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Närvaron är färdigregistrerad'),
          subtitle: const Text(
            'Jag har kontrollerat att underlaget är komplett.',
          ),
          value: _confirmed,
          onChanged: _busy
              ? null
              : (v) => setState(() => _confirmed = v ?? false),
        ),
        if (_message != null)
          _issue(
            context,
            _message!,
            _messageIsError ? Icons.error_outline : Icons.check_circle_outline,
            _messageIsError,
          ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Avbryt'),
            ),
            OutlinedButton.icon(
              key: const Key('export-generate'),
              onPressed: _busy || result.file == null ? null : _export,
              icon: const Icon(Icons.download_outlined),
              label: const Text('Skapa exportfil'),
            ),
            FilledButton.icon(
              key: const Key('export-sync'),
              onPressed: _busy || blockers.isNotEmpty
                  ? null
                  : () => _sendToLaget(syncResult),
              icon: const Icon(Icons.sync),
              label: const Text('Skicka till laget.se'),
            ),
          ],
        ),
        if (blockers.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Innan du kan skicka: ${blockers.join(' · ')}',
              key: const Key('export-blockers'),
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ..._syncSection(context, exportContext),
      ],
    );
  }

  String _statusLabel(String status) =>
      status == 'present' ? '✓' : (status == 'absent' ? '?' : 'okänd');

  /// Direct sync through the sync agent on the administrator's computer.
  List<Widget> _syncSection(BuildContext context, ExportContext exportContext) {
    final theme = Theme.of(context);
    final job = exportContext.latestSyncJob;
    final agent = exportContext.agent;
    final now = DateTime.now();
    final widgets = <Widget>[
      const SizedBox(height: 24),
      Text('Synka direkt till laget.se', style: theme.textTheme.titleMedium),
      const Text(
        'Synkagenten på din dator läser aktiviteten i laget.se och visar '
        'vad som ändras. Inget skrivs förrän du godkänner.',
      ),
    ];
    void info(String text, IconData icon, {bool error = false}) =>
        widgets.add(_issue(context, text, icon, error));
    if (exportContext.externalTeamRef == null) {
      info(
        'Ange lagets namn i laget.se-adressen under Integrationer → laget.se '
        '(t.ex. EksjoFotbollJ18) för att kunna synka direkt.',
        Icons.info_outline,
      );
    }
    if (agent == null) {
      info(
        'Synkagenten har inte startats ännu. Starta "laget.se-synk" på datorn '
        'och logga in med ditt Teamzone-konto.',
        Icons.computer,
      );
    } else if (!agent.isOnline(now)) {
      info(
        'Synkagenten på datorn är inte igång. Jobb väntar tills den startas.',
        Icons.computer,
        error: job?.isRunning == true,
      );
    } else if (agent.lagetSessionOk == false) {
      info(
        'Synkagenten behöver logga in på laget.se igen. Öppna "laget.se-synk" på datorn.',
        Icons.lock_outline,
        error: true,
      );
    } else {
      info('Synkagenten är igång.', Icons.check_circle_outline);
    }
    if (job == null) return widgets;
    final message = job.message;
    final suffix = message == null ? '' : ' $message';
    switch (job.state) {
      case SyncJobState.queued when exportContext.activityLink == null:
      case SyncJobState.locating:
        widgets.add(const SizedBox(height: 8));
        widgets.add(const LinearProgressIndicator());
        info(
          'Synkagenten letar upp aktiviteten i laget.se-kalendern '
          '(samma datum och starttid)…$suffix',
          Icons.search,
        );
      case SyncJobState.needsActivity:
        info(
          message ?? 'Hittade ingen entydig aktivitet i laget.se.',
          Icons.help_outline,
          error: true,
        );
        if (job.candidates.isNotEmpty) {
          widgets.add(const SizedBox(height: 4));
          widgets.add(const Text('Välj rätt aktivitet i laget.se:'));
          for (final candidate in job.candidates) {
            widgets.add(
              ListTile(
                key: ValueKey('sync-candidate-${candidate.id}'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: Text(
                  candidate.label.isEmpty ? 'Aktivitet' : candidate.label,
                ),
                subtitle: Text('${candidate.date} · ID ${candidate.id}'),
                trailing: OutlinedButton(
                  onPressed: _busy ? null : () => _chooseCandidate(candidate),
                  child: const Text('Välj'),
                ),
              ),
            );
          }
        } else {
          info(
            'Klistra in aktivitetens länk från laget.se i fältet ovan och skicka igen.',
            Icons.link,
          );
        }
      case SyncJobState.queued:
      case SyncJobState.previewing:
        widgets.add(const SizedBox(height: 8));
        widgets.add(const LinearProgressIndicator());
        info(
          'Synkagenten läser aktiviteten i laget.se…$suffix',
          Icons.hourglass_top,
        );
      case SyncJobState.awaitingApproval:
        final preview = job.preview;
        if (message != null) info(message, Icons.info_outline);
        if (preview != null) {
          final title = preview.pageTitle == null
              ? ''
              : ' (${preview.pageTitle})';
          widgets.add(const SizedBox(height: 8));
          widgets.add(
            Text(
              preview.changes.isEmpty
                  ? 'Inga ändringar behövs.'
                  : '${preview.changes.length} ändringar i laget.se$title:',
              key: const Key('sync-preview-heading'),
            ),
          );
          for (final change in preview.changes) {
            final role = change.role == 'leader' ? 'ledare' : 'spelare';
            widgets.add(
              Text(
                '${change.name} ($role): '
                '${_statusLabel(change.from)} → ${_statusLabel(change.to)}',
              ),
            );
          }
          widgets.add(Text('Redan rätt: ${preview.unchanged}'));
        }
        widgets.add(const SizedBox(height: 8));
        widgets.add(
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: _busy ? null : () => _cancelSync(job),
                child: const Text('Avbryt synk'),
              ),
              FilledButton(
                key: const Key('sync-approve'),
                onPressed: _busy || job.previewSha256 == null
                    ? null
                    : () => _approve(job),
                child: const Text('Godkänn och genomför'),
              ),
            ],
          ),
        );
      case SyncJobState.approved:
      case SyncJobState.applying:
        widgets.add(const SizedBox(height: 8));
        widgets.add(const LinearProgressIndicator());
        info('Genomförs i laget.se och kontrolleras…$suffix', Icons.sync);
      case SyncJobState.verified:
        info('Verifierad i laget.se.$suffix', Icons.verified_outlined);
      case SyncJobState.failed:
        info(
          'Synken misslyckades: ${message ?? 'okänt fel'} Inget mer ändrades.',
          Icons.error_outline,
          error: true,
        );
        for (final problem in job.preview?.problems ?? const <String>[]) {
          info(problem, Icons.warning_amber_outlined, error: true);
        }
      case SyncJobState.cancelled:
        if (message != null) info(message, Icons.info_outline);
    }
    return widgets;
  }

  Widget _countRow(String label, int value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text('$value'),
      ],
    ),
  );

  Widget _issue(BuildContext context, String text, IconData icon, bool error) {
    final color = error ? Theme.of(context).colorScheme.error : null;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: color)),
          ),
        ],
      ),
    );
  }
}
