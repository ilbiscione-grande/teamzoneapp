import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/messaging/messaging_models.dart';
import 'package:teamzone_app/src/shared/lists/app_list_controller.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260827142616_msg01_inbox_system_threads.sql',
  ).readAsStringSync();
  final surface = File(
    'lib/src/features/messaging/inbox_surface.dart',
  ).readAsStringSync();
  final relationFix = File(
    'supabase/migrations/20260828095553_msg01_reconcile_old_and_new_relations.sql',
  ).readAsStringSync();
  final services = File(
    'lib/src/features/messaging/messaging_services.dart',
  ).readAsStringSync();

  test('team and leader chats are deterministic and relation-derived', () {
    expect(migration, contains('primary key(team_id,thread_kind)'));
    expect(migration, contains("array['team','leader']"));
    expect(migration, contains("assignment.state='active'"));
    expect(migration, contains("link.state='active'"));
    expect(migration, contains('assignments_sync_system_threads'));
    expect(migration, contains('person_links_sync_system_threads'));
  });

  test('leader chat checks current capability on every access', () {
    expect(migration, contains("binding.thread_kind='leader'"));
    expect(
      migration,
      contains(
        "internal.actor_has_capability(binding.club_id,binding.team_id,'team.roster.view')",
      ),
    );
    expect(
      migration,
      contains('create or replace function internal.actor_can_access_thread'),
    );
  });

  test('moved links and grants reconcile both old and new teams', () {
    expect(relationFix, contains("tg_op<>'INSERT'"));
    expect(relationFix, contains('old.club_person_id'));
    expect(relationFix, contains("tg_op<>'DELETE'"));
    expect(relationFix, contains('new.club_person_id'));
    expect(relationFix, contains('old.assignment_id'));
    expect(relationFix, contains('new.assignment_id'));
    expect(relationFix, contains('array_agg(distinct assignment.team_id)'));
  });

  test('inbox has private invalidation and visible UX controls', () {
    expect(migration, contains("'message:inbox:'||participant.profile_id"));
    expect(migration, contains("='message:inbox:'||auth.uid()::text"));
    expect(services, contains('watchInboxInvalidations'));
    expect(surface, contains("('unread', 'Olästa')"));
    expect(surface, contains("('muted', 'Tystade')"));
    expect(surface, contains('_inboxTime(context, thread.lastAt)'));
    expect(surface, contains('Duration(milliseconds: 300)'));
    expect(surface, contains('persistentFooterButtons: compact'));
    expect(surface, contains("strings.feature('Fler inkorgsåtgärder')"));
    expect(surface, contains('onSelected: _handleCompactAction'));
    expect(surface, contains('_scheduleStaleResync'));
    expect(surface, contains('if (_data.state.isStale)'));
    expect(surface, contains('_clearStaleResync'));
  });

  test('closing a deep-linked thread cannot immediately reopen it', () {
    expect(surface, contains('String? _dismissedThreadId;'));
    expect(surface, contains('target == _dismissedThreadId'));
    expect(surface, contains('_dismissedThreadId = thread.id;'));
    expect(surface, contains('rootNavigator: true'));
    expect(surface, contains('widget.onNavigate(ProductRouteContract.inbox)'));
  });

  test('capability revoke fixture is isolated to the dedicated leader', () {
    final sql = File(
      'supabase/migrations/20260920175000_msg01_revoke_test_leader_roster_view.sql',
    ).readAsStringSync().toLowerCase();
    expect(sql, contains('coach.emilson+tzleader@gmail.com'));
    expect(sql, contains("team.name = 'thomas lag'"));
    expect(sql, contains("grant_row.capability = 'team.roster.view'"));
    expect(sql, contains('affected <> 1'));
    expect(sql, isNot(contains("grant_row.capability = 'team.roster.manage'")));
    expect(sql, isNot(contains("grant_row.capability = 'event.manage'")));
  });

  test('capability fixture restores the existing grant after verification', () {
    final sql = File(
      'supabase/migrations/20260920180500_msg01_restore_test_leader_roster_view.sql',
    ).readAsStringSync().toLowerCase();
    expect(sql, contains('coach.emilson+tzleader@gmail.com'));
    expect(sql, contains("grant_row.capability = 'team.roster.view'"));
    expect(sql, contains('set starts_at = now()'));
    expect(sql, contains('ends_at = null'));
    expect(sql, contains('grant_row.revision + 1'));
    expect(sql, isNot(contains('insert into core.capability_grants')));
  });

  test('shared list controller supports inbox search and unread filter', () {
    final now = DateTime.utc(2026, 8, 27);
    final controller = AppListController<MessageThreadSummary>(
      searchText: (thread) => '${thread.subject} ${thread.preview}',
    );
    controller.replaceItems([
      MessageThreadSummary(
        id: 'team',
        type: 'team',
        subject: 'P16 Lagchatt',
        preview: 'Träning i kväll',
        revision: 3,
        unreadCount: 2,
        muted: false,
        lastAt: now,
      ),
      MessageThreadSummary(
        id: 'leader',
        type: 'leader',
        subject: 'P16 Ledarchatt',
        revision: 1,
        unreadCount: 0,
        muted: true,
        lastAt: now.subtract(const Duration(hours: 1)),
      ),
    ]);
    controller.setQuery('träning');
    expect(controller.visibleItems.single.id, 'team');
    controller.setQuery('');
    controller.setFilter(
      key: 'unread',
      predicate: (thread) => thread.unreadCount > 0,
    );
    expect(controller.visibleItems.single.id, 'team');
    controller.dispose();
  });
}
