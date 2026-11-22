import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/features/assistant_coach/assistant_inbox_tasks.dart';
import 'package:teamzone_app/src/features/assistant_coach/assistant_task_preferences.dart';
import 'package:teamzone_app/src/features/roster/roster_models.dart';

TeamZoneContext _team(String id, {Set<String> caps = const {}}) =>
    TeamZoneContext(
      id: 'context-$id',
      clubId: 'club',
      clubName: 'Klubben',
      teamId: 'team-$id',
      teamName: 'Lag $id',
      rolePackage: 'leader',
      capabilities: caps,
    );

IntakeSubmission _sent(String id, String? teamId) => IntakeSubmission(
  id: id,
  fullName: 'Person $id',
  phone: '070-0000000',
  email: '$id@example.test',
  birthDate: DateTime(2012, 1, 1),
  streetAddress: 'Gatan 1',
  postalCode: '111 11',
  city: 'Staden',
  createdAt: DateTime(2026, 11, 22),
  teamId: teamId,
);

void main() {
  final managed = _team('a', caps: {'team.roster.manage'});
  final readOnly = _team('b');
  final overview = IntakeOverview(
    canManageClub: false,
    teams: const [],
    forms: const [],
    submissions: [
      _sent('1', 'team-a'),
      _sent('2', 'team-a'),
      _sent('3', 'team-b'),
      // Sent to the club, not a team: the inbox handles it.
      _sent('4', null),
    ],
  );

  test('new contact details give one task per team you manage', () async {
    final tasks = await loadAssistantIntakeTasks(
      contexts: [managed, readOnly],
      activeContext: managed,
      loadIntake: (_) async => overview,
      preferences: const AssistantTaskPreferences(),
    );
    expect(tasks, hasLength(1));
    final task = tasks.single;
    expect(task.task.kind, 'team_contact_details');
    expect(task.task.count, 2);
    expect(task.context.id, 'context-a');
    expect(Uri.parse(task.task.route).queryParameters, {
      'action': 'intake',
      'context': 'context-a',
    });
  });

  test('hidden in the settings or failing to load gives no task', () async {
    expect(
      await loadAssistantIntakeTasks(
        contexts: [managed],
        activeContext: managed,
        loadIntake: (_) async => overview,
        preferences: const AssistantTaskPreferences(
          hiddenKinds: {'team_contact_details'},
        ),
      ),
      isEmpty,
    );
    expect(
      await loadAssistantIntakeTasks(
        contexts: [managed],
        activeContext: managed,
        loadIntake: (_) async => throw StateError('offline'),
        preferences: const AssistantTaskPreferences(),
      ),
      isEmpty,
    );
  });
}
