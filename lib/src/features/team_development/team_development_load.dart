part of '../../app/teamzone_app.dart';

/// What a signal says about a player, as facts, and what the rule suggests
/// (step 8, PAR-METHOD-01): never a medical conclusion.
({String fact, String advice}) _tdpSignalText(
  BuildContext context,
  LoadSignal signal,
  PlayerLoad player,
) => switch (signal) {
  LoadSignal.loadIncrease => (
    fact: _tdpText(
      context,
      '${player.minutes7} min de senaste 7 dagarna, ${player.loadPercent} % av en snittvecka.',
      '${player.minutes7} min in the last 7 days, ${player.loadPercent}% of an average week.',
    ),
    advice: _tdpText(
      context,
      'Överväg ett lugnare pass, eller prata med spelaren.',
      'Consider a lighter session, or talk to the player.',
    ),
  ),
  LoadSignal.lowAttendance => (
    fact: _tdpText(
      context,
      'På ${player.sessions28} av ${player.trainings28} träningar de senaste 4 veckorna.',
      'At ${player.sessions28} of ${player.trainings28} trainings in the last 4 weeks.',
    ),
    advice: _tdpText(
      context,
      'Prata med spelaren om frånvaron.',
      'Talk to the player about the absence.',
    ),
  ),
  LoadSignal.matchMinutes => (
    fact: _tdpText(
      context,
      '${player.matchMinutes7} matchminuter de senaste 7 dagarna.',
      '${player.matchMinutes7} match minutes in the last 7 days.',
    ),
    advice: _tdpText(
      context,
      'Tänk på speltiden i nästa match.',
      'Mind the playing time in the next match.',
    ),
  ),
};

String _tdpSignalName(BuildContext context, LoadSignal signal) =>
    switch (signal) {
      LoadSignal.loadIncrease => _tdpText(
        context,
        'Ökad belastning',
        'Increased load',
      ),
      LoadSignal.lowAttendance => _tdpText(
        context,
        'Låg närvaro',
        'Low attendance',
      ),
      LoadSignal.matchMinutes => _tdpText(
        context,
        'Mycket speltid',
        'A lot of playing time',
      ),
    };

/// The team's side of Översikt (step 8): the players a signal points at
/// ("Behöver din uppmärksamhet", with what the rule suggests), then every
/// player's load over the last 7 days and 4 weeks. The leaders set the
/// signals' values for the team.
class _TdpTeamLoad extends StatefulWidget {
  const _TdpTeamLoad({super.key, required this.controller, required this.plan});
  final _TdpController controller;
  final SeasonPlan plan;

  @override
  State<_TdpTeamLoad> createState() => _TdpTeamLoadState();
}

class _TdpTeamLoadState extends State<_TdpTeamLoad> {
  /// Players beyond the first few show on request.
  static const _shown = 8, _shownAttention = 5;
  bool _allAttention = false;
  late Future<TeamLoad> _load = widget.controller.services.load(widget.plan);
  bool _all = false;

  Future<void> _settings(LoadSettings current) async {
    final chosen = await showDialog<LoadSettings>(
      context: context,
      builder: (context) => _TdpLoadSettingsDialog(settings: current),
    );
    if (chosen == null || !mounted) return;
    final saved = widget.controller.services.saveLoadSettings(
      widget.plan,
      chosen,
    );
    setState(() {
      _load = saved;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<TeamLoad>(
      future: _load,
      builder: (context, snapshot) {
        final load = snapshot.data;
        if (snapshot.hasError) {
          return _TdpHint(
            icon: Icons.error_outline,
            text: _tdpText(
              context,
              'Belastningen kunde inte hämtas.',
              'The load could not be loaded.',
            ),
          );
        }
        if (load == null) return const SizedBox.shrink();
        final flagged = load.flagged;
        final attention = [
          for (final player in flagged)
            for (final signal in player.signals) (player, signal),
        ];
        final players = _all ? load.players : load.players.take(_shown);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              key: const Key('tdp-attention'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _tdpText(
                        context,
                        'Behöver din uppmärksamhet',
                        'Needs your attention',
                      ),
                      style: theme.textTheme.titleMedium,
                    ),
                    if (flagged.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          _tdpText(
                            context,
                            'Ingen spelare sticker ut just nu.',
                            'No player stands out right now.',
                          ),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    for (final (player, signal)
                        in _allAttention
                            ? attention
                            : attention.take(_shownAttention))
                      ListTile(
                        key: ValueKey(
                          'tdp-attention-${player.personId}-${signal.key}',
                        ),
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(switch (signal) {
                          LoadSignal.loadIncrease => Icons.trending_up,
                          LoadSignal.lowAttendance => Icons.event_busy,
                          LoadSignal.matchMinutes => Icons.timer_outlined,
                        }),
                        title: Text(
                          '${player.name} · ${_tdpSignalName(context, signal)}',
                        ),
                        subtitle: Text(
                          '${_tdpSignalText(context, signal, player).fact}\n${_tdpSignalText(context, signal, player).advice}',
                        ),
                        isThreeLine: true,
                      ),
                    if (!_allAttention && attention.length > _shownAttention)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          key: const Key('tdp-attention-all'),
                          onPressed: () => setState(() => _allAttention = true),
                          child: Text(
                            _tdpText(
                              context,
                              'Visa alla ${attention.length}',
                              'Show all ${attention.length}',
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              key: const Key('tdp-players-load'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _tdpText(context, 'Spelarna', 'The players'),
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        if (widget.controller.canEdit)
                          IconButton(
                            key: const Key('tdp-load-settings'),
                            tooltip: _tdpText(
                              context,
                              'Gränsvärden',
                              'Thresholds',
                            ),
                            icon: const Icon(Icons.tune),
                            onPressed: () => _settings(load.settings),
                          ),
                      ],
                    ),
                    Text(
                      _tdpText(
                        context,
                        'Senaste 7 dagarna, och 4 veckor. Räknat ur närvaron och matcherna.',
                        'The last 7 days, and 4 weeks. Counted from the attendance and the matches.',
                      ),
                      style: theme.textTheme.bodySmall,
                    ),
                    if (load.players.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          _tdpText(
                            context,
                            'Inga spelare i laget.',
                            'No players in the team.',
                          ),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    for (final player in players)
                      ListTile(
                        key: ValueKey('tdp-player-load-${player.personId}'),
                        contentPadding: const EdgeInsets.only(right: 8),
                        dense: true,
                        title: Row(
                          children: [
                            Flexible(child: Text(player.name)),
                            for (final signal in player.signals) ...[
                              const SizedBox(width: 6),
                              Tooltip(
                                message: _tdpSignalName(context, signal),
                                child: Icon(
                                  Icons.circle,
                                  size: 8,
                                  color: theme.colorScheme.error,
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          _tdpText(
                            context,
                            '${player.sessions7} pass · ${player.trainingMinutes7} min träning · ${player.matchMinutes7} min match'
                                '\n4 v: ${player.sessions28} pass · ${player.matchMinutes28} min match'
                                '${player.attendancePercent == null ? '' : ' · närvaro ${player.attendancePercent} %'}'
                                '${player.effort7 == null ? '' : '\nansträngning ${player.effort7!.toStringAsFixed(1).replaceAll('.', ',')} av 10 (${player.efforts7} svar)'}',
                            '${player.sessions7} sessions · ${player.trainingMinutes7} min training · ${player.matchMinutes7} min match'
                                '\n4 wk: ${player.sessions28} sessions · ${player.matchMinutes28} min match'
                                '${player.attendancePercent == null ? '' : ' · attendance ${player.attendancePercent}%'}'
                                '${player.effort7 == null ? '' : '\neffort ${player.effort7!.toStringAsFixed(1)} of 10 (${player.efforts7} answers)'}',
                          ),
                        ),
                        trailing: Text(
                          '${player.minutes7} min',
                          style: theme.textTheme.labelLarge,
                        ),
                      ),
                    if (!_all && load.players.length > _shown)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          key: const Key('tdp-players-load-all'),
                          onPressed: () => setState(() => _all = true),
                          child: Text(
                            _tdpText(
                              context,
                              'Visa alla ${load.players.length}',
                              'Show all ${load.players.length}',
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The team's values for the signals; an empty field turns one off.
class _TdpLoadSettingsDialog extends StatefulWidget {
  const _TdpLoadSettingsDialog({required this.settings});
  final LoadSettings settings;

  @override
  State<_TdpLoadSettingsDialog> createState() => _TdpLoadSettingsDialogState();
}

class _TdpLoadSettingsDialogState extends State<_TdpLoadSettingsDialog> {
  final _form = GlobalKey<FormState>();
  late final _increase = TextEditingController(
    text: widget.settings.loadIncreasePercent?.toString() ?? '',
  );
  late final _attendance = TextEditingController(
    text: widget.settings.attendanceMinPercent?.toString() ?? '',
  );
  late final _match = TextEditingController(
    text: widget.settings.matchMinutesMax?.toString() ?? '',
  );

  @override
  void dispose() {
    _increase.dispose();
    _attendance.dispose();
    _match.dispose();
    super.dispose();
  }

  static int? _value(TextEditingController field) =>
      int.tryParse(field.text.trim());

  Widget _field(
    String key,
    TextEditingController field,
    String label,
    String helper,
    int min,
    int max,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      key: Key(key),
      controller: field,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 3,
      ),
      validator: (text) {
        final trimmed = (text ?? '').trim();
        if (trimmed.isEmpty) return null;
        final value = int.tryParse(trimmed);
        return value == null || value < min || value > max
            ? _tdpText(
                context,
                'Ett tal från $min till $max, eller tomt.',
                'A number from $min to $max, or empty.',
              )
            : null;
      },
    ),
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_tdpText(context, 'Gränsvärden', 'Thresholds')),
    content: SizedBox(
      width: 420,
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _tdpText(
                    context,
                    'Ställ in värdena för ert lag, till exempel efter årskull. Ett tomt fält stänger av signalen.',
                    'Set the values for your team, for example by age group. An empty field turns the signal off.',
                  ),
                ),
              ),
              _field(
                'tdp-load-increase',
                _increase,
                _tdpText(context, 'Ökad belastning, %', 'Increased load, %'),
                _tdpText(
                  context,
                  'När de senaste 7 dagarnas minuter är minst så här mycket av en snittvecka under 4 veckor (100–400).',
                  'When the last 7 days\' minutes are at least this share of an average week over 4 weeks (100–400).',
                ),
                100,
                400,
              ),
              _field(
                'tdp-load-attendance',
                _attendance,
                _tdpText(context, 'Låg närvaro, %', 'Low attendance, %'),
                _tdpText(
                  context,
                  'När spelaren varit på färre än så här många procent av träningarna under 4 veckor (1–100).',
                  'When the player was at fewer than this share of the trainings over 4 weeks (1–100).',
                ),
                1,
                100,
              ),
              _field(
                'tdp-load-match',
                _match,
                _tdpText(
                  context,
                  'Mycket speltid, minuter',
                  'A lot of playing time, minutes',
                ),
                _tdpText(
                  context,
                  'När spelaren spelat mer än så här många matchminuter de senaste 7 dagarna (1–1000).',
                  'When the player played more than this many match minutes in the last 7 days (1–1000).',
                ),
                1,
                1000,
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(AppStrings.of(context).cancel),
      ),
      FilledButton(
        key: const Key('tdp-load-save'),
        onPressed: () {
          if (!(_form.currentState?.validate() ?? false)) return;
          Navigator.of(context).pop(
            LoadSettings(
              loadIncreasePercent: _value(_increase),
              attendanceMinPercent: _value(_attendance),
              matchMinutesMax: _value(_match),
            ),
          );
        },
        child: Text(_tdpText(context, 'Spara', 'Save')),
      ),
    ],
  );
}
