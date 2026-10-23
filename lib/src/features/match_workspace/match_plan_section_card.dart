part of '../../app/teamzone_app.dart';

/// One part of the match plan: its text with ready openings to start from
/// and whether the players see it; read-only, it shows only when written.
class _PlanSectionCard extends StatelessWidget {
  const _PlanSectionCard({
    required this.area,
    required this.title,
    required this.controller,
    required this.visible,
    required this.edit,
    required this.onEdited,
    required this.onVisible,
  });
  final String area, title;
  final TextEditingController controller;
  final bool visible, edit;
  final VoidCallback onEdited;
  final ValueChanged<bool> onVisible;

  static const _openings = {
    'tactics': ['Försvar: ', 'Anfall: ', 'Omställning: ', 'Press: '],
    'set_pieces': [
      'Hörnor för: ',
      'Hörnor mot: ',
      'Frisparkar: ',
      'Inkast: ',
      'Straffar: ',
    ],
    'opponent': ['Formation: ', 'Styrkor: ', 'Svagheter: ', 'Nyckelspelare: '],
  };

  void _open(String opening) {
    final text = controller.text;
    controller.text =
        '${text.isEmpty || text.endsWith('\n') ? text : '$text\n'}$opening';
    onEdited();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    if (!edit && controller.text.trim().isEmpty) return const SizedBox.shrink();
    return Card(
      key: Key('match-plan-$area'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              strings.feature(title),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            if (!edit)
              Text(controller.text)
            else ...[
              TextField(
                controller: controller,
                minLines: 3,
                maxLines: 12,
                maxLength: 8000,
                onChanged: (_) => onEdited(),
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
              Wrap(
                spacing: 6,
                children: [
                  for (final opening in _openings[area] ?? const <String>[])
                    ActionChip(
                      label: Text(strings.feature(opening.trim())),
                      onPressed: () => _open(opening),
                    ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: visible,
                onChanged: onVisible,
                title: Text(strings.feature('Visa för spelarna')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
