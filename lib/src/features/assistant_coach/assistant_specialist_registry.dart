import 'package:flutter/material.dart';

enum AssistantAreaGateState { pendingVerification, blocked }

@immutable
class AssistantSpecialistArea {
  const AssistantSpecialistArea({
    required this.key,
    required this.label,
    required this.iconToken,
    required this.designToken,
    required this.sourceKeys,
    required this.capabilities,
    required this.targetRoles,
    required this.presentationFields,
    required this.actions,
    required this.gateState,
  });

  final String key;
  final String label;
  final String iconToken;
  final String designToken;
  final List<String> sourceKeys;
  final List<String> capabilities;
  final List<String> targetRoles;
  final List<String> presentationFields;
  final List<String> actions;
  final AssistantAreaGateState gateState;

  bool get isActive => false;
}

abstract final class AssistantSpecialistRegistry {
  static const version = 1;

  static const areas = <AssistantSpecialistArea>[
    AssistantSpecialistArea(
      key: 'team_planning',
      label: 'Lagplanering',
      iconToken: 'strategy',
      designToken: 'assistant.area.blue',
      sourceKeys: [
        'core.events',
        'core.squad_revisions',
        'core.callups',
        'core.attendance_facts',
      ],
      capabilities: [
        'event.manage',
        'event.squad.manage',
        'event.attendance.manage',
      ],
      targetRoles: ['leader'],
      presentationFields: [
        'context',
        'source',
        'observed_at',
        'fresh_until',
        'explanation',
      ],
      actions: ['navigate.calendar', 'navigate.event'],
      gateState: AssistantAreaGateState.pendingVerification,
    ),
    AssistantSpecialistArea(
      key: 'training_support',
      label: 'Träningsstöd',
      iconToken: 'training',
      designToken: 'assistant.area.green',
      sourceKeys: ['core.events', 'core.attendance_facts'],
      capabilities: ['event.manage', 'event.attendance.manage'],
      targetRoles: ['leader'],
      presentationFields: ['context', 'source', 'fresh_until', 'explanation'],
      actions: ['navigate.calendar'],
      gateState: AssistantAreaGateState.blocked,
    ),
    AssistantSpecialistArea(
      key: 'individual_development',
      label: 'Individuell utveckling',
      iconToken: 'development',
      designToken: 'assistant.area.purple',
      sourceKeys: ['core.development_plans', 'core.development_actions'],
      capabilities: ['development.manage', 'development.self.view'],
      targetRoles: ['leader', 'player', 'guardian'],
      presentationFields: [
        'context',
        'subject',
        'source',
        'fresh_until',
        'explanation',
      ],
      actions: ['navigate.development'],
      gateState: AssistantAreaGateState.blocked,
    ),
    AssistantSpecialistArea(
      key: 'rehab_support',
      label: 'Rehabstöd',
      iconToken: 'recovery',
      designToken: 'assistant.area.teal',
      sourceKeys: ['approved_rehab_plan'],
      capabilities: ['rehab.plan.view'],
      targetRoles: ['player', 'guardian', 'leader'],
      presentationFields: [
        'context',
        'subject',
        'approved_plan_source',
        'fresh_until',
        'explanation',
      ],
      actions: ['navigate.approved_rehab_plan'],
      gateState: AssistantAreaGateState.blocked,
    ),
    AssistantSpecialistArea(
      key: 'club_administration',
      label: 'Klubbadministration',
      iconToken: 'club',
      designToken: 'assistant.area.orange',
      sourceKeys: [
        'core.clubs',
        'core.club_people',
        'core.team_assignments',
        'core.membership_applications',
        'core.editorial_articles',
      ],
      capabilities: ['club.memberships.manage', 'publication.manage'],
      targetRoles: ['club_functionary', 'leader'],
      presentationFields: ['context', 'source', 'fresh_until', 'explanation'],
      actions: ['navigate.club', 'navigate.publication'],
      gateState: AssistantAreaGateState.blocked,
    ),
    AssistantSpecialistArea(
      key: 'communication',
      label: 'Kommunikation',
      iconToken: 'message',
      designToken: 'assistant.area.cyan',
      sourceKeys: ['core.message_threads', 'core.messages'],
      capabilities: ['message.thread.view', 'message.send'],
      targetRoles: ['club_functionary', 'leader', 'player', 'guardian'],
      presentationFields: ['context', 'source', 'fresh_until', 'explanation'],
      actions: ['navigate.inbox', 'navigate.thread'],
      gateState: AssistantAreaGateState.blocked,
    ),
  ];

  static AssistantSpecialistArea? byKey(String key) {
    for (final area in areas) {
      if (area.key == key) return area;
    }
    return null;
  }
}

class AssistantAreaBadge extends StatelessWidget {
  const AssistantAreaBadge({required this.area, super.key});

  final AssistantSpecialistArea area;

  @override
  Widget build(BuildContext context) {
    final colors = _areaColors(context, area.designToken);
    return Semantics(
      label: 'Område: ${area.label}',
      child: Chip(
        avatar: Icon(_areaIcon(area.iconToken), size: 18, color: colors.$2),
        label: Text(area.label),
        backgroundColor: colors.$1,
        labelStyle: TextStyle(color: colors.$2),
        side: BorderSide(color: colors.$2.withValues(alpha: 0.35)),
      ),
    );
  }
}

IconData _areaIcon(String token) => switch (token) {
  'strategy' => Icons.event_note_outlined,
  'training' => Icons.fitness_center_outlined,
  'development' => Icons.trending_up_outlined,
  'recovery' => Icons.healing_outlined,
  'club' => Icons.shield_outlined,
  'message' => Icons.forum_outlined,
  _ => Icons.assistant_outlined,
};

(Color, Color) _areaColors(BuildContext context, String token) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final background = switch (token) {
    'assistant.area.blue' =>
      dark ? const Color(0xff173b63) : const Color(0xffd9eaff),
    'assistant.area.green' =>
      dark ? const Color(0xff174c36) : const Color(0xffd5f4e4),
    'assistant.area.purple' =>
      dark ? const Color(0xff493067) : const Color(0xffecddff),
    'assistant.area.teal' =>
      dark ? const Color(0xff164c50) : const Color(0xffd2f2f2),
    'assistant.area.orange' =>
      dark ? const Color(0xff623615) : const Color(0xffffe3cb),
    'assistant.area.cyan' =>
      dark ? const Color(0xff174854) : const Color(0xffd5f1f8),
    _ => Theme.of(context).colorScheme.surfaceContainerHighest,
  };
  final foreground =
      ThemeData.estimateBrightnessForColor(background) == Brightness.dark
      ? Colors.white
      : const Color(0xff111111);
  return (background, foreground);
}
