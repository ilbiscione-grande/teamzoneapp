import 'package:supabase_flutter/supabase_flutter.dart';

const assistantBaseName = 'Min assistent';
const assistantNameMaxLength = 40;
const assistantAvatarKeys = <String?>[
  null,
  'woman',
  'woman_2',
  'woman_3',
  'man',
  'man_2',
  'man_3',
];

String? assistantAvatarAsset(String? key) => switch (key) {
  'woman' => 'assets/images/assistant/woman.png',
  'woman_2' => 'assets/images/assistant/woman_2.png',
  'woman_3' => 'assets/images/assistant/woman_3.png',
  'man' => 'assets/images/assistant/man.png',
  'man_2' => 'assets/images/assistant/man_2.png',
  'man_3' => 'assets/images/assistant/man_3.png',
  _ => null,
};

class AssistantIdentityPreference {
  const AssistantIdentityPreference({
    this.customName,
    this.avatarKey,
    required this.revision,
  });

  factory AssistantIdentityPreference.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Invalid assistant identity preference.');
    }
    final name = value['custom_name'];
    final avatarKey = value['avatar_key'];
    final revision = value['revision'];
    if (name != null && name is! String ||
        avatarKey != null && avatarKey is! String ||
        revision is! num) {
      throw const FormatException('Invalid assistant identity preference.');
    }
    if (avatarKey != null && !assistantAvatarKeys.contains(avatarKey)) {
      throw const FormatException('Invalid assistant avatar preference.');
    }
    return AssistantIdentityPreference(
      customName: (name as String?)?.trim(),
      avatarKey: avatarKey as String?,
      revision: revision.toInt(),
    );
  }

  final String? customName, avatarKey;
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
  Future<AssistantIdentityPreference> saveAvatarPreference({
    required String? avatarKey,
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

  @override
  Future<AssistantIdentityPreference> saveAvatarPreference({
    required String? avatarKey,
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
  }) async {
    await _client
        .schema('api')
        .rpc<Object?>(
          'set_assistant_name',
          params: {
            'custom_name': customName,
            'expected_revision': expectedRevision,
            'idempotency_key': idempotencyKey,
          },
        );
    return getPreference();
  }

  @override
  Future<AssistantIdentityPreference> saveAvatarPreference({
    required String? avatarKey,
    required int expectedRevision,
    required String idempotencyKey,
  }) async => AssistantIdentityPreference.fromJson(
    await _client
        .schema('api')
        .rpc<Object?>(
          'set_assistant_avatar',
          params: {
            'avatar_key': avatarKey,
            'expected_revision': expectedRevision,
            'idempotency_key': idempotencyKey,
          },
        ),
  );
}
