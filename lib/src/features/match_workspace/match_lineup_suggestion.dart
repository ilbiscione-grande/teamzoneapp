part of '../../app/teamzone_app.dart';

/// Why each player was suggested where: under the pitch after Föreslå, one
/// row per place with the position fit and the attributes that counted.
class _SuggestionReasonsCard extends StatelessWidget {
  const _SuggestionReasonsCard({
    required this.places,
    required this.slots,
    required this.people,
    required this.customLabels,
    required this.onClose,
  });
  final List<SuggestedPlace> places;
  final List<FormationSlot> slots;
  final Map<String, LineupPlayer> people;
  final Map<String, String> customLabels;
  final VoidCallback onClose;

  String _attribute(String key, bool swedish) =>
      customLabels[key] ??
      playerAttributeLabel(PlayerAttributeOption(key: key), swedish);

  @override
  Widget build(BuildContext context) {
    final swedish = AppStrings.of(context).isSwedish;
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    String why(SuggestedPlace place) => [
      switch (place.positionFit) {
        'main' => _attrText(context, 'Huvudposition', 'Main position'),
        'other' => _attrText(context, 'Kan positionen', 'Plays the position'),
        'group' => _attrText(context, 'Rätt lagdel', 'Right part of the team'),
        _ => null,
      },
      for (final key in place.strengths) '+ ${_attribute(key, swedish)}',
      for (final key in place.development) '− ${_attribute(key, swedish)}',
      ?_footReason(context, place),
    ].whereType<String>().join(' · ');

    return Card(
      key: const Key('lineup-suggestion-reasons'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, size: 18, color: palette.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _attrText(
                      context,
                      'Därför föreslås de',
                      'Why these players',
                    ),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: _attrText(context, 'Dölj', 'Hide'),
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
            for (final slot in slots)
              if (places.where((p) => p.code == slot.code).firstOrNull
                  case final place?)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 40,
                        child: Text(
                          slot.label,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            text:
                                people[place.personId]?.name ??
                                _attrText(
                                  context,
                                  'Ingen spelare',
                                  'No player',
                                ),
                            children: [
                              if (place.personId != null &&
                                  why(place).isNotEmpty)
                                TextSpan(
                                  text: '\n${why(place)}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: palette.muted,
                                  ),
                                ),
                            ],
                          ),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// The foot in a suggestion's reasons: "+ Vänsterfot" when it fits, "− Fel
/// fot" when it does not; nothing when the place asks for none.
String? _footReason(BuildContext context, SuggestedPlace place) {
  final left = place.foot == 'left';
  return switch (place.footFit) {
    'good' || 'both' =>
      left
          ? _attrText(context, '+ Vänsterfot', '+ Left foot')
          : _attrText(context, '+ Högerfot', '+ Right foot'),
    'weaker' =>
      left
          ? _attrText(context, 'Hyfsad vänsterfot', 'Decent left foot')
          : _attrText(context, 'Hyfsad högerfot', 'Decent right foot'),
    'wrong' => _attrText(context, '− Fel fot', '− Wrong foot'),
    _ => null,
  };
}
