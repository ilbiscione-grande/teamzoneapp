part of '../../app/teamzone_app.dart';

/// What an attribute means and the positions it matters most for, in a
/// sheet from the Egenskaper tab.
Future<void> _showAttributeHelp(
  BuildContext context,
  PlayerAttributeOption option,
) {
  final strings = AppStrings.of(context);
  final swedish = strings.isSwedish;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useRootNavigator: true,
    builder: (sheet) {
      final theme = Theme.of(sheet);
      final palette = AppPalette.of(sheet);
      return SafeArea(
        child: Padding(
          key: ValueKey('attribute-help-sheet-${option.key}'),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                playerAttributeLabel(option, swedish),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(option.about(swedish), style: theme.textTheme.bodyLarge),
              if (option.positions.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  _attrText(sheet, 'Viktigast för', 'Matters most for'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: palette.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final position in option.positions)
                      Chip(
                        label: Text(_positionLabel(strings, position)),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}
