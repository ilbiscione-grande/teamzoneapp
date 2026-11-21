part of '../../app/teamzone_app.dart';

/// Which foot the player prefers, on the Egenskaper tab: Vänster, Höger or
/// Båda, and for Båda whether they are equally good or one is better (the
/// other then decent). Tapping the chosen foot again takes it away.
class _PlayerFootCard extends StatelessWidget {
  const _PlayerFootCard({required this.foot, required this.onChanged});
  final String? foot;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final both = foot?.startsWith('both') ?? false;
    final main = both ? 'both' : foot;

    Widget choice(String value, String label, {Key? key}) {
      final selected = value == main || value == foot;
      return ChoiceChip(
        key: key ?? ValueKey('foot-$value'),
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        selectedColor: palette.accent.withValues(alpha: .2),
        labelStyle: selected ? TextStyle(color: palette.accent) : null,
        side: BorderSide(
          color: selected
              ? palette.accent
              : palette.muted.withValues(alpha: .4),
        ),
        visualDensity: VisualDensity.compact,
        onSelected: (on) => onChanged(
          !on
              ? (value.startsWith('both_') ? 'both_equal' : null)
              : value == 'both'
              ? 'both_equal'
              : value,
        ),
      );
    }

    return Card(
      key: const ValueKey('player-foot'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _attrText(context, 'Fot', 'Foot'),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                choice('left', _attrText(context, 'Vänster', 'Left')),
                choice('right', _attrText(context, 'Höger', 'Right')),
                choice('both', _attrText(context, 'Båda', 'Both')),
              ],
            ),
            if (both) ...[
              const SizedBox(height: 10),
              Text(
                _attrText(context, 'Hur bra med båda?', 'How good with both?'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: palette.muted,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  choice(
                    'both_equal',
                    _attrText(context, 'Lika bra', 'Equally good'),
                  ),
                  choice(
                    'both_left',
                    _attrText(
                      context,
                      'Bättre med vänster',
                      'Better with the left',
                    ),
                  ),
                  choice(
                    'both_right',
                    _attrText(
                      context,
                      'Bättre med höger',
                      'Better with the right',
                    ),
                  ),
                ],
              ),
              if (foot == 'both_left' || foot == 'both_right')
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _attrText(
                      context,
                      'Hyfsad med den svagare foten.',
                      'Decent with the weaker foot.',
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: palette.muted,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
