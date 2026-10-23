import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/workspaces/module_services.dart';

void main() {
  group('module foundation (decision package 11)', () {
    test('reads the modules and each area\'s level', () {
      final modules = TeamModules.fromJson({
        'modules': [
          {
            'key': 'module.match_workspace',
            'title': 'Match',
            'description': 'Matchplan',
            'beta': true,
            'access': 'write',
          },
          {
            'key': 'module.training',
            'title': 'Träning',
            'description': 'Pass',
            'beta': false,
            'access': 'read_only',
          },
          {'key': 'module.player_development', 'access': 'none'},
        ],
        'levels': {
          'lineup': 'tacticsboard',
          'match_followup': 'module',
          'training': 'base',
        },
      });
      expect(modules.modules.map((module) => module.key), [
        'module.match_workspace',
        'module.training',
        'module.player_development',
      ]);
      expect(modules.modules.map((module) => module.open), [true, true, false]);
      expect(modules.level('lineup'), ModuleLevel.tacticsboard);
      expect(modules.level('match_followup'), ModuleLevel.module);
      expect(modules.level('training'), ModuleLevel.base);
      expect(
        modules.level('unknown_area'),
        ModuleLevel.base,
        reason: 'an area the app does not know is always the built-in one',
      );
    });

    test('without a backend everything is the built-in version', () async {
      final modules = await const UnconfiguredModuleServices().getTeamModules(
        teamId: 'team',
      );
      expect(modules.modules, isEmpty);
      expect(modules.level('lineup'), ModuleLevel.base);
    });
  });
}
