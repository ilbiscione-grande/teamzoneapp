import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:teamzone_app/src/core/localization/app_strings.dart';
import 'package:teamzone_app/src/core/observability/app_errors.dart';
import 'package:teamzone_app/src/features/team_development/player_talk_services.dart';
import 'package:teamzone_app/src/features/team_development/survey_delete_confirm.dart';
import 'package:teamzone_app/src/features/team_development/team_survey_services.dart';

/// Writes down a talk with a player, with the survey answer beside (above
/// on a phone). Saved as one writes; leaving waits for the last save and
/// warns when it failed. Nothing is saved until something is written.
class PlayerTalkEditor extends StatefulWidget {
  const PlayerTalkEditor({
    super.key,
    required this.teamId,
    required this.personId,
    required this.talks,
    required this.answers,
    required this.answerView,
    this.talk,
    this.responseId,
  });
  final String teamId, personId;
  final PlayerTalks talks;
  final PlayerTalk? talk;
  final List<PlayerSurveyAnswer> answers;

  /// The answer a new talk starts from.
  final String? responseId;
  final Widget Function(PlayerSurveyAnswer answer) answerView;

  @override
  State<PlayerTalkEditor> createState() => _PlayerTalkEditorState();
}

class _PlayerTalkEditorState extends State<PlayerTalkEditor>
    with WidgetsBindingObserver {
  static const _pause = Duration(milliseconds: 1500);

  late final String _id = widget.talk?.id ?? newPlayerTalkId();
  late int? _revision = widget.talk?.revision;
  late DateTime _day =
      widget.talk?.talkedOn ?? DateUtils.dateOnly(DateTime.now());
  late final Set<String> _leaders = {
    if (widget.talk case final talk?)
      for (final leader in talk.leaders) leader.personId
    else
      for (final leader in widget.talks.leaders)
        if (leader.self) leader.personId,
  };
  late String? _responseId = _known(
    widget.talk == null ? widget.responseId : widget.talk!.responseId,
  );
  late final _notes = TextEditingController(text: widget.talk?.leaderNotes);
  late final _agreed = TextEditingController(text: widget.talk?.agreed);

  Timer? _timer;
  Future<void>? _saving;
  bool _dirty = false, _leaving = false, _saved = false;
  Object? _error;

  /// Saves that failed on the way, so that may have landed all the same.
  final List<PlayerTalkDraft> _unanswered = [];

  bool get _swedish => AppStrings.of(context).isSwedish;
  bool get _canEdit => widget.talks.canEdit;
  bool get _conflict =>
      _error is PlayerTalkException &&
      (_error! as PlayerTalkException).code == PlayerTalkException.conflict;
  PlayerSurveyAnswer? get _answer =>
      widget.answers.where((a) => a.responseId == _responseId).firstOrNull;

  String? _known(String? responseId) =>
      widget.answers.any((a) => a.responseId == responseId) ? responseId : null;

  /// The team's leaders, and those at this talk who have since left.
  List<TalkLeader> get _allLeaders => [
    ...widget.talks.leaders,
    for (final leader in widget.talk?.leaders ?? const <TalkLeader>[])
      if (!widget.talks.leaders.any((l) => l.personId == leader.personId))
        leader,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _notes.dispose();
    _agreed.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_flush());
  }

  void _changed([VoidCallback? change]) {
    setState(() {
      change?.call();
      _dirty = true;
    });
    _timer?.cancel();
    if (!_conflict) _timer = Timer(_pause, () => unawaited(_flush()));
  }

  PlayerTalkDraft get _draft => PlayerTalkDraft(
    id: _id,
    talkedOn: _day,
    leaderIds: {..._leaders},
    leaderNotes: _notes.text,
    agreed: _agreed.text,
    responseId: _responseId,
  );

  /// Saves what is not saved yet, one save at a time.
  Future<void> _flush() {
    _timer?.cancel();
    if (_saving case final running?) return running;
    if (!_dirty || _conflict || !mounted) return Future.value();
    return _saving = _saveAll().whenComplete(() {
      _saving = null;
      if (mounted) setState(() {});
    });
  }

  Future<void> _saveAll() async {
    while (_dirty && mounted) {
      final draft = _draft;
      setState(() {
        _dirty = false;
        _error = null;
      });
      try {
        _revision = await _save(draft);
        _unanswered.clear();
        if (mounted) setState(() => _saved = true);
      } catch (error) {
        if (error is! PlayerTalkException) {
          AppErrors.caught('player_talks.save', error);
          _unanswered.add(draft);
        }
        _dirty = true;
        if (mounted) setState(() => _error = error);
        return;
      }
    }
  }

  Future<int> _save(PlayerTalkDraft draft) async {
    final services = PlayerTalksFeature.services;
    try {
      return await services.save(
        widget.teamId,
        widget.personId,
        draft,
        _revision,
      );
    } on PlayerTalkException catch (refused) {
      if (refused.code != PlayerTalkException.conflict) rethrow;
      // Our own earlier save may have landed without its answer reaching
      // us: then the talk holds what one of those saves sent.
      final now = await services.list(widget.teamId, widget.personId);
      final stored = now.talks.where((talk) => talk.id == _id).firstOrNull;
      if (stored == null) rethrow;
      if (draft.matches(stored)) return stored.revision;
      if (!_unanswered.any((earlier) => earlier.matches(stored))) rethrow;
      return services.save(
        widget.teamId,
        widget.personId,
        draft,
        stored.revision,
      );
    }
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    final navigator = Navigator.of(context);
    await _flush();
    if (!mounted) return;
    var leave = !_dirty;
    if (!leave) {
      leave =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(
                _swedish ? 'Texten är inte sparad' : 'The text is not saved',
              ),
              content: Text(
                _swedish
                    ? 'Det du skrev senast kunde inte sparas. Lämnar du sidan försvinner det.'
                    : 'What you last wrote could not be saved. It is lost if you leave.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(_swedish ? 'Lämna ändå' : 'Leave anyway'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(_swedish ? 'Stanna kvar' : 'Stay'),
                ),
              ],
            ),
          ) ??
          false;
    }
    _leaving = false;
    if (leave && mounted) navigator.pop();
  }

  Future<void> _delete() async {
    final navigator = Navigator.of(context);
    final sure = await confirmDeletionTwice(
      context,
      title: _swedish ? 'Ta bort samtalet?' : 'Delete the talk?',
      message: _swedish
          ? 'Samtalet med ${widget.talks.name} och anteckningarna tas bort.'
          : 'The talk with ${widget.talks.name} and the notes are deleted.',
      warning: _swedish
          ? 'Är du säker på att du vill ta bort samtalet för gott? Det går inte att återställa.'
          : 'Are you sure you want to delete the talk for good? It cannot be restored.',
      keep: _swedish ? 'Behåll samtalet' : 'Keep the talk',
    );
    if (!sure || !mounted) return;
    await _flush();
    if (!mounted) return;
    _timer?.cancel();
    try {
      if (_revision case final revision?) {
        await PlayerTalksFeature.services.delete(_id, revision);
      }
      navigator.pop();
    } catch (error) {
      if (error is! PlayerTalkException) {
        AppErrors.caught('player_talks.delete', error);
      }
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _copyText() async {
    final messenger = ScaffoldMessenger.of(context);
    final done = _swedish ? 'Texten är kopierad.' : 'Text copied.';
    await Clipboard.setData(
      ClipboardData(text: '${_notes.text}\n\n${_agreed.text}'.trim()),
    );
    messenger.showSnackBar(SnackBar(content: Text(done)));
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2000),
      lastDate: DateUtils.dateOnly(
        DateTime.now(),
      ).add(const Duration(days: 365)),
    );
    if (picked != null && mounted) _changed(() => _day = picked);
  }

  String get _status => _saving != null || (_dirty && _error == null)
      ? (_swedish ? 'Sparar …' : 'Saving …')
      : _error != null
      ? (_swedish ? 'Inte sparat' : 'Not saved')
      : _saved
      ? (_swedish ? 'Sparat' : 'Saved')
      : '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final answer = _answer;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return PopScope(
      canPop: !_dirty && _saving == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _swedish
                ? 'Samtal med ${widget.talks.name}'
                : 'Talk with ${widget.talks.name}',
          ),
          actions: [
            Center(
              child: Text(
                _status,
                key: const Key('talk-status'),
                style: theme.textTheme.bodySmall,
              ),
            ),
            if (_canEdit && _revision != null)
              IconButton(
                key: const Key('talk-delete'),
                tooltip: _swedish ? 'Ta bort samtalet' : 'Delete the talk',
                icon: const Icon(Icons.delete_outline),
                onPressed: _delete,
              ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            if (_error case final error?) _errorBanner(theme, error),
            Expanded(
              child: wide && answer != null
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.all(24),
                            children: [
                              Text(
                                answer.title,
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 12),
                              widget.answerView(answer),
                            ],
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.all(24),
                            children: _form(theme),
                          ),
                        ),
                      ],
                    )
                  : Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
                          children: [
                            ..._form(
                              theme,
                              answers: answer == null
                                  ? null
                                  : Card(
                                      margin: const EdgeInsets.only(top: 12),
                                      child: ExpansionTile(
                                        key: const Key('talk-answers'),
                                        title: Text(answer.title),
                                        subtitle: Text(
                                          _swedish
                                              ? 'Visa spelarens svar'
                                              : 'Show the player\'s answers',
                                        ),
                                        childrenPadding:
                                            const EdgeInsets.fromLTRB(
                                              16,
                                              0,
                                              16,
                                              8,
                                            ),
                                        children: [widget.answerView(answer)],
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorBanner(ThemeData theme, Object error) => Material(
    color: theme.colorScheme.errorContainer,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              error is PlayerTalkException
                  ? error.message(_swedish)
                  : _swedish
                  ? 'Det gick inte att spara. Kontrollera uppkopplingen.'
                  : 'It could not be saved. Check the connection.',
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
          ),
          TextButton(
            onPressed: _conflict ? _copyText : () => unawaited(_flush()),
            child: Text(
              _conflict
                  ? (_swedish ? 'Kopiera texten' : 'Copy the text')
                  : (_swedish ? 'Försök igen' : 'Retry'),
            ),
          ),
        ],
      ),
    ),
  );

  List<Widget> _form(ThemeData theme, {Widget? answers}) {
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final leaders = _allLeaders;
    return [
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          key: const Key('talk-day'),
          onPressed: _canEdit ? _pickDay : null,
          icon: const Icon(Icons.event),
          label: Text(MaterialLocalizations.of(context).formatCompactDate(_day)),
        ),
      ),
      if (leaders.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(
          _swedish ? 'Ledare som var med' : 'Leaders who were there',
          style: theme.textTheme.labelLarge,
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final leader in leaders)
              FilterChip(
                key: Key('talk-leader-${leader.personId}'),
                label: Text(leader.name),
                selected: _leaders.contains(leader.personId),
                onSelected: _canEdit
                    ? (on) => _changed(
                        () => on
                            ? _leaders.add(leader.personId)
                            : _leaders.remove(leader.personId),
                      )
                    : null,
              ),
          ],
        ),
      ],
      if (widget.answers.isNotEmpty) ...[
        const SizedBox(height: 16),
        DropdownButtonFormField<String?>(
          key: const Key('talk-response'),
          initialValue: _responseId,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: _swedish
                ? 'Enkätsvar som underlag'
                : 'Survey answer to start from',
          ),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text(_swedish ? 'Inget' : 'None'),
            ),
            for (final answer in widget.answers)
              DropdownMenuItem<String?>(
                value: answer.responseId,
                child: Text(answer.title, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: _canEdit
              ? (id) => _changed(() => _responseId = id)
              : null,
        ),
      ],
      ?answers,
      const SizedBox(height: 24),
      Text(
        _swedish ? 'Ledarnas anteckningar' : 'The leaders\' notes',
        style: theme.textTheme.titleMedium,
      ),
      Text(
        _swedish
            ? 'Syns bara för lagets ledare med Säsongsplanering, inte för spelaren. Skriv inte om hälsa eller bestraffningar. Spelaren eller en vårdnadshavare kan ha rätt att begära ut texten.'
            : 'Only the team\'s leaders with Season planning see this, not the player. Do not write about health or sanctions. The player or a guardian may have the right to request the text.',
        style: muted,
      ),
      const SizedBox(height: 8),
      TextField(
        key: const Key('talk-notes'),
        controller: _notes,
        readOnly: !_canEdit,
        maxLength: 20000,
        minLines: 8,
        maxLines: null,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          counterText: '',
        ),
        onChanged: (_) => _changed(),
      ),
      const SizedBox(height: 24),
      Text(
        _swedish ? 'Vi kom överens om' : 'We agreed on',
        style: theme.textTheme.titleMedium,
      ),
      Text(
        _swedish
            ? 'Syns än så länge också bara för ledarna. Ska kunna delas med spelaren när utvecklingsplanen (IDP) byggs, så skriv det som ni sa det till spelaren.'
            : 'For now only the leaders see this too. It can be shared with the player once the development plan is built, so write it as you told the player.',
        style: muted,
      ),
      const SizedBox(height: 8),
      TextField(
        key: const Key('talk-agreed'),
        controller: _agreed,
        readOnly: !_canEdit,
        maxLength: 8000,
        minLines: 4,
        maxLines: null,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          counterText: '',
        ),
        onChanged: (_) => _changed(),
      ),
    ];
  }
}
