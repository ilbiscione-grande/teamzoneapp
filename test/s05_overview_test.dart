import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/overview/overview_models.dart';
import 'package:teamzone_app/src/shared/layout/app_breakpoints.dart';

void main() {
  test('central breakpoints classify phone tablet and desktop', () {
    expect(AppBreakpoints.classify(599), AppWindowClass.phone);
    expect(AppBreakpoints.classify(600), AppWindowClass.tablet);
    expect(AppBreakpoints.classify(1024), AppWindowClass.desktop);
  });

  test('versioned projection parses explicit contextual actions', () {
    final value = MainSurfacesProjection.fromJson({
      'schema_version': 1,
      'generated_at': '2026-08-08T09:00:00Z',
      'sync_cursor': 'djE=',
      'contexts': [
        {
          'context_id': 'ctx',
          'club_name': 'Club',
          'team_name': 'Team',
          'member_count': 2,
        },
      ],
      'actions': [
        {'action': 'create_event', 'route': '/calendar', 'context_id': 'ctx'},
      ],
      'home': {
        'upcoming_count': 1,
        'pending_callup_count': 1,
        'next_event': null,
      },
      'inbox': {'messages_available': false, 'pending_notification_count': 0},
      'statistics': {
        'present': 1,
        'late': 0,
        'partial': 0,
        'absent': 0,
        'unknown': 0,
      },
    });
    expect(value.schemaVersion, 1);
    expect(value.contexts.single.memberCount, 2);
    expect(value.actions.single.contextId, 'ctx');
    expect(value.statistics.total, 1);
    expect(value.asStale().isStale, isTrue);
  });

  test('unknown projection versions fail closed', () {
    expect(
      () => MainSurfacesProjection.fromJson({'schema_version': 2}),
      throwsFormatException,
    );
  });
}
