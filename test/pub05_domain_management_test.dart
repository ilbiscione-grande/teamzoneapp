import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PUB-05 domain projection is capability and tenant scoped', () {
    final sql = File(
      'supabase/migrations/20260828093026_pub05_domain_management_projection.sql',
    ).readAsStringSync();
    expect(
      sql,
      contains(
        "internal.actor_has_capability(target_club_id,null,'publication.manage')",
      ),
    );
    expect(sql, contains('where domain.club_id=target_club_id'));
    expect(
      sql,
      contains(
        "'teamzone_subdomain_available',runtime.wildcard_dns_ready and runtime.wildcard_tls_ready and runtime.automatic_tenant_routing_ready",
      ),
    );
    expect(sql, contains('revoke all on function'));
  });
  test(
    'publication commands are explicitly allowed by the measured gateway',
    () {
      final gateway = File(
        'supabase/functions/critical-flow-command/index.ts',
      ).readAsStringSync();
      for (final operation in [
        'save_editorial_article',
        'transition_editorial_article',
        'configure_event_publication',
        'save_public_partner',
        'request_publication_domain',
        'set_canonical_publication_domain',
      ]) {
        expect(gateway, contains('$operation: "critical_commands"'));
      }
    },
  );
  test('domain UI keeps wildcard and activation gates visible', () {
    final surface = File(
      'lib/src/features/publication/domain_management_surface.dart',
    ).readAsStringSync();
    expect(surface, contains('Premiumsubdomän kommer senare'));
    expect(surface, contains('betalningsgodkännande, DNS-verifiering'));
    expect(surface, contains("kind: 'custom'"));
    expect(surface, isNot(contains("kind: 'teamzone_subdomain'")));
  });
}
