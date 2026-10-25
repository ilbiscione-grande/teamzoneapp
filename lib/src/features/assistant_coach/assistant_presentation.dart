import '../../core/localization/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/features/assistant_coach/assistant_queue.dart';
import 'package:teamzone_app/src/features/assistant_coach/assistant_policy.dart';
import 'package:teamzone_app/src/features/assistant_coach/assistant_specialist_registry.dart';

@immutable
class AssistantPresentationContext {
  const AssistantPresentationContext({
    required this.contextId,
    required this.clubId,
    required this.clubName,
    required this.teamId,
    required this.teamName,
    required this.rolePackage,
    this.actingAsPersonId,
    this.actingAsName,
  });

  factory AssistantPresentationContext.fromTeamZoneContext(
    TeamZoneContext value, {
    String? actingAsPersonId,
    String? actingAsName,
  }) => AssistantPresentationContext(
    contextId: value.id,
    clubId: value.clubId,
    clubName: value.clubName,
    teamId: value.teamId,
    teamName: value.teamName,
    rolePackage: value.rolePackage,
    actingAsPersonId: actingAsPersonId,
    actingAsName: actingAsName,
  );

  final String contextId;
  final String clubId;
  final String clubName;
  final String? teamId;
  final String? teamName;
  final String rolePackage;
  final String? actingAsPersonId;
  final String? actingAsName;

  String get roleLabel => switch (rolePackage) {
    'leader' => 'Ledare',
    'player' => 'Spelare',
    'guardian' => 'Vårdnadshavare',
    'club_functionary' => 'Klubbfunktionär',
    'referee' => 'Domare',
    'referee_assigner' => 'Domartillsättare',
    _ => 'Användare',
  };
}

List<AssistantSpecialistArea> relevantAssistantAreas(TeamZoneContext context) =>
    AssistantSpecialistRegistry.areas
        .where(
          (area) =>
              area.targetRoles.contains(context.rolePackage) &&
              area.capabilities.any(context.can),
        )
        .toList(growable: false);

@immutable
class AssistantAreaPreference {
  const AssistantAreaPreference({
    required this.areaKey,
    required this.visible,
    required this.deliveryMode,
    required this.revision,
  });

  factory AssistantAreaPreference.fromJson(Map<String, dynamic> json) =>
      AssistantAreaPreference(
        areaKey: json['area_key'] as String,
        visible: json['visible'] as bool? ?? true,
        deliveryMode: assistantDeliveryModeFromWire(
          json['delivery_mode'] as String? ?? 'off',
        ),
        revision: (json['revision'] as num?)?.toInt() ?? 0,
      );

  final String areaKey;
  final bool visible;
  final AssistantDeliveryMode deliveryMode;
  final int revision;
}

abstract interface class AssistantPresentationServices {
  Future<List<AssistantAreaPreference>> getAreaPreferences();
  Future<AssistantAreaPreference> saveAreaPreference({
    required String areaKey,
    required bool visible,
    required AssistantDeliveryMode deliveryMode,
    required int expectedRevision,
    required String idempotencyKey,
  });
}

class UnconfiguredAssistantPresentationServices
    implements AssistantPresentationServices {
  const UnconfiguredAssistantPresentationServices();

  @override
  Future<List<AssistantAreaPreference>> getAreaPreferences() async => const [];

  @override
  Future<AssistantAreaPreference> saveAreaPreference({
    required String areaKey,
    required bool visible,
    required AssistantDeliveryMode deliveryMode,
    required int expectedRevision,
    required String idempotencyKey,
  }) => Future.error(StateError('Supabase is not configured.'));
}

class SupabaseAssistantPresentationServices
    implements AssistantPresentationServices {
  const SupabaseAssistantPresentationServices(this._client);

  final SupabaseClient _client;

  @override
  Future<List<AssistantAreaPreference>> getAreaPreferences() async {
    final value = await _client
        .schema('api')
        .rpc<Object?>('get_assistant_area_preferences');
    if (value is! List) {
      throw const FormatException('Invalid assistant area preferences.');
    }
    return value
        .whereType<Map<String, dynamic>>()
        .map(AssistantAreaPreference.fromJson)
        .toList(growable: false);
  }

  @override
  Future<AssistantAreaPreference> saveAreaPreference({
    required String areaKey,
    required bool visible,
    required AssistantDeliveryMode deliveryMode,
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'set_assistant_area_preference',
          params: {
            'area_key': areaKey,
            'visible': visible,
            'delivery_mode': deliveryMode.name == 'inAssistant'
                ? 'in_assistant'
                : deliveryMode.name,
            'expected_revision': expectedRevision,
            'idempotency_key': idempotencyKey,
          },
        );
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid assistant area preference.');
    }
    return AssistantAreaPreference.fromJson(value);
  }
}

class AssistantContextBanner extends StatelessWidget {
  const AssistantContextBanner({required this.value, super.key});

  final AssistantPresentationContext value;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label:
        '${AppStrings.of(context).isSwedish ? 'Aktiv kontext' : 'Active context'}: ${value.clubName}, '
        '${value.teamName ?? (AppStrings.of(context).isSwedish ? 'hela klubben' : 'whole club')}, ${AppStrings.of(context).feature(value.roleLabel)}',
    child: Card(
      child: ListTile(
        key: const Key('assistant-context-banner'),
        leading: const Icon(Icons.account_tree_outlined),
        title: Text(value.teamName ?? value.clubName),
        subtitle: Text(
          [
            if (value.teamName != null) value.clubName,
            AppStrings.of(context).feature(value.roleLabel),
            if (value.actingAsName != null)
              '${AppStrings.of(context).isSwedish ? 'Agerar för' : 'Acting for'} ${value.actingAsName}',
          ].join(' • '),
        ),
      ),
    ),
  );
}

class AssistantQueuePostCard extends StatelessWidget {
  const AssistantQueuePostCard({
    required this.post,
    required this.area,
    required this.presentationContext,
    this.onAction,
    this.now,
    super.key,
  });

  final AssistantQueuePost post;
  final AssistantSpecialistArea area;
  final AssistantPresentationContext presentationContext;
  final VoidCallback? onAction;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final stale = post.isStaleAt(now ?? DateTime.now());
    final policy = AssistantSpecialistPolicyRegistry.byAreaKey(area.key);
    return Card(
      key: ValueKey('assistant-post-${post.canonicalKey}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                AssistantAreaBadge(area: area),
                Chip(
                  avatar: Icon(
                    stale ? Icons.sync_problem_outlined : Icons.schedule,
                    size: 18,
                  ),
                  label: Text(
                    AppStrings.of(
                      context,
                    ).feature(stale ? 'Inaktuell' : 'Aktuell'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(post.explanation),
            if (policy != null) ...[
              const SizedBox(height: 6),
              Text(
                'Ansvar: ${policy.responsibility}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (area.key == 'rehab_support')
              ListTile(
                key: Key('assistant-rehab-boundary'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.health_and_safety_outlined),
                title: Text(
                  AppStrings.of(
                    context,
                  ).feature('Rehabstöd följer bara en beslutad plan'),
                ),
                subtitle: Text(
                  AppStrings.of(context).feature(
                    'Det diagnostiserar, ordinerar, riskrangordnar eller beslutar '
                    'aldrig om återgång till spel.',
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'Källa: ${post.source} • Beräknad: ${post.observedAt.toLocal()}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              'Kontext: ${presentationContext.clubName} • '
              '${presentationContext.teamName ?? 'hela klubben'} • '
              '${AppStrings.of(context).feature(presentationContext.roleLabel)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (presentationContext.actingAsName != null)
              Text(
                'Agerar för: ${presentationContext.actingAsName}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (post.safeAction.isNotEmpty) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.open_in_new),
                label: Text(post.safeAction),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
