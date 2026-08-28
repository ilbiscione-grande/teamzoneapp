import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('billing UI is web-only and capability gated', () {
    final source = [
      File('lib/src/features/billing/billing_surface.dart').readAsStringSync(),
      File('lib/src/app/product_shell.dart').readAsStringSync(),
      File('lib/src/app/product_routes.dart').readAsStringSync(),
    ].join('\n');
    expect(source, contains("can('club.billing.manage')"));
    expect(source, contains('if (!kIsWeb)'));
    expect(source, contains("path: '/billing'"));
    expect(source, contains("webOnlyWindowName: '_self'"));
    expect(
      source,
      contains('void didUpdateWidget(covariant _BillingSurface oldWidget)'),
    );
  });

  test('pricebook projection hides provider references', () {
    final sql = File(
      'supabase/migrations/20260816112100_s10a_pricebook_query.sql',
    ).readAsStringSync();
    expect(sql, contains("'club.billing.manage'"));
    expect(sql, isNot(contains('provider_price_ref')));
    expect(
      sql,
      contains('grant execute on function api.get_published_pricebook'),
    );
  });

  test('checkout CORS is exact and return route exists', () {
    final http = File(
      'supabase/functions/_shared/billing_http.ts',
    ).readAsStringSync();
    final checkout = File(
      'supabase/functions/billing-checkout/index.ts',
    ).readAsStringSync();
    expect(http, isNot(contains('access-control-allow-origin": "*')));
    expect(checkout, contains('request.method === "OPTIONS"'));
    expect(checkout, contains('/billing?result=success'));
  });

  test('pricebook API crosses the revoked internal boundary safely', () {
    final sql = File(
      'supabase/migrations/20260817100000_s10a_fix_pricebook_wrapper_execution.sql',
    ).readAsStringSync();
    expect(sql, contains('security definer'));
    expect(sql, contains("set search_path = ''"));
    expect(sql, contains('internal.get_published_pricebook_for_actor'));
    expect(sql, contains('revoke all on function api.get_published_pricebook'));
  });
}
