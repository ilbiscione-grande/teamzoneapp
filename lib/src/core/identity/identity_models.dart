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
  });

  final String id;
  final String clubId;
  final String clubName;
  final String? teamId;
  final String? teamName;
  final String rolePackage;
  final Set<String> capabilities;

  bool can(String capability) => capabilities.contains(capability);

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
