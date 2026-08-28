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

  test('inbox has private invalidation and visible UX controls', () {
    expect(migration, contains("'message:inbox:'||participant.profile_id"));
    expect(migration, contains("='message:inbox:'||auth.uid()::text"));
    expect(services, contains('watchInboxInvalidations'));
    expect(surface, contains("('unread', 'Olästa')"));
    expect(surface, contains("('muted', 'Tystade')"));
    expect(surface, contains('_inboxTime(context, thread.lastAt)'));
    expect(surface, contains('Duration(milliseconds: 300)'));
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
