import 'package:supabase_flutter/supabase_flutter.dart';

/// One of the app's modules (or the Tacticsboard link) and the club's
/// access to it: `write`, `read_only` after a purchase ended, or `none`.
class ModuleInfo {
  const ModuleInfo({
    required this.key,
    required this.title,
    required this.description,
    required this.beta,
    required this.access,
  });

  factory ModuleInfo.fromJson(Map<String, dynamic> json) => ModuleInfo(
    key: json['key'] as String? ?? '',
    title: json['title'] as String? ?? '',
    description: json['description'] as String? ?? '',
    beta: json['beta'] == true,
    access: json['access'] as String? ?? 'none',
  );

  final String key;
  final String title;
  final String description;
  final bool beta;
  final String access;

  bool get open => access == 'write' || access == 'read_only';
}

/// The level an area of the app shows for a team (decision package 11):
/// the built-in version, the club's module, or Tacticsboard.
enum ModuleLevel { base, module, tacticsboard }

/// A team's modules and the level of each area (`lineup`,
/// `match_preparation`, `match_followup`, `team_development`, `training`,
/// `player_development`). An unknown area is always the built-in version.
class TeamModules {
  const TeamModules({this.modules = const [], this.levels = const {}});

  factory TeamModules.fromJson(Map<String, dynamic> json) => TeamModules(
    modules: [
      for (final row in (json['modules'] as List? ?? const []).whereType<Map>())
        ModuleInfo.fromJson(Map<String, dynamic>.from(row)),
    ],
    levels: {
      for (final entry in (json['levels'] as Map? ?? const {}).entries)
        entry.key as String: switch (entry.value) {
          'tacticsboard' => ModuleLevel.tacticsboard,
          'module' => ModuleLevel.module,
          _ => ModuleLevel.base,
        },
    },
  );

  final List<ModuleInfo> modules;
  final Map<String, ModuleLevel> levels;

  ModuleLevel level(String area) => levels[area] ?? ModuleLevel.base;
}

abstract interface class ModuleServices {
  Future<TeamModules> getTeamModules({required String teamId});
}

/// Without a backend every area is the built-in version.
class UnconfiguredModuleServices implements ModuleServices {
  const UnconfiguredModuleServices();
  @override
  Future<TeamModules> getTeamModules({required String teamId}) =>
      Future.value(const TeamModules());
}

class SupabaseModuleServices implements ModuleServices {
  SupabaseModuleServices(this._client);
  final SupabaseClient _client;

  @override
  Future<TeamModules> getTeamModules({required String teamId}) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>('get_team_modules', params: {'target_team_id': teamId});
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid modules response.');
    }
    return TeamModules.fromJson(value);
  }
}
