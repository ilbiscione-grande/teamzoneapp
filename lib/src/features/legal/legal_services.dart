import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:teamzone_app/src/features/legal/legal_models.dart';

abstract interface class LegalServices {
  Future<LegalStatus> getStatus();
  Future<void> acceptCurrent({
    required String termsVersion,
    required String privacyVersion,
    required bool marketingOptIn,
    required String idempotencyKey,
  });
  Future<void> setMarketingPreference({
    required bool marketingOptIn,
    required String idempotencyKey,
  });
}

class UnconfiguredLegalServices implements LegalServices {
  const UnconfiguredLegalServices();
  @override
  Future<LegalStatus> getStatus() async => const LegalStatus(
    termsVersion: 'unconfigured',
    termsUrl: 'https://teamzoneapp.se/villkor',
    termsAccepted: true,
    privacyVersion: 'unconfigured',
    privacyUrl: 'https://teamzoneapp.se/integritet',
    privacyAccepted: true,
    marketingOptIn: false,
  );
  @override
  Future<void> acceptCurrent({
    required String termsVersion,
    required String privacyVersion,
    required bool marketingOptIn,
    required String idempotencyKey,
  }) => Future.error(StateError('Supabase is not configured.'));
  @override
  Future<void> setMarketingPreference({
    required bool marketingOptIn,
    required String idempotencyKey,
  }) => Future.error(StateError('Supabase is not configured.'));
}

class SupabaseLegalServices implements LegalServices {
  const SupabaseLegalServices(this._client);
  final SupabaseClient _client;

  @override
  Future<LegalStatus> getStatus() async {
    final value = await _client.schema('api').rpc<Object?>('get_legal_status');
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid legal status.');
    }
    return LegalStatus.fromJson(value);
  }

  @override
  Future<void> acceptCurrent({
    required String termsVersion,
    required String privacyVersion,
    required bool marketingOptIn,
    required String idempotencyKey,
  }) => _client
      .schema('api')
      .rpc<Object?>(
        'accept_current_legal',
        params: {
          'terms_version': termsVersion,
          'privacy_version': privacyVersion,
          'marketing_opt_in': marketingOptIn,
          'idempotency_key': idempotencyKey,
        },
      );

  @override
  Future<void> setMarketingPreference({
    required bool marketingOptIn,
    required String idempotencyKey,
  }) => _client
      .schema('api')
      .rpc<Object?>(
        'set_marketing_preference',
        params: {
          'marketing_opt_in': marketingOptIn,
          'idempotency_key': idempotencyKey,
        },
      );
}
