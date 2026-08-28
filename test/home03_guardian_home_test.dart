import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260827193735_home03_guardian_home.sql',
  ).readAsStringSync();
  final surface = File(
    'lib/src/features/overview/overview_surface.dart',
  ).readAsStringSync();

  test('guardian and selected child require active relation and team', () {
    expect(migration, contains("context_row.role_package<>'guardian'"));
    expect(
      migration,
      contains('relation.guardian_person_id=guardian_person_id'),
    );
    expect(migration, contains("relation.state='active'"));
    expect(migration, contains('child.id=target_child_person_id'));
    expect(migration, contains('assignment.club_person_id=child.id'));
    expect(migration, contains('assignment.team_id=context_row.team_id'));
  });

  test(
    'projection contains only selected child data and visible acting-as',
    () {
      expect(migration, contains('callup.club_person_id=selected_child_id'));
      expect(migration, contains('selected_child_id acting_as_person_id'));
      expect(migration, contains("'guardian'::text response_role"));
      expect(surface, contains("labelText: 'Visa för barn'"));
      expect(surface, contains("'Du agerar för \${child.displayName}'"));
      expect(
        surface,
        contains("'Svarar som vårdnadshavare för \${widget.actingAsName}'"),
      );
    },
  );

  test('acting-as survives the callup mutation', () {
    expect(surface, contains('actingAsPersonId: callup.actingAsPersonId'));
    expect(surface, contains('expectedRevision: callup.revision'));
    expect(surface, contains('declineReasonCode: reasonCode'));
    expect(surface, contains('declineReasonText: reasonText'));
  });

  test('child event and messages stay in selected team context', () {
    expect(migration, contains('team_relation.team_id=context_row.team_id'));
    expect(migration, contains('scope.team_id=context_row.team_id'));
    expect(migration, contains("'child_callups'"));
    expect(migration, contains("'unread_message_count'"));
  });
}
