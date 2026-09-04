import 'package:supabase_flutter/supabase_flutter.dart';

const assistantBaseName = 'Min assistent';
const assistantNameMaxLength = 40;

class AssistantIdentityPreference {
  const AssistantIdentityPreference({this.customName, required this.revision});

  factory AssistantIdentityPreference.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Invalid assistant identity preference.');
    }
    final name = value['custom_name'];
    final revision = value['revision'];
    if (name != null && name is! String || revision is! num) {
      throw const FormatException('Invalid assistant identity preference.');
    }
    return AssistantIdentityPreference(
      customName: (name as String?)?.trim(),
      revision: revision.toInt(),
    );
  }

  final String? customName;
  final int revision;

  String get displayName =>
      customName?.isNotEmpty == true ? customName! : assistantBaseName;
}

String? validateAssistantName(String value) {
  final name = value.trim();
  if (name.isEmpty) return null;
  if (name.length > assistantNameMaxLength) {
    return 'Namnet får vara högst $assistantNameMaxLength tecken.';
  }
  if (RegExp(r'[\u0000-\u001f\u007f]').hasMatch(name)) {
    return 'Namnet innehåller tecken som inte kan användas.';
  }
  return null;
}

bool assistantNameNeedsIdentityWarning(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.isEmpty) return false;
  return RegExp(
    r'(^|\s)(teamzone|admin|support|läkare|lakare|fysioterapeut|physio|official|officiell)(\s|$)',
  ).hasMatch(normalized);
}

abstract interface class AssistantIdentityServices {
  Future<AssistantIdentityPreference> getPreference();
  Future<AssistantIdentityPreference> savePreference({
    required String? customName,
    required int expectedRevision,
    required String idempotencyKey,
  });
}

class UnconfiguredAssistantIdentityServices
    implements AssistantIdentityServices {
  const UnconfiguredAssistantIdentityServices();

  @override
  Future<AssistantIdentityPreference> getPreference() async =>
      const AssistantIdentityPreference(revision: 0);

  @override
  Future<AssistantIdentityPreference> savePreference({
    required String? customName,
    required int expectedRevision,
    required String idempotencyKey,
  }) => Future.error(StateError('Supabase is not configured.'));
}

class SupabaseAssistantIdentityServices implements AssistantIdentityServices {
  const SupabaseAssistantIdentityServices(this._client);

  final SupabaseClient _client;

  @override
  Future<AssistantIdentityPreference> getPreference() async =>
      AssistantIdentityPreference.fromJson(
        await _client.schema('api').rpc<Object?>('get_assistant_preference'),
      );

  @override
  Future<AssistantIdentityPreference> savePreference({
    required String? customName,
    required int expectedRevision,
    required String idempotencyKey,
  }) async => AssistantIdentityPreference.fromJson(
    await _client
        .schema('api')
        .rpc<Object?>(
          'set_assistant_name',
          params: {
            'custom_name': customName,
            'expected_revision': expectedRevision,
            'idempotency_key': idempotencyKey,
          },
        ),
  );
}
