import 'package:flutter/material.dart';

enum AssistantActionKind { navigate, domainMutation }

@immutable
class AssistantActionContract {
  const AssistantActionContract({
    required this.kind,
    required this.previewed,
    required this.explicitlyConfirmed,
    required this.serverAuthorized,
    required this.idempotent,
    required this.audited,
  });

  const AssistantActionContract.navigation()
    : kind = AssistantActionKind.navigate,
      previewed = false,
      explicitlyConfirmed = false,
      serverAuthorized = false,
      idempotent = false,
      audited = false;

  final AssistantActionKind kind;
  final bool previewed;
  final bool explicitlyConfirmed;
  final bool serverAuthorized;
  final bool idempotent;
  final bool audited;

  bool get mayExecute => switch (kind) {
    AssistantActionKind.navigate => true,
    AssistantActionKind.domainMutation =>
      previewed &&
          explicitlyConfirmed &&
          serverAuthorized &&
          idempotent &&
          audited,
  };
}

@immutable
class AssistantSpecialistPolicy {
  const AssistantSpecialistPolicy({
    required this.areaKey,
    required this.responsibility,
    required this.prohibitedDecisions,
  });

  final String areaKey;
  final String responsibility;
  final Set<String> prohibitedDecisions;

  bool get isDigitalFunction => true;
  bool get generativeAiAllowed => false;
  bool get autonomousDomainMutationAllowed => false;
}

abstract final class AssistantSpecialistPolicyRegistry {
  static const version = 1;

  static const policies = <AssistantSpecialistPolicy>[
    AssistantSpecialistPolicy(
      areaKey: 'team_planning',
      responsibility:
          'Förklara verifierade planeringssignaler och navigera till rätt lagvy.',
      prohibitedDecisions: {
        'select_players',
        'change_event',
        'record_attendance',
      },
    ),
    AssistantSpecialistPolicy(
      areaKey: 'training_support',
      responsibility:
          'Stödja praktisk träningsplanering från godkända lagdata.',
      prohibitedDecisions: {'prescribe_training', 'assess_medical_readiness'},
    ),
    AssistantSpecialistPolicy(
      areaKey: 'individual_development',
      responsibility:
          'Förklara godkända mål och progression utan personrangordning.',
      prohibitedDecisions: {'rank_people', 'set_goal_without_confirmation'},
    ),
    AssistantSpecialistPolicy(
      areaKey: 'rehab_support',
      responsibility:
          'Följa och påminna om en redan beslutad plan utan medicinsk bedömning.',
      prohibitedDecisions: {
        'diagnose',
        'prescribe',
        'rank_medical_risk',
        'decide_return_to_play',
      },
    ),
    AssistantSpecialistPolicy(
      areaKey: 'club_administration',
      responsibility:
          'Förklara verifierade klubbuppgifter och navigera till ansvarig vy.',
      prohibitedDecisions: {
        'approve_membership',
        'publish_without_confirmation',
      },
    ),
    AssistantSpecialistPolicy(
      areaKey: 'communication',
      responsibility:
          'Förklara relationstillåtna kommunikationsbehov utan att skicka själv.',
      prohibitedDecisions: {'send_message', 'contact_outside_relationship'},
    ),
  ];

  static AssistantSpecialistPolicy? byAreaKey(String key) {
    for (final policy in policies) {
      if (policy.areaKey == key) return policy;
    }
    return null;
  }
}

class AssistantDigitalFunctionNotice extends StatelessWidget {
  const AssistantDigitalFunctionNotice({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label:
        'Min assistent är en digital funktion, inte en människa eller legitimerad expert.',
    child: Card(
      key: const Key('assistant-digital-function-notice'),
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: const Padding(
        padding: EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.smart_toy_outlined),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Min assistent är en digital funktion – inte en människa, '
                'vårdprofession eller legitimerad expert. Förslag bygger på '
                'verifierade TeamZone-data och kräver ditt beslut.',
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
