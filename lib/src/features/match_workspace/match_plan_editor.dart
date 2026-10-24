part of '../../app/teamzone_app.dart';

/// The match plan, Förberedelse in the Match module: tactics, set pieces
/// and the opponent with ready openings to start from, each shown to the
/// players or not; the event's match goals; links; and publishing. Who may
/// not edit reads the same plan.
class _MatchPlanEditor extends StatefulWidget {
  const _MatchPlanEditor({required this.eventId, required this.calendar});
  final String eventId;
  final CalendarServices calendar;

  @override
  State<_MatchPlanEditor> createState() => _MatchPlanEditorState();
}

class _MatchPlanEditorState extends State<_MatchPlanEditor> {
  final _tactics = TextEditingController();
  final _setPieces = TextEditingController();
  final _opponent = TextEditingController();
  bool _showTactics = true, _showSetPieces = true, _showOpponent = false;
  bool _published = false, _busy = false, _dirty = false;
  MatchPlan? _plan;
  Object? _error;
  late final Future<EventFollowup?> _goals = _loadGoals();

  // MFD-12: the period's focus and the team's principles, as support when
  // writing the tactics. A suggestion only.
  late final Future<TeamPlanSuggestion?> _planSuggestion =
      widget.calendar.matchPlans is TeamPlanSuggestionServices
      ? (widget.calendar.matchPlans as TeamPlanSuggestionServices)
            .teamPlanSuggestion(widget.eventId)
            .catchError((Object error) {
              AppErrors.caught('match_plan_editor._planSuggestion', error);
              return null;
            })
      : Future.value(null);

  /// A principle or goal into the tactics, on a line of its own.
  Future<void> _takeIntoTactics(String label) async {
    final text = _tactics.text.trimRight();
    _tactics.text = text.isEmpty ? '• $label' : '$text\n• $label';
    _changed();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in [_tactics, _setPieces, _opponent]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<EventFollowup?> _loadGoals() => widget.calendar.preparation
      .getFollowup(widget.eventId)
      .then<EventFollowup?>((value) => value, onError: (_) => null);

  Future<void> _load() async {
    try {
      final plan = await widget.calendar.matchPlans.getPlan(widget.eventId);
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _error = null;
        _dirty = false;
        _tactics.text = plan?.tactics?.text ?? '';
        _setPieces.text = plan?.setPieces?.text ?? '';
        _opponent.text = plan?.opponent?.text ?? '';
        _showTactics = plan?.tactics?.visible ?? true;
        _showSetPieces = plan?.setPieces?.visible ?? true;
        _showOpponent = plan?.opponent?.visible ?? false;
        _published = plan?.published ?? false;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _save() async {
    final plan = _plan;
    if (plan == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final strings = AppStrings.of(context);
    setState(() => _busy = true);
    try {
      await widget.calendar.matchPlans.savePlan(
        eventId: widget.eventId,
        expectedRevision: plan.revision,
        tactics: _tactics.text,
        setPieces: _setPieces.text,
        opponent: _opponent.text,
        showTactics: _showTactics,
        showSetPieces: _showSetPieces,
        showOpponent: _showOpponent,
        published: _published,
      );
      messenger.showSnackBar(
        SnackBar(content: Text(strings.feature('Matchplanen är sparad.'))),
      );
      await _load();
    } on MatchPlanConflict {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            strings.feature(
              'Någon annan har ändrat matchplanen. Den senaste versionen visas nu.',
            ),
          ),
        ),
      );
      await _load();
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(strings.feature('Matchplanen kunde inte sparas.')),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _changed() => setState(() => _dirty = true);

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    if (_error != null) {
      return Center(
        child: TextButton(
          onPressed: _load,
          child: Text(
            strings.feature('Matchplanen kunde inte hämtas. Försök igen.'),
          ),
        ),
      );
    }
    final plan = _plan;
    if (plan == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final edit = plan.canEdit;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _MatchPlanHeader(plan: plan),
        const SizedBox(height: 12),
        if (edit)
          FutureBuilder<TeamPlanSuggestion?>(
            future: _planSuggestion,
            builder: (context, snapshot) => switch (snapshot.data) {
              final suggestion? => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _PlanSuggestionBox(
                  suggestion: suggestion,
                  taken: {
                    for (final line in _tactics.text.split('\n'))
                      line
                          .replaceFirst(RegExp(r'^•\s*'), '')
                          .trim()
                          .toLowerCase(),
                  },
                  onTake: _takeIntoTactics,
                  takeHint: 'Ett tryck lägger in den under Taktik.',
                ),
              ),
              null => const SizedBox.shrink(),
            },
          ),
        _PlanSectionCard(
          area: 'tactics',
          title: 'Taktik',
          controller: _tactics,
          visible: _showTactics,
          edit: edit,
          onEdited: _changed,
          onVisible: (value) => setState(() {
            _showTactics = value;
            _dirty = true;
          }),
        ),
        _PlanSectionCard(
          area: 'set_pieces',
          title: 'Standardsituationer',
          controller: _setPieces,
          visible: _showSetPieces,
          edit: edit,
          onEdited: _changed,
          onVisible: (value) => setState(() {
            _showSetPieces = value;
            _dirty = true;
          }),
        ),
        _PlanSectionCard(
          area: 'opponent',
          title: 'Motståndaren och nyckelspelare',
          controller: _opponent,
          visible: _showOpponent,
          edit: edit,
          onEdited: _changed,
          onVisible: (value) => setState(() {
            _showOpponent = value;
            _dirty = true;
          }),
        ),
        _MatchGoalsCard(goals: _goals),
        _MatchPlanLinks(
          eventId: widget.eventId,
          services: widget.calendar.matchPlans,
          links: plan.links,
          canEdit: edit,
          onChanged: _load,
        ),
        if (edit) ...[
          SwitchListTile(
            key: const Key('match-plan-published'),
            contentPadding: EdgeInsets.zero,
            value: _published,
            onChanged: (value) => setState(() {
              _published = value;
              _dirty = true;
            }),
            title: Text(strings.feature('Publicerad för spelarna')),
            subtitle: Text(
              strings.feature(
                'Spelarna ser de delar som visas, när planen är publicerad.',
              ),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('match-plan-save'),
            onPressed: _busy || !_dirty ? null : _save,
            child: Text(
              strings.feature(_busy ? 'Sparar…' : 'Spara matchplanen'),
            ),
          ),
        ],
      ],
    );
  }
}
