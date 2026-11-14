import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Every club keeps an admin who can sign in: no way of leaving, being
// removed or erasing one's account may take the last Medlemmar och lag.
void main() {
  final migration = File(
    'supabase/migrations/20270316090000_club_keeps_an_admin.sql',
  ).readAsStringSync();

  test('grants, roles and account links are all guarded at commit', () {
    for (final table in [
      'capability_grants',
      'assignments',
      'person_account_links',
    ]) {
      expect(
        migration,
        contains('create constraint trigger ${table}_club_keeps_admin'),
      );
    }
    expect(migration, contains('deferrable initially deferred'));
    // An admin counts only with an account and a right without an end date.
    expect(migration, contains("link.state = 'active'"));
    expect(migration, contains('grant_row.ends_at is null)'));
    // The same code the app already explains.
    expect(
      migration,
      contains(
        "raise check_violation using message = 'last_memberships_manager'",
      ),
    );
  });

  test('the last admin cannot ask to have the account erased', () {
    expect(
      migration,
      contains(
        "then raise check_violation using message = ''last_memberships_manager''",
      ),
    );
  });

  test('the app explains the refusal where it can happen', () {
    final settings = File(
      'lib/src/features/account/profile_settings_surface.dart',
    ).readAsStringSync();
    final roster = File(
      'lib/src/features/roster/roster_surface.dart',
    ).readAsStringSync();
    expect(settings, contains('_isLastClubAdmin(error)'));
    expect(RegExp(r'_isLastClubAdmin\(error\)').allMatches(roster).length, 2);
  });
}
