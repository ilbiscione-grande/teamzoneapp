part of '../../app/teamzone_app.dart';

/// The squad list's order: by position group (goalkeepers, defenders,
/// midfielders, forwards; a handball team has its own), A–Ö in each group.

const _positionGroupLabels = <String, String>{
  'goalkeeper': 'Målvakter',
  'defender': 'Försvarare',
  'midfielder': 'Mittfältare',
  'forward': 'Anfallare',
  'hb_backcourt': 'Nior',
  'hb_wing': 'Kanter',
  'hb_pivot': 'Linjespelare',
};

/// A player whose only positions are the team's own labels.
const _ownPositionGroup = 'own';

/// The squad's groups in the order they are shown; null is without position.
final _positionGroupOrder = <String?>[
  ..._positionGroupLabels.keys,
  _ownPositionGroup,
  null,
];

/// The group of the main position, else of the first position that has one.
String? _positionGroup(TeamRole? role, List<SportPosition> catalog) {
  if (role == null) return null;
  for (final key in [?role.mainPosition, ...role.positions]) {
    final entry = catalog.where((entry) => entry.key == key).firstOrNull;
    final general = entry?.parent ?? key;
    if (_positionGroupLabels.containsKey(general)) return general;
  }
  return role.customPositions.isEmpty ? null : _ownPositionGroup;
}

String _positionGroupLabel(AppStrings strings, String? group) =>
    strings.feature(
      group == null
          ? 'Utan position'
          : _positionGroupLabels[group] ?? 'Övriga positioner',
    );

/// Names in Swedish order: å, ä and ö after z, in that order.
int _compareSwedishNames(String a, String b) {
  String key(String value) => value
      .toLowerCase()
      .replaceAll('é', 'e')
      .replaceAll('å', '{a')
      .replaceAll('ä', '{b')
      .replaceAll('ö', '{c');
  return key(a).compareTo(key(b));
}

class _RosterPositionHeader extends StatelessWidget {
  const _RosterPositionHeader({required this.group, required this.count});
  final String? group;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: ValueKey('roster-group-${group ?? 'none'}'),
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Semantics(
        header: true,
        child: Text(
          '${_positionGroupLabel(AppStrings.of(context), group)} ($count)',
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
