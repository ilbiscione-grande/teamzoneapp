part of '../../app/teamzone_app.dart';

/// One counter in Live: a KPI goal from Förberedelse or an own button.
typedef _LiveCounter = ({
  String key,
  String label,
  num? value,
  String? goal,
  int pending,

  /// Counted with −/+; otherwise the value is entered (a KPI goal that is
  /// not a count).
  bool counted,
});

/// The counters below the event buttons: KPI goals and the team's own
/// buttons, as the old match mode's counters, each with −/+ (or a tap to
/// enter a value that is not counted).
class _LiveCounters extends StatelessWidget {
  const _LiveCounters({
    required this.counters,
    required this.onDelta,
    required this.onEnter,
  });
  final List<_LiveCounter> counters;
  final void Function(String key, int delta)? onDelta;
  final ValueChanged<String>? onEnter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('live-counters'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Räknare', style: theme.textTheme.titleSmall),
            for (final counter in counters)
              ListTile(
                key: Key('live-counter-${counter.key}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(counter.label),
                subtitle: counter.goal == null ? null : Text(counter.goal!),
                onTap: !counter.counted && onEnter != null
                    ? () => onEnter!(counter.key)
                    : null,
                trailing: counter.counted
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Minska ${counter.label}',
                            onPressed:
                                onDelta == null ||
                                    (counter.value ?? 0) + counter.pending <= 0
                                ? null
                                : () => onDelta!(counter.key, -1),
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          SizedBox(
                            width: 32,
                            child: Text(
                              '${(counter.value ?? 0) + counter.pending}',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: counter.pending == 0
                                    ? null
                                    : theme.colorScheme.outline,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Öka ${counter.label}',
                            onPressed: onDelta == null
                                ? null
                                : () => onDelta!(counter.key, 1),
                            icon: const Icon(Icons.add_circle),
                          ),
                        ],
                      )
                    : Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Text(
                          counter.value == null ? 'Fyll i' : '${counter.value}',
                        ),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Min vy: which buttons Live shows this leader, as in the old app. Returns
/// the keys to show, or null (inside a record) for everything.
class _MyViewDialog extends StatefulWidget {
  const _MyViewDialog({required this.options, required this.initial});

  /// Groups of (key, label) under a heading.
  final List<(String, List<(String, String)>)> options;
  final Set<String>? initial;

  @override
  State<_MyViewDialog> createState() => _MyViewDialogState();
}

class _MyViewDialogState extends State<_MyViewDialog> {
  late final Set<String> _shown =
      widget.initial ??
      {
        for (final (_, items) in widget.options)
          for (final (key, _) in items) key,
      };

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Min vy'),
    content: SizedBox(
      width: 380,
      child: ListView(
        shrinkWrap: true,
        children: [
          const Text(
            'Välj vilka knappar du vill se under matchen. Valet gäller bara dig.',
          ),
          for (final (heading, items) in widget.options)
            if (items.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Text(
                  heading,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              for (final (key, label) in items)
                CheckboxListTile(
                  key: Key('my-view-$key'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: _shown.contains(key),
                  title: Text(label),
                  onChanged: (value) => setState(
                    () => value == true ? _shown.add(key) : _shown.remove(key),
                  ),
                ),
            ],
        ],
      ),
    ),
    actions: [
      TextButton(
        key: const Key('my-view-all'),
        onPressed: () => Navigator.pop(context, (null,)),
        child: const Text('Visa alla'),
      ),
      FilledButton(
        key: const Key('my-view-save'),
        onPressed: () => Navigator.pop(context, (_shown,)),
        child: const Text('Spara'),
      ),
    ],
  );
}

/// The team's own buttons: add, rename, remove; used in every match.
class _OwnButtonsDialog extends StatefulWidget {
  const _OwnButtonsDialog({required this.initial});
  final List<MatchButton> initial;

  @override
  State<_OwnButtonsDialog> createState() => _OwnButtonsDialogState();
}

class _OwnButtonsDialogState extends State<_OwnButtonsDialog> {
  late final List<(String, TextEditingController)> _rows = [
    for (final button in widget.initial)
      (button.id, TextEditingController(text: button.label)),
  ];

  @override
  void dispose() {
    for (final (_, controller) in _rows) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = _rows.every(
      (row) => row.$2.text.trim().isNotEmpty && row.$2.text.trim().length <= 30,
    );
    return AlertDialog(
      title: const Text('Egna knappar'),
      content: SizedBox(
        width: 380,
        child: ListView(
          shrinkWrap: true,
          children: [
            const Text(
              'Räknare för det ni vill följa i varje match, t.ex. brytningar '
              'eller inlägg. De gäller hela laget.',
            ),
            const SizedBox(height: 8),
            for (final (index, (id, controller)) in _rows.indexed)
              Row(
                key: Key('own-button-$id'),
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      maxLength: 30,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        isDense: true,
                        counterText: '',
                        hintText: 'Namn på knappen',
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Ta bort',
                    onPressed: () => setState(() {
                      _rows.removeAt(index).$2.dispose();
                    }),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            if (_rows.length < 12)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('own-button-add'),
                  onPressed: () => setState(
                    () => _rows.add((_newUuid(), TextEditingController())),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Lägg till knapp'),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Avbryt'),
        ),
        FilledButton(
          key: const Key('own-buttons-save'),
          onPressed: valid
              ? () => Navigator.pop(context, [
                  for (final (id, controller) in _rows)
                    MatchButton(id: id, label: controller.text.trim()),
                ])
              : null,
          child: const Text('Spara'),
        ),
      ],
    );
  }
}
