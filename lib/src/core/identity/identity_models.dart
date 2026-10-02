enum SessionStatus { unauthenticated, authenticated }

class TeamZoneProfile {
  const TeamZoneProfile({
    required this.id,
    required this.displayName,
    required this.locale,
  });

  final String id;
  final String displayName;
  final String locale;

  factory TeamZoneProfile.fromJson(Map<String, dynamic> json) {
    return TeamZoneProfile(
      id: json['id'] as String,
      displayName: (json['display_name'] as String?)?.trim() ?? '',
      locale: (json['locale'] as String?) ?? 'sv',
    );
  }
}

class TeamZoneContext {
  const TeamZoneContext({
    required this.id,
    required this.clubId,
    required this.clubName,
    required this.rolePackage,
    required this.capabilities,
    this.teamId,
    this.teamName,
    this.rolePackages = const [],
    this.aliasIds = const {},
    this.titles = const [],
    this.customTitles = const [],
    this.mainTitle,
  });

  /// The primary assignment. Role-bound server calls (homes, messaging) use it.
  final String id;
  final String clubId;
  final String clubName;
  final String? teamId;
  final String? teamName;

  /// The primary role; decides which home and views the context shows.
  final String rolePackage;

  /// Capabilities of every assignment merged into this context.
  final Set<String> capabilities;

  /// Every role held in this team when several assignments were merged.
  final List<String> rolePackages;

  /// Ids of the other assignments merged into this context, so a stored
  /// choice of any of them still selects it.
  final Set<String> aliasIds;

  /// Your own leader titles in this team (catalog keys and own labels),
  /// shown instead of the plain leader role.
  final List<String> titles;
  final List<String> customTitles;

  /// The title you chose as your main one, shown instead of the role.
  final String? mainTitle;

  TeamZoneContext withTitles(
    List<String> titles,
    List<String> customTitles, {
    String? mainTitle,
  }) => TeamZoneContext(
        id: id,
        clubId: clubId,
        clubName: clubName,
        teamId: teamId,
        teamName: teamName,
        rolePackage: rolePackage,
        capabilities: capabilities,
        rolePackages: rolePackages,
        aliasIds: aliasIds,
        titles: titles,
        customTitles: customTitles,
        mainTitle: mainTitle,
      );

  List<String> get roles => rolePackages.isEmpty ? [rolePackage] : rolePackages;

  bool can(String capability) => capabilities.contains(capability);

  bool matchesId(String? value) =>
      value != null && (value == id || aliasIds.contains(value));

  factory TeamZoneContext.fromJson(Map<String, dynamic> json) {
    final rawCapabilities = json['capabilities'];
    if (rawCapabilities is! List) {
      throw const FormatException('Context capabilities are missing.');
    }
    return TeamZoneContext(
      id: json['context_id'] as String,
      clubId: json['club_id'] as String,
      clubName: json['club_name'] as String,
      teamId: json['team_id'] as String?,
      teamName: json['team_name'] as String?,
      rolePackage: json['role_package'] as String,
      capabilities: rawCapabilities.whereType<String>().toSet(),
    );
  }
}

/// Roles you hold yourself in one team (leader, club functionary, player)
/// form one team context with several roles, not one context per
/// assignment. The primary role is the most capable one; capabilities are
/// combined, as the server already checks them across all your assignments.
/// Guardian contexts stay separate: they show a child's team, not your own
/// role there. Order follows the first assignment of each team.
List<TeamZoneContext> mergeTeamContexts(List<TeamZoneContext> contexts) {
  const primaryOrder = ['leader', 'club_functionary', 'player'];
  final groups = <String, List<TeamZoneContext>>{};
  for (final context in contexts) {
    final mergeable =
        context.teamId != null && primaryOrder.contains(context.rolePackage);
    final key = mergeable
        ? 'team:${context.clubId}:${context.teamId}'
        : 'own:${context.id}';
    groups.putIfAbsent(key, () => []).add(context);
  }
  return [
    for (final group in groups.values)
      if (group.length == 1) group.single else _mergeTeamGroup(group),
  ];
}

TeamZoneContext _mergeTeamGroup(List<TeamZoneContext> group) {
  const primaryOrder = ['leader', 'club_functionary', 'player'];
  const displayOrder = ['club_functionary', 'leader', 'player'];
  final sorted = [...group]
    ..sort(
      (a, b) => primaryOrder
          .indexOf(a.rolePackage)
          .compareTo(primaryOrder.indexOf(b.rolePackage)),
    );
  final primary = sorted.first;
  final roles = {for (final item in group) item.rolePackage}.toList()
    ..sort(
      (a, b) => displayOrder.indexOf(a).compareTo(displayOrder.indexOf(b)),
    );
  return TeamZoneContext(
    id: primary.id,
    clubId: primary.clubId,
    clubName: primary.clubName,
    teamId: primary.teamId,
    teamName: primary.teamName,
    rolePackage: primary.rolePackage,
    capabilities: {for (final item in group) ...item.capabilities},
    rolePackages: roles,
    aliasIds: {
      for (final item in group)
        if (item.id != primary.id) item.id,
    },
  );
}
