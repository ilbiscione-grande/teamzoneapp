import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

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
    expect(service, isNot(contains(".from('")));
    expect(surface, contains('Partnerlogotyp kommer senare'));
    expect(
      surface,
      contains('Endast titel, tid, typ och uttryckligt vald plats publiceras.'),
    );
  });
}
