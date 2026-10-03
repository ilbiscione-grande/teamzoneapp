import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/assistant_coach/assistant_identity.dart';

void main() {
  test('assistant identity has a safe presentation fallback', () {
    expect(assistantBaseName, 'Min assistent');
    expect(
      const AssistantIdentityPreference(revision: 0).displayName,
      assistantBaseName,
    );
    expect(
      const AssistantIdentityPreference(
        customName: 'Nova',
        revision: 2,
      ).displayName,
      'Nova',
    );
    expect(
      AssistantIdentityPreference.fromJson({
        'custom_name': 'Nova',
        'avatar_key': 'woman',
        'revision': 3,
      }).avatarKey,
      'woman',
    );
    expect(assistantAvatarAsset('woman'), endsWith('woman.png'));
    expect(assistantAvatarAsset('man'), endsWith('man.png'));
    expect(assistantAvatarAsset('woman_2'), endsWith('woman_2.png'));
    expect(assistantAvatarAsset('woman_3'), endsWith('woman_3.png'));
    expect(assistantAvatarAsset('man_2'), endsWith('man_2.png'));
    expect(assistantAvatarAsset('man_3'), endsWith('man_3.png'));
    expect(assistantAvatarAsset(null), isNull);
    expect(
      () => AssistantIdentityPreference.fromJson({
        'custom_name': null,
        'avatar_key': 'unknown',
        'revision': 1,
      }),
      throwsFormatException,
    );
  });

  test(
    'personal name validation rejects control characters and long names',
    () {
      expect(validateAssistantName('Nova'), isNull);
      expect(validateAssistantName(''), isNull);
      expect(validateAssistantName(List.filled(41, 'A').join()), isNotNull);
      expect(validateAssistantName('Nova\nSupport'), isNotNull);
      expect(assistantNameNeedsIdentityWarning('TeamZone support'), isTrue);
      expect(assistantNameNeedsIdentityWarning('Nova'), isFalse);
    },
  );

  test('AC-04 keeps the preference private and presentation-only', () {
    final migration = File(
      'supabase/migrations/20260828160052_ac04_assistant_identity_preferences.sql',
    ).readAsStringSync();
    final surface = File(
      'lib/src/features/assistant_coach/assistant_coach_entry.dart',
    ).readAsStringSync();
    final avatarMigration = File(
      'supabase/migrations/20261003070703_assistant_profile_avatar.sql',
    ).readAsStringSync();
    final expandedAvatarMigration = File(
      'supabase/migrations/20261003072031_expand_assistant_profile_avatars.sql',
    ).readAsStringSync();

    expect(migration, contains('enable row level security'));
    expect(
      migration,
      contains(
        'revoke all on table core.assistant_preferences from public, anon, authenticated',
      ),
    );
    expect(migration, contains("'assistant.identity.updated.v1'"));
    expect(migration, isNot(contains('capability')));
    expect(surface, contains("Key('assistant-name-settings')"));
    expect(surface, contains("Key('assistant-avatar-options')"));
    expect(avatarMigration, contains("avatar_key in ('woman','man')"));
    expect(expandedAvatarMigration, contains("'woman_2','woman_3'"));
    expect(expandedAvatarMigration, contains("'man_2','man_3'"));
    expect(avatarMigration, contains("'assistant.avatar.updated.v1'"));
    expect(avatarMigration, contains('from public, anon, authenticated'));
    expect(surface, contains("Key('assistant-name-warning')"));
    expect(surface, contains('Lämna fältet tomt för att återställa'));
  });
}
