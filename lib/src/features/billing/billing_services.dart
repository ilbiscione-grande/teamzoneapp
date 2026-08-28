import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:teamzone_app/src/features/billing/billing_models.dart';

abstract interface class BillingServices {
  Future<BillingOverview> getPublishedPricebook({required String clubId});
  Future<Uri> createCheckout({
    required String clubId,
    required String planKey,
    required String interval,
    required String idempotencyKey,
  });
}

class UnconfiguredBillingServices implements BillingServices {
  const UnconfiguredBillingServices();
  StateError get _error => StateError('Billing backend is not configured.');
  @override
  Future<Uri> createCheckout({
    required String clubId,
    required String planKey,
    required String interval,
    required String idempotencyKey,
  }) => Future.error(_error);
  @override
  Future<BillingOverview> getPublishedPricebook({required String clubId}) =>
      Future.error(_error);
}

class SupabaseBillingServices implements BillingServices {
  SupabaseBillingServices(this._client);
  final SupabaseClient _client;

  @override
  Future<BillingOverview> getPublishedPricebook({
    required String clubId,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'get_published_pricebook',
          params: {'target_club_id': clubId},
        );
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid billing response.');
    }
    return BillingOverview.fromJson(value);
  }

  @override
  Future<Uri> createCheckout({
    required String clubId,
    required String planKey,
    required String interval,
    required String idempotencyKey,
  }) async {
    final response = await _client.functions.invoke(
      'billing-checkout',
      body: {
        'clubId': clubId,
        'planKey': planKey,
        'interval': interval,
        'idempotencyKey': idempotencyKey,
      },
    );
    final data = response.data;
    final uri = data is Map
        ? Uri.tryParse(data['checkoutUrl'] as String? ?? '')
        : null;
    if (response.status != 200 ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'checkout.stripe.com') {
      throw StateError('Checkout unavailable.');
    }
    return uri;
  }
}
