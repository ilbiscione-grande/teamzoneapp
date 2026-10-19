import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:teamzone_app/src/core/observability/app_errors.dart';
import 'package:teamzone_app/src/features/calendar/referee_services.dart';

/// REF-02 phase 2: reports, fees and pay for föreningsdomare. A report is
/// made for each confirmed club referee once the match has ended; the
/// domaransvarig can send a control question to the team's leaders and
/// approves; the one who pays (Domarersättning) makes payout lists,
/// exports them and marks them paid.

String _date(MaterialLocalizations material, DateTime value) =>
    material.formatShortDate(value.toLocal());

void _snack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// Runs an action with the error in Swedish as a snackbar; true when done.
Future<bool> _attempt(
  BuildContext context,
  String where,
  Future<void> Function() action, [
  String? done,
]) async {
  try {
    await action();
    if (context.mounted && done != null) _snack(context, done);
    return true;
  } catch (error) {
    AppErrors.caught(where, error);
    if (context.mounted) _snack(context, refereeErrorText(error));
    return false;
  }
}

Future<int?> _askAmount(
  BuildContext context,
  String title,
  int? initial,
) async {
  var text = initial?.toString() ?? '';
  final value = await showDialog<int>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextFormField(
        key: const ValueKey('referee-amount-field'),
        initialValue: text,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(suffixText: 'kr'),
        onChanged: (value) => text = value,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Avbryt'),
        ),
        FilledButton(
          key: const ValueKey('referee-amount-save'),
          onPressed: () {
            final amount = int.tryParse(text.trim());
            if (amount == null || amount > 100000) return;
            Navigator.pop(dialogContext, amount);
          },
          child: const Text('Spara'),
        ),
      ],
    ),
  );
  return value;
}

Future<String?> _askText(
  BuildContext context, {
  required String title,
  required String label,
  String? initial,
  String action = 'Spara',
}) {
  var text = initial ?? '';
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextFormField(
        key: const ValueKey('referee-text-field'),
        initialValue: text,
        autofocus: true,
        maxLength: 500,
        maxLines: 3,
        minLines: 1,
        decoration: InputDecoration(labelText: label),
        onChanged: (value) => text = value,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Avbryt'),
        ),
        FilledButton(
          key: const ValueKey('referee-text-save'),
          onPressed: () => Navigator.pop(dialogContext, text.trim()),
          child: Text(action),
        ),
      ],
    ),
  );
}

String _controlText(ClubRefereeReport report) => switch (report.controlState) {
  'asked' => 'Kontrollfråga skickad till lagets ledare',
  'confirmed' =>
    'Ledaren bekräftar${report.controlNote == null ? '' : ': ${report.controlNote}'}',
  'denied' =>
    'Ledaren säger nej${report.controlNote == null ? '' : ': ${report.controlNote}'}',
  _ => '',
};

/// The domaransvarig's reports: approve (many at once) or reject, change
/// an amount and send a control question to the team's leaders.
class ClubRefereeReportsView extends StatefulWidget {
  const ClubRefereeReportsView({
    super.key,
    required this.services,
    required this.clubId,
  });
  final RefereeServices services;
  final String clubId;

  @override
  State<ClubRefereeReportsView> createState() => _ClubRefereeReportsViewState();
}

class _ClubRefereeReportsViewState extends State<ClubRefereeReportsView> {
  String _state = 'pending';
  late Future<ClubRefereeReports> _reports = _load();
  final _selected = <String>{};
  bool _busy = false;

  Future<ClubRefereeReports> _load() =>
      widget.services.reports(widget.clubId, state: _state);

  void _reload() {
    final next = _load();
    setState(() {
      _reports = next;
      _selected.clear();
    });
  }

  Future<void> _run(Future<void> Function() action, [String? done]) async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await _attempt(
      context,
      'club_referee_pay.reports',
      action,
      done,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) _reload();
  }

  Future<void> _decide(List<String> ids, bool approve) async {
    String? reason;
    if (!approve) {
      reason = await _askText(
        context,
        title: 'Godkänn inte',
        label: 'Anledning (syns för domaren)',
        action: 'Godkänn inte',
      );
      if (reason == null || !mounted) return;
    }
    await _run(
      () => widget.services.decideReports(
        widget.clubId,
        ids,
        approve,
        reason: reason,
      ),
      approve
          ? (ids.length == 1
                ? 'Uppdraget är godkänt.'
                : '${ids.length} uppdrag är godkända.')
          : 'Uppdraget är inte godkänt.',
    );
  }

  Future<void> _amount(ClubRefereeReport report) async {
    final amount = await _askAmount(context, 'Belopp', report.amount);
    if (amount == null || !mounted) return;
    await _run(() => widget.services.setReportAmount(report.id, amount));
  }

  @override
  Widget build(BuildContext context) {
    const filters = ['pending', 'approved', 'rejected', 'paid'];
    return FutureBuilder<ClubRefereeReports>(
      future: _reports,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final selectable = [
          for (final report in data?.reports ?? const <ClubRefereeReport>[])
            if (report.open && report.state != 'approved') report.id,
        ];
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final value in filters)
                  ChoiceChip(
                    key: ValueKey('referee-reports-filter-$value'),
                    label: Text(
                      [
                        refereeReportStateLabel(value),
                        if ((data?.counts[value] ?? 0) > 0 && value != 'paid')
                          '(${data!.counts[value]})',
                      ].join(' '),
                    ),
                    selected: _state == value,
                    onSelected: (_) {
                      _state = value;
                      _reload();
                    },
                  ),
              ],
            ),
            if (snapshot.hasError)
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextButton(
                  onPressed: _reload,
                  child: const Text(
                    'Rapporterna kunde inte hämtas. Försök igen.',
                  ),
                ),
              )
            else if (data == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              if (selectable.isNotEmpty && data.canManage)
                Row(
                  children: [
                    Checkbox(
                      key: const ValueKey('referee-reports-select-all'),
                      value: _selected.length == selectable.length
                          ? true
                          : (_selected.isEmpty ? false : null),
                      tristate: true,
                      onChanged: (_) => setState(() {
                        if (_selected.length == selectable.length) {
                          _selected.clear();
                        } else {
                          _selected
                            ..clear()
                            ..addAll(selectable);
                        }
                      }),
                    ),
                    const Expanded(child: Text('Markera alla')),
                    FilledButton(
                      key: const ValueKey('referee-reports-approve-selected'),
                      onPressed: _busy || _selected.isEmpty
                          ? null
                          : () => _decide(_selected.toList(), true),
                      child: Text('Godkänn (${_selected.length})'),
                    ),
                  ],
                ),
              if (data.reports.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _state == 'pending'
                        ? 'Inga uppdrag att godkänna. Rapporter skapas när en match med föreningsdomare är spelad.'
                        : 'Inga uppdrag här.',
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final report in data.reports)
                _reportCard(report, data.canManage),
            ],
          ],
        );
      },
    );
  }

  Widget _reportCard(ClubRefereeReport report, bool canManage) {
    final material = MaterialLocalizations.of(context);
    final theme = Theme.of(context);
    final selectable = canManage && report.open && report.state != 'approved';
    return Card(
      key: ValueKey('referee-report-${report.id}'),
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (selectable)
              Checkbox(
                value: _selected.contains(report.id),
                onChanged: (value) => setState(
                  () => value == true
                      ? _selected.add(report.id)
                      : _selected.remove(report.id),
                ),
              )
            else
              const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${report.name} · ${formatKronor(report.amount)}',
                    style: theme.textTheme.titleSmall,
                  ),
                  Text(report.match.matchup),
                  Text(
                    [
                      _date(material, report.match.startsAt),
                      refereeSlotLabel(report.slot),
                      if (_state != report.state)
                        refereeReportStateLabel(report.state),
                    ].join(' · '),
                    style: theme.textTheme.bodySmall,
                  ),
                  if (report.refereeNote != null)
                    Text(
                      'Domaren: ${report.refereeNote}',
                      style: theme.textTheme.bodySmall,
                    ),
                  if (report.controlState != null)
                    Text(
                      _controlText(report),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: report.controlState == 'denied'
                            ? theme.colorScheme.error
                            : null,
                      ),
                    ),
                  if (report.rejectReason != null && report.state == 'rejected')
                    Text(
                      'Anledning: ${report.rejectReason}',
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            if (canManage && report.open)
              PopupMenuButton<String>(
                key: ValueKey('referee-report-menu-${report.id}'),
                enabled: !_busy,
                onSelected: (value) => switch (value) {
                  'approve' => _decide([report.id], true),
                  'reject' => _decide([report.id], false),
                  'amount' => _amount(report),
                  'control' => _run(
                    () => widget.services.askControl(report.id),
                    'Kontrollfrågan är skickad till lagets ledare.',
                  ),
                  _ => null,
                },
                itemBuilder: (_) => [
                  if (report.state != 'approved')
                    const PopupMenuItem(
                      value: 'approve',
                      child: Text('Godkänn'),
                    ),
                  if (report.state != 'rejected')
                    const PopupMenuItem(
                      value: 'reject',
                      child: Text('Godkänn inte'),
                    ),
                  const PopupMenuItem(
                    value: 'amount',
                    child: Text('Ändra belopp'),
                  ),
                  if (report.state == 'pending')
                    PopupMenuItem(
                      value: 'control',
                      child: Text(
                        report.controlState == null
                            ? 'Skicka kontrollfråga till ledaren'
                            : 'Skicka kontrollfrågan igen',
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Fees: the club's, and a team's own where it differs.
class ClubRefereeFeesSection extends StatefulWidget {
  const ClubRefereeFeesSection({
    super.key,
    required this.services,
    required this.clubId,
  });
  final RefereeServices services;
  final String clubId;

  @override
  State<ClubRefereeFeesSection> createState() => _ClubRefereeFeesSectionState();
}

class _ClubRefereeFeesSectionState extends State<ClubRefereeFeesSection> {
  late Future<ClubRefereeFees> _fees = widget.services.fees(widget.clubId);

  Future<void> _edit(RefereeFee fee, RefereeFee club) async {
    var main = fee.main?.toString() ?? '';
    var assistant = fee.assistant?.toString() ?? '';
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Arvode · ${fee.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const ValueKey('referee-fee-main'),
              initialValue: main,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Huvuddomare',
                suffixText: 'kr',
              ),
              onChanged: (value) => main = value,
            ),
            TextFormField(
              key: const ValueKey('referee-fee-assistant'),
              initialValue: assistant,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Assisterande domare',
                suffixText: 'kr',
              ),
              onChanged: (value) => assistant = value,
            ),
            if (fee.teamId != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Utan eget arvode gäller klubbens.',
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
              ),
          ],
        ),
        actions: [
          if (fee.main != null)
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'remove'),
              child: const Text('Ta bort'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            key: const ValueKey('referee-fee-save'),
            onPressed: () => Navigator.pop(dialogContext, 'save'),
            child: const Text('Spara'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    final mainValue = int.tryParse(main.trim());
    final assistantValue = int.tryParse(assistant.trim()) ?? mainValue;
    if (result == 'save' && mainValue == null) return;
    var changed = 0;
    final ok = await _attempt(context, 'club_referee_pay.fee', () async {
      changed = await widget.services.saveFee(
        widget.clubId,
        fee.teamId,
        result == 'save' ? mainValue : null,
        result == 'save' ? assistantValue : null,
      );
    });
    if (!mounted || !ok) return;
    _snack(
      context,
      changed > 0
          ? 'Arvodet är sparat. $changed uppdrag att godkänna fick det nya beloppet.'
          : 'Arvodet är sparat.',
    );
    setState(() {
      _fees = widget.services.fees(widget.clubId);
    });
  }

  String _label(RefereeFee fee, RefereeFee club) {
    if (fee.main == null) {
      return club.main == null || fee.teamId == null
          ? 'Inget arvode'
          : 'Klubbens arvode';
    }
    return 'Huvuddomare ${formatKronor(fee.main!)} · assisterande ${formatKronor(fee.assistant ?? fee.main!)}';
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ClubRefereeFees>(
    future: _fees,
    builder: (context, snapshot) {
      final fees = snapshot.data;
      if (fees == null) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 32),
          Text('Arvoden', style: Theme.of(context).textTheme.titleMedium),
          const Text(
            'Arvodet fylls i på domarens uppdrag när matchen är spelad. Ett lags eget arvode gäller före klubbens.',
          ),
          for (final fee in [fees.club, ...fees.teams])
            ListTile(
              key: ValueKey('referee-fee-${fee.teamId ?? 'club'}'),
              title: Text(fee.name),
              subtitle: Text(_label(fee, fees.club)),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _edit(fee, fees.club),
            ),
        ],
      );
    },
  );
}

/// Domarersättning: what is ready to pay, the payout lists, and who pays.
class ClubRefereePayoutsView extends StatefulWidget {
  const ClubRefereePayoutsView({
    super.key,
    required this.services,
    required this.clubId,
    this.pickPerson,
  });
  final RefereeServices services;
  final String clubId;

  /// Picks a person in the club (to give Domarersättning).
  final Future<ClubPerson?> Function(String title)? pickPerson;

  @override
  State<ClubRefereePayoutsView> createState() => _ClubRefereePayoutsViewState();
}

class _ClubRefereePayoutsViewState extends State<ClubRefereePayoutsView> {
  late Future<RefereePayouts> _payouts = _load();
  bool _busy = false;

  Future<RefereePayouts> _load() => widget.services.payouts(widget.clubId);

  void _reload() {
    final next = _load();
    setState(() {
      _payouts = next;
    });
  }

  Future<void> _open(String payoutId) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ClubRefereePayoutPage(
          services: widget.services,
          payoutId: payoutId,
        ),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _create() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final through = await showDatePicker(
      context: context,
      helpText: 'Matcher till och med',
      firstDate: DateTime(today.year - 2),
      lastDate: today,
      initialDate: today,
    );
    if (through == null || !mounted) return;
    setState(() => _busy = true);
    String? created;
    await _attempt(context, 'club_referee_pay.create', () async {
      created = await widget.services.createPayout(widget.clubId, through);
    });
    if (!mounted) return;
    setState(() => _busy = false);
    final id = created;
    if (id != null) {
      await _open(id);
    } else {
      _reload();
    }
  }

  Future<void> _payer(String personId, bool enabled, String done) async {
    setState(() => _busy = true);
    await _attempt(
      context,
      'club_referee_pay.payer',
      () => widget.services.setPayer(widget.clubId, personId, enabled),
      done,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final material = MaterialLocalizations.of(context);
    return FutureBuilder<RefereePayouts>(
      future: _payouts,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: _reload,
              child: const Text('Ersättningen kunde inte hämtas. Försök igen.'),
            ),
          );
        }
        final data = snapshot.data;
        if (data == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Card(
              child: ListTile(
                key: const ValueKey('referee-payout-ready'),
                title: Text(
                  data.readyCount == 0
                      ? 'Inga godkända uppdrag att betala ut'
                      : '${data.readyCount} godkända uppdrag · ${formatKronor(data.readyTotal)}',
                ),
                subtitle: const Text(
                  'Uppdragen godkänns av domaransvarig under Rapporter.',
                ),
              ),
            ),
            FilledButton.icon(
              key: const ValueKey('referee-payout-create'),
              onPressed: _busy || data.readyCount == 0 ? null : _create,
              icon: const Icon(Icons.playlist_add_check),
              label: const Text('Skapa utbetalningslista'),
            ),
            const SizedBox(height: 8),
            for (final payout in data.payouts)
              ListTile(
                key: ValueKey('referee-payout-${payout.id}'),
                leading: Icon(
                  payout.state == 'paid'
                      ? Icons.check_circle_outline
                      : Icons.pending_actions_outlined,
                ),
                title: Text(
                  'Till och med ${_date(material, payout.throughDate)} · ${formatKronor(payout.total)}',
                ),
                subtitle: Text(
                  [
                    '${payout.lineCount} domare',
                    payout.state == 'paid' && payout.paidAt != null
                        ? 'utbetald ${_date(material, payout.paidAt!)}'
                        : 'inte utbetald',
                  ].join(' · '),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(payout.id),
              ),
            if (data.canAppointPayers && widget.pickPerson != null) ...[
              const Divider(height: 32),
              Text(
                'Domarersättning',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Text(
                'Kan göra utbetalningslistor och markera dem som utbetalda, till exempel kassören. Klubbens administratörer kan alltid.',
              ),
              for (final person in data.payers)
                ListTile(
                  title: Text(person.name),
                  trailing: IconButton(
                    tooltip: 'Ta bort',
                    onPressed: _busy
                        ? null
                        : () => _payer(
                            person.personId,
                            false,
                            '${person.name} betalar inte längre ut domarersättning.',
                          ),
                    icon: const Icon(Icons.close),
                  ),
                ),
              TextButton.icon(
                key: const ValueKey('referee-payer-add'),
                onPressed: _busy
                    ? null
                    : () async {
                        final person = await widget.pickPerson!(
                          'Lägg till för domarersättning',
                        );
                        if (person == null || !mounted) return;
                        await _payer(
                          person.personId,
                          true,
                          '${person.name} kan betala ut domarersättning.',
                        );
                      },
                icon: const Icon(Icons.add),
                label: const Text('Lägg till'),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// The CSV for a payout list: one row per referee to pay, then every
/// assignment. Semicolons and a BOM so that Excel opens it in Swedish.
String refereePayoutCsv(RefereePayout payout) {
  String cell(Object? value) {
    final text = '${value ?? ''}';
    return text.contains(RegExp('[;"\n]'))
        ? '"${text.replaceAll('"', '""')}"'
        : text;
  }

  String day(DateTime value) {
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  final lines = <List<Object?>>[
    [
      'Namn',
      'Antal uppdrag',
      'Belopp (kr)',
      'Vårdnadshavare',
      'Årets summa (kr)',
    ],
    for (final line in payout.lines)
      [
        line.name,
        line.reportCount,
        line.amount,
        line.guardians,
        line.yearTotal,
      ],
    ['Summa', null, payout.total, null, null],
    [],
    ['Namn', 'Datum', 'Lag', 'Motståndare', 'Plats', 'Belopp (kr)'],
    for (final row in payout.rows)
      [
        row.name,
        day(row.startsAt),
        row.teamName,
        row.opponentName,
        refereeSlotLabel(row.slot),
        row.amount,
      ],
  ];
  return '﻿${lines.map((line) => line.map(cell).join(';')).join('\r\n')}\r\n';
}

/// Saves the export; tests replace it. True when saved.
Future<bool> Function(String fileName, String csv) saveRefereePayoutCsv =
    (fileName, csv) async {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Spara utbetalningslistan',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        bytes: Uint8List.fromList(utf8.encode(csv)),
      );
      return path != null;
    };

/// One payout list: per referee, the year's total against the guide, and
/// under 18 the guardians; export, mark paid, remove.
class ClubRefereePayoutPage extends StatefulWidget {
  const ClubRefereePayoutPage({
    super.key,
    required this.services,
    required this.payoutId,
  });
  final RefereeServices services;
  final String payoutId;

  @override
  State<ClubRefereePayoutPage> createState() => _ClubRefereePayoutPageState();
}

class _ClubRefereePayoutPageState extends State<ClubRefereePayoutPage> {
  late Future<RefereePayout> _payout = widget.services.payout(widget.payoutId);
  bool _busy = false;

  void _reload() {
    final next = widget.services.payout(widget.payoutId);
    setState(() {
      _payout = next;
    });
  }

  Future<void> _export(RefereePayout payout) async {
    final csv = refereePayoutCsv(payout);
    final through = payout.throughDate;
    final name =
        'domarersattning-${through.year}-${through.month.toString().padLeft(2, '0')}-${through.day.toString().padLeft(2, '0')}.csv';
    try {
      if (await saveRefereePayoutCsv(name, csv) && mounted) {
        _snack(context, 'Utbetalningslistan är sparad.');
      }
    } catch (error) {
      AppErrors.caught('club_referee_pay.export', error);
      await Clipboard.setData(ClipboardData(text: csv));
      if (mounted) {
        _snack(
          context,
          'Filen kunde inte sparas. Listan är kopierad i stället.',
        );
      }
    }
  }

  Future<void> _paid(RefereePayout payout) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Markera som utbetald?'),
        content: Text(
          'Gör det när ${formatKronor(payout.total)} är betalt till ${payout.lines.length} domare. Domarna får besked.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            key: const ValueKey('referee-payout-paid-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Utbetald'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    await _attempt(
      context,
      'club_referee_pay.paid',
      () => widget.services.markPayoutPaid(payout.id),
      'Listan är markerad som utbetald.',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    _reload();
  }

  Future<void> _cancel(RefereePayout payout) async {
    setState(() => _busy = true);
    final ok = await _attempt(
      context,
      'club_referee_pay.cancel',
      () => widget.services.cancelPayout(payout.id),
      'Listan är borttagen. Uppdragen kan betalas på en ny lista.',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final material = MaterialLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Utbetalningslista')),
      body: FutureBuilder<RefereePayout>(
        future: _payout,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: TextButton(
                onPressed: _reload,
                child: const Text('Listan kunde inte hämtas. Försök igen.'),
              ),
            );
          }
          final payout = snapshot.data;
          if (payout == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final theme = Theme.of(context);
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Text(
                'Matcher till och med ${_date(material, payout.throughDate)}',
                style: theme.textTheme.titleMedium,
              ),
              Text(
                payout.state == 'paid'
                    ? 'Utbetald${payout.paidAt == null ? '' : ' ${_date(material, payout.paidAt!)}'} · ${formatKronor(payout.total)}'
                    : 'Inte utbetald · ${formatKronor(payout.total)}',
              ),
              const SizedBox(height: 8),
              for (final line in payout.lines)
                ListTile(
                  key: ValueKey('referee-payout-line-${line.id}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text('${line.name} · ${formatKronor(line.amount)}'),
                  subtitle: Text(
                    [
                      '${line.reportCount} uppdrag',
                      'i år ${formatKronor(line.yearTotal)}',
                      if (line.guardians != null)
                        'vårdnadshavare: ${line.guardians}',
                    ].join(' · '),
                  ),
                  trailing: payout.limit > 0 && line.yearTotal > payout.limit
                      ? Tooltip(
                          message: 'Över halva prisbasbeloppet i år',
                          child: Icon(
                            Icons.error_outline,
                            color: theme.colorScheme.error,
                          ),
                        )
                      : payout.limit > 0 && line.yearTotal >= payout.limit * 0.8
                      ? const Tooltip(
                          message: 'Närmar sig halva prisbasbeloppet',
                          child: Icon(Icons.warning_amber_outlined),
                        )
                      : null,
                ),
              const SizedBox(height: 8),
              Text(
                'Årets summa jämförs med halva prisbasbeloppet (${formatKronor(payout.limit)}) som stöd. Klubben avgör vad som gäller för skatt och avgifter.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                key: const ValueKey('referee-payout-export'),
                onPressed: () => _export(payout),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Exportera (CSV)'),
              ),
              if (payout.state == 'draft') ...[
                const SizedBox(height: 8),
                FilledButton.icon(
                  key: const ValueKey('referee-payout-paid'),
                  onPressed: _busy ? null : () => _paid(payout),
                  icon: const Icon(Icons.check),
                  label: const Text('Markera som utbetald'),
                ),
                TextButton(
                  key: const ValueKey('referee-payout-cancel'),
                  onPressed: _busy ? null : () => _cancel(payout),
                  child: const Text('Ta bort listan'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// On the club referee's page: the year's pay and the reports, with a
/// note on one waiting for approval (e.g. that the match was not played).
class MyRefereePaySection extends StatefulWidget {
  const MyRefereePaySection({super.key, required this.services});
  final RefereeServices services;

  @override
  State<MyRefereePaySection> createState() => _MyRefereePaySectionState();
}

class _MyRefereePaySectionState extends State<MyRefereePaySection> {
  late Future<List<MyRefereePay>> _pay = _load();

  Future<List<MyRefereePay>> _load() async {
    try {
      return await widget.services.myPay();
    } catch (error) {
      AppErrors.caught('club_referee_pay.mine', error);
      return const [];
    }
  }

  Future<void> _note(ClubRefereeReport report) async {
    final note = await _askText(
      context,
      title: 'Kommentar till domaransvarig',
      label: 'Till exempel att matchen inte blev av',
      initial: report.refereeNote,
    );
    if (note == null || !mounted) return;
    final ok = await _attempt(
      context,
      'club_referee_pay.note',
      () => widget.services.noteReport(report.id, note),
      'Kommentaren är sparad.',
    );
    if (ok && mounted) {
      setState(() {
        _pay = _load();
      });
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<MyRefereePay>>(
    future: _pay,
    builder: (context, snapshot) {
      final people = snapshot.data ?? const <MyRefereePay>[];
      if (people.isEmpty) return const SizedBox.shrink();
      final theme = Theme.of(context);
      final material = MaterialLocalizations.of(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          Text('Ersättning', style: theme.textTheme.titleMedium),
          for (final person in people) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                [
                  if (people.length > 1) person.name,
                  '${person.year}: ${formatKronor(person.yearTotal)} godkänt och utbetalt',
                ].join(' · '),
                key: ValueKey('my-referee-pay-${person.personId}'),
              ),
            ),
            if (person.reports.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text('Inga spelade uppdrag ännu.'),
              ),
            for (final report in person.reports.take(20))
              ListTile(
                key: ValueKey('my-referee-report-${report.id}'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(report.match.matchup),
                subtitle: Text(
                  [
                    _date(material, report.match.startsAt),
                    refereeSlotLabel(report.slot),
                    formatKronor(report.amount),
                    refereeReportStateLabel(report.state),
                    if (report.state == 'rejected' &&
                        report.rejectReason != null)
                      report.rejectReason!,
                    if (report.refereeNote != null)
                      'din kommentar: ${report.refereeNote}',
                  ].join(' · '),
                ),
                trailing: person.canNote && report.state == 'pending'
                    ? IconButton(
                        key: ValueKey('my-referee-note-${report.id}'),
                        tooltip: 'Lämna kommentar',
                        onPressed: () => _note(report),
                        icon: const Icon(Icons.comment_outlined),
                      )
                    : null,
              ),
          ],
        ],
      );
    },
  );
}
