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
    expect(surface, contains("Key('assistant-name-warning')"));
    expect(surface, contains('Lämna fältet tomt för att återställa'));
  });
}
