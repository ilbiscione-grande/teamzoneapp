import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final sql = File(
    'supabase/migrations/20260827125738_pub02_catalog_publication_model.sql',
  ).readAsStringSync();

  test(
    'publication status is explicit and private remains the safe default',
    () {
      expect(sql, contains("check(mode in ('private','listed','published'))"));
      expect(sql, contains("set mode='private' where mode='draft'"));
      expect(sql, contains("new_mode not in('private','listed','published')"));
      expect(sql, contains("club.verification_status='official'"));
    },
  );

  test(
    'publishing requires explicit capability and expiring field confirmation',
    () {
      expect(sql, contains("'publication.manage'"));
      expect(sql, contains('create table core.publication_confirmations'));
      expect(sql, contains("state text not null default 'active'"));
      expect(sql, contains("expires_at<=confirmed_at+interval '366 days'"));
      expect(sql, contains('internal.expire_publication_confirmations'));
      expect(sql, contains("'remove',null"));
    },
  );

  test('allowlisted projections fail closed for people and public clients', () {
    expect(
      sql,
      contains("array['name','age_class','profile_media','squad']::text[]"),
    );
    expect(sql, isNot(contains('public_api.person')));
    expect(
      sql,
      contains(
        'revoke all on table core.publication_confirmations from public,anon,authenticated',
      ),
    );
    expect(sql, contains("visibility in('listed','published') and official"));
    expect(sql, contains("page_limit not between 1 and 10"));
    expect(
      sql,
      contains("consume_public_rate_limit(ip_sha256_hex,'search',null)"),
    );
  });
}
