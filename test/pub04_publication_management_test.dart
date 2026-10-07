import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/publication/editorial_models.dart';

void main() {
  test('PUB-04 management RPC is tenant and capability scoped', () {
    final sql = File(
      'supabase/migrations/20260828090546_pub04_publication_management_list.sql',
    ).readAsStringSync();
    expect(
      sql,
      contains(
        "internal.actor_has_capability(target_club_id,null,'publication.manage')",
      ),
    );
    expect(
      sql,
      contains(
        "internal.actor_has_capability(target_club_id,event_row.owning_team_id,'publication.manage')",
      ),
    );
    expect(sql, contains("event_row.state in('scheduled','completed')"));
    expect(sql, isNot(contains('event_row.description')));
    expect(sql, contains("'media_upload_status','not_configured'"));
    expect(sql, contains('revoke all on function'));
  });

  test('PUB-04 client uses only API RPCs and keeps media fail closed', () {
    final service = File(
      'lib/src/features/publication/editorial_services.dart',
    ).readAsStringSync();
    final surface = File(
      'lib/src/features/publication/publication_management_surface.dart',
    ).readAsStringSync();
    expect(service, contains("_query('get_publication_management'"));
    expect(service, contains("operation: 'configure_event_publication'"));
    expect(service, contains("operation: 'save_public_partner'"));
    // No direct table access; the only Storage use is the private,
    // policy-checked news image upload.
    expect(service, isNot(matches(RegExp(r"_client\s*\.from\("))));
    expect(
      RegExp(
        r"\.from\('([a-z-]+)'\)",
      ).allMatches(service).map((match) => match.group(1)).toSet(),
      {'public-media-source'},
    );
    expect(surface, contains('Partnerlogotyp kommer senare'));
    expect(
      surface,
      contains(
        'Titel, tid och typ publiceras. Plats och slutresultat kräver separata val.',
      ),
    );
  });

  test(
    'completed score keeps zero and remains private without an explicit choice',
    () {
      final input = <String, dynamic>{
        'id': 'event',
        'team_name': 'Laget',
        'title': 'Match',
        'event_type': 'match',
        'starts_at': '2026-09-25T12:00:00Z',
        'publication_state': 'published',
        'revision': 1,
        'result_available': true,
        'score_us': 0,
        'score_opponent': 2,
      };
      final item = PublicEventItem.fromJson(input);
      expect(item.resultAvailable, isTrue);
      expect(item.publishResult, isFalse);
      expect(item.scoreUs, 0);
      expect(item.scoreOpponent, 2);
      expect(
        PublicEventItem.fromJson({
          ...input,
          'publish_result': true,
        }).publishResult,
        isTrue,
      );
    },
  );
}
