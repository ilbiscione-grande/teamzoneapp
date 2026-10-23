part of '../../app/teamzone_app.dart';

class _LiveEventResult {
  const _LiveEventResult({
    required this.minute,
    this.side,
    this.playerId,
    this.secondaryId,
    this.detail = const {},
    this.delete = false,
  });
  final int minute;
  final String? side, playerId, secondaryId;
  final Map<String, Object?> detail;
  final bool delete;
}

/// Registers or corrects one event, as the old app's quick log: the side,
/// the result, who (for a substitution who goes off and who comes on, the
/// next planned one offered), the minute and a comment.
class _LiveEventSheet extends StatefulWidget {
  const _LiveEventSheet({
    required this.kind,
    required this.players,
    required this.onPitch,
    required this.minute,
    required this.opponentName,
    required this.name,
    this.fact,
    this.planned,
  });
  final LiveEventKind kind;
  final List<MatchRosterMember> players;
  final List<String> onPitch;
  final int minute;
  final String opponentName;
  final String Function(String?) name;
  final Map<String, dynamic>? fact;
  final PlannedSubstitution? planned;

  @override
  State<_LiveEventSheet> createState() => _LiveEventSheetState();
}

class _LiveEventSheetState extends State<_LiveEventSheet> {
  late final Map<dynamic, dynamic> _detail =
      (widget.fact?['detail'] as Map?) ?? const {};
  late String _side = widget.fact?['side'] as String? ?? 'us';
  late int _minute =
      (widget.fact?['minute'] as num?)?.toInt() ??
      widget.planned?.minute ??
      widget.minute;
  late String? _result =
      _detail[widget.kind.resultKey] as String? ?? widget.kind.defaultResult;
  late String? _player =
      widget.fact?['club_person_id'] as String? ?? widget.planned?.outId;
  late String? _secondary =
      widget.fact?['secondary_club_person_id'] as String? ??
      widget.planned?.inId;
  late (double, double)? _location = widget.fact == null
      ? null
      : factLocation(widget.fact!);
  late final _comment = TextEditingController(
    text: _detail['comment'] as String? ?? '',
  );

  bool get _substitution => widget.kind.type == 'substitution';
  bool get _editing => widget.fact != null;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  List<MatchRosterMember> _choices({required bool playing}) {
    if (!_substitution || widget.onPitch.isEmpty) return widget.players;
    final pitch = widget.onPitch.toSet();
    return widget.players
        .where((p) => pitch.contains(p.personId) == playing)
        .toList();
  }

  Widget _picker(
    String label,
    String? value,
    List<MatchRosterMember> choices,
    ValueChanged<String?> onChanged, {
    bool optional = true,
  }) {
    final ids = choices.map((p) => p.personId).toSet();
    return DropdownButtonFormField<String?>(
      key: Key('live-sheet-$label'),
      initialValue: ids.contains(value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, isDense: true),
      items: [
        if (optional)
          const DropdownMenuItem<String?>(
            value: null,
            child: Text('Ingen vald'),
          ),
        for (final player in choices)
          DropdownMenuItem<String?>(
            value: player.personId,
            child: Text(player.name),
          ),
      ],
      onChanged: onChanged,
    );
  }

  void _save() {
    final planned = widget.planned;
    final keepsPlan =
        planned != null &&
        planned.outId == _player &&
        planned.inId == _secondary;
    final comment = _comment.text.trim();
    final us = _side == 'us';
    Navigator.pop(
      context,
      _LiveEventResult(
        minute: _minute,
        side: _side,
        playerId: us ? _player : null,
        secondaryId: us && _substitution ? _secondary : null,
        detail: {
          for (final entry in _detail.entries)
            if (entry.key is String &&
                !const [
                  'comment',
                  'result',
                  'color',
                  'plan_id',
                  'location',
                ].contains(entry.key))
              entry.key as String: entry.value,
          if (_result != null && widget.kind.results.isNotEmpty)
            widget.kind.resultKey: _result,
          if (comment.isNotEmpty) 'comment': comment,
          if (_location case (final x, final y) when widget.kind.locatable)
            'location': locationDetail(x, y),
          if (_substitution && (keepsPlan || _detail['plan_id'] != null))
            'plan_id': keepsPlan ? planned.id : _detail['plan_id'],
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final us = _side == 'us';
    final ready =
        !_substitution ||
        (_player != null && _secondary != null && _player != _secondary);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(_liveIcon(kind.type)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_editing ? 'Rätta' : 'Registrera'} ${kind.label.toLowerCase()}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'En minut tidigare',
                    onPressed: _minute > 0
                        ? () => setState(() => _minute--)
                        : null,
                    icon: const Icon(Icons.remove),
                  ),
                  Text(
                    "$_minute′",
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  IconButton(
                    tooltip: 'En minut senare',
                    onPressed: () => setState(() => _minute++),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              if (widget.planned != null && !_editing)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Från bytesplanen: ${widget.name(widget.planned!.outId)} ut, '
                    '${widget.name(widget.planned!.inId)} in',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (!_substitution) ...[
                SegmentedButton<String>(
                  key: const Key('live-sheet-side'),
                  segments: [
                    const ButtonSegment(value: 'us', label: Text('Vi')),
                    ButtonSegment(
                      value: 'opponent',
                      label: Text(
                        widget.opponentName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  selected: {_side},
                  onSelectionChanged: (value) =>
                      setState(() => _side = value.first),
                ),
                const SizedBox(height: 10),
              ],
              if (kind.results.isNotEmpty) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final (value, label) in kind.results)
                      ChoiceChip(
                        key: Key('live-sheet-result-$value'),
                        label: Text(label),
                        selected: _result == value,
                        onSelected: (_) => setState(() => _result = value),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              if (_substitution) ...[
                _picker(
                  'Ut',
                  _player,
                  _choices(playing: true),
                  (id) => setState(() => _player = id),
                  optional: false,
                ),
                const SizedBox(height: 8),
                _picker(
                  'In',
                  _secondary,
                  _choices(playing: false),
                  (id) => setState(() => _secondary = id),
                  optional: false,
                ),
              ] else if (us)
                _picker(
                  kind.type == 'save' ? 'Målvakt' : 'Spelare',
                  _player,
                  widget.players,
                  (id) => setState(() => _player = id),
                ),
              if (kind.locatable) ...[
                const SizedBox(height: 10),
                _LocationField(
                  value: _location,
                  onChanged: (place) => setState(() => _location = place),
                ),
              ],
              const SizedBox(height: 8),
              TextField(
                key: const Key('live-sheet-comment'),
                controller: _comment,
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: 'Kommentar (frivilligt)',
                  isDense: true,
                ),
              ),
              Row(
                children: [
                  if (_editing)
                    TextButton.icon(
                      key: const Key('live-sheet-delete'),
                      onPressed: () => Navigator.pop(
                        context,
                        _LiveEventResult(minute: _minute, delete: true),
                      ),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Ta bort'),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Avbryt'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const Key('live-sheet-save'),
                    onPressed: ready ? _save : null,
                    child: Text(_editing ? 'Spara' : 'Registrera'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
