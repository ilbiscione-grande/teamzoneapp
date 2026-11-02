part of '../../app/teamzone_app.dart';

/// What a key figure counts from the matches, in words; an own button by
/// its label.
String _tdpKpiSourceLabel(
  BuildContext context,
  SeasonPlan plan,
  String source,
) {
  if (source.startsWith('button:')) {
    final id = source.substring(7);
    final label =
        plan.matchButtons.where((b) => b.id == id).firstOrNull?.label ??
        _tdpText(context, 'borttagen knapp', 'removed button');
    return _tdpText(context, 'Egen knapp: $label', 'Own button: $label');
  }
  final known = kpiSources.where((s) => s.$1 == source).firstOrNull;
  return known == null ? source : _tdpText(context, known.$2, known.$3);
}

/// Where a key figure's values come from: by hand, or what the matches
/// count (step 6).
class _TdpKpiSourceField extends StatelessWidget {
  const _TdpKpiSourceField({
    required this.plan,
    required this.value,
    required this.onChanged,
  });
  final SeasonPlan plan;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final sources = [
      for (final source in kpiSources) source.$1,
      for (final button in plan.matchButtons) 'button:${button.id}',
      // A source no longer offered (a removed button) stays as it is.
      if (value != null &&
          !kpiSources.any((s) => s.$1 == value) &&
          !plan.matchButtons.any((b) => 'button:${b.id}' == value))
        value!,
    ];
    return DropdownButtonFormField<String?>(
      key: const Key('tdp-kpi-source'),
      isExpanded: true,
      initialValue: value,
      decoration: InputDecoration(
        labelText: _tdpText(context, 'Värden', 'Values'),
        helperText: value == null
            ? null
            : _tdpText(
                context,
                'Hämtas från matcherna. Ett värde kan rättas för hand.',
                'Taken from the matches. A value can be corrected by hand.',
              ),
      ),
      items: [
        DropdownMenuItem<String?>(
          value: null,
          child: Text(_tdpText(context, 'Fylls i för hand', 'Added by hand')),
        ),
        for (final source in sources)
          DropdownMenuItem<String?>(
            value: source,
            child: Text(
              _tdpText(
                context,
                'Från matcherna: ${_tdpKpiSourceLabel(context, plan, source)}',
                'From the matches: ${_tdpKpiSourceLabel(context, plan, source)}',
              ),
            ),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

/// A key figure's value from a match: counted, set by hand for it, or none
/// when the match tells nothing. A tap sets it by hand, or shows the
/// counted value again.
class _TdpKpiMatchTile extends StatelessWidget {
  const _TdpKpiMatchTile({
    required this.controller,
    required this.kpi,
    required this.match,
    this.value,
  });
  final _TdpController controller;
  final TeamKpi kpi;
  final PlanMatch match;
  final KpiValue? value;

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    final counted = value?.counted ?? true;
    final note = value?.checkin?.note.trim() ?? '';
    return ListTile(
      key: ValueKey('tdp-kpi-match-${match.eventId}'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        counted ? Icons.sports_soccer : Icons.edit_note,
        color: counted ? null : Theme.of(context).colorScheme.primary,
      ),
      title: Text(match.title),
      subtitle: Text(
        [
          _tdpDate(context, match.playedOn),
          if (value == null)
            _tdpText(
              context,
              'händelserna registrerades inte',
              'the events were not recorded',
            )
          else if (value.counted)
            _tdpText(context, 'räknat från matchen', 'counted from the match')
          else
            _tdpText(context, 'satt för hand', 'set by hand'),
          if (note.isNotEmpty) note,
        ].join(' · '),
      ),
      trailing: Text(
        value == null ? '–' : '${_tdpNumber(value.value)} ${kpi.unit}'.trim(),
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      onTap: controller.canEdit
          ? () => _TdpKpiMatchValueDialog.edit(
              context,
              controller,
              kpi,
              match,
              value,
            )
          : null,
    );
  }
}

/// Sets a key figure's value for a match by hand, or lets the match count
/// it again.
abstract final class _TdpKpiMatchValueDialog {
  static Future<void> edit(
    BuildContext context,
    _TdpController controller,
    TeamKpi kpi,
    PlanMatch match,
    KpiValue? value,
  ) async {
    final counted = kpi.source == null ? null : match.valueOf(kpi.source!);
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => _TdpTexts(
        first: value == null ? '' : _tdpNumber(value.value),
        second: value?.checkin?.note ?? '',
        builder: (context, number, note) => StatefulBuilder(
          builder: (context, setState) {
            final parsed = double.tryParse(
              number.text.trim().replaceAll(',', '.'),
            );
            return AlertDialog(
              title: Text(kpi.title),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${match.title} · ${_tdpDate(context, match.playedOn)}',
                    ),
                    const SizedBox(height: 4),
                    Text(
                      counted == null
                          ? _tdpText(
                              context,
                              'Matchen räknar inget värde, eftersom dess händelser inte registrerades.',
                              'The match counts no value, as its events were not recorded.',
                            )
                          : _tdpText(
                              context,
                              'Matchen räknar ${_tdpNumber(counted)} ${kpi.unit}.',
                              'The match counts ${_tdpNumber(counted)} ${kpi.unit}.',
                            ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    TextField(
                      key: const Key('tdp-kpi-match-value'),
                      controller: number,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: InputDecoration(
                        labelText: _tdpText(context, 'Värde', 'Value'),
                        suffixText: kpi.unit,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    TextField(
                      key: const Key('tdp-kpi-match-note'),
                      controller: note,
                      maxLength: 2000,
                      decoration: InputDecoration(
                        labelText: _tdpText(
                          context,
                          'Anteckning (valfritt)',
                          'Note (optional)',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                if (value != null && !value.counted)
                  TextButton(
                    key: const Key('tdp-kpi-match-reset'),
                    onPressed: () => Navigator.pop(context, ('reset', '')),
                    child: Text(
                      counted == null
                          ? _tdpText(context, 'Ta bort', 'Remove')
                          : _tdpText(
                              context,
                              'Använd matchens värde',
                              'Use the match value',
                            ),
                    ),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(AppStrings.of(context).feature('Avbryt')),
                ),
                FilledButton(
                  key: const Key('tdp-kpi-match-save'),
                  onPressed: parsed == null
                      ? null
                      : () => Navigator.pop(context, (
                          number.text.trim().replaceAll(',', '.'),
                          note.text.trim(),
                        )),
                  child: Text(AppStrings.of(context).feature('Spara')),
                ),
              ],
            );
          },
        ),
      ),
    );
    final plan = controller.plan;
    if (result == null || plan == null || !context.mounted) return;
    final reset = result.$1 == 'reset';
    await controller.change(
      context,
      () => controller.services.setKpiMatchValue(
        plan,
        kpiId: kpi.id,
        eventId: match.eventId,
        value: reset ? null : double.parse(result.$1),
        note: reset ? '' : result.$2,
      ),
      done: reset
          ? _tdpText(
              context,
              'Matchens värde används igen.',
              'The match value is used again.',
            )
          : _tdpText(context, 'Värdet är sparat.', 'The value is saved.'),
    );
  }
}
