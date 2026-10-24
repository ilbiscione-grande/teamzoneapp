/// The Training module (decision package 11, MFD-08): a training session
/// with its blocks in order.
library;

import 'package:teamzone_app/src/features/team_development/team_development_models.dart';

/// The part of the session a block is in, as the old app's sessions.
enum TrainingPart {
  warmup('Uppvärmning'),
  main('Huvuddel'),
  finish('Avslutning');

  const TrainingPart(this.label);
  final String label;

  static TrainingPart from(Object? value) => switch (value) {
    'warmup' => warmup,
    'finish' => finish,
    _ => main,
  };
}

/// One exercise in the session.
class TrainingBlock {
  const TrainingBlock({
    required this.part,
    required this.title,
    this.minutes = 0,
    this.organisation = '',
    this.coachingPoints = '',
    this.phase,
    this.sourceKind = 'own',
    this.sourceId,
  });
  factory TrainingBlock.fromJson(Map<String, dynamic> json) => TrainingBlock(
    part: TrainingPart.from(json['part']),
    title: json['title'] as String? ?? '',
    minutes: (json['minutes'] as num?)?.toInt() ?? 0,
    organisation: json['organisation'] as String? ?? '',
    coachingPoints: json['coaching_points'] as String? ?? '',
    phase: json['phase'] == null ? null : PrincipleArea.from(json['phase']),
    sourceKind: json['source_kind'] as String? ?? 'own',
    sourceId: json['source_id'] as String?,
  );
  final TrainingPart part;
  final String title, organisation, coachingPoints, sourceKind;
  final int minutes;

  /// The phase of the game the exercise trains, if any.
  final PrincipleArea? phase;
  final String? sourceId;

  Map<String, Object?> toJson() => {
    'part': part.name,
    'title': title,
    'minutes': minutes,
    'organisation': organisation,
    'coaching_points': coachingPoints,
    'phase': phase?.key,
    'source_kind': sourceKind,
    'source_id': sourceId,
  };

  TrainingBlock copyWith({
    TrainingPart? part,
    String? title,
    int? minutes,
    String? organisation,
    String? coachingPoints,
    PrincipleArea? phase,
    bool clearPhase = false,
  }) => TrainingBlock(
    part: part ?? this.part,
    title: title ?? this.title,
    minutes: minutes ?? this.minutes,
    organisation: organisation ?? this.organisation,
    coachingPoints: coachingPoints ?? this.coachingPoints,
    phase: clearPhase ? null : phase ?? this.phase,
    sourceKind: sourceKind,
    sourceId: sourceId,
  );
}

/// A training's session: everything for those who prepare it, a published
/// one for the players. A new one (revision 0) starts from the event's own
/// theme and focus; [eventPlan] is the event's text plan to start from.
class TrainingSession {
  const TrainingSession({
    required this.eventId,
    required this.canEdit,
    required this.title,
    required this.startsAt,
    required this.endsAt,
    required this.revision,
    this.published = false,
    this.theme = '',
    this.goal = '',
    this.eventPlan,
    this.blocks = const [],
    this.updatedBy,
  });
  factory TrainingSession.fromJson(Map<String, dynamic> json) =>
      TrainingSession(
        eventId: json['event_id'] as String,
        canEdit: json['can_edit'] == true,
        title: json['title'] as String? ?? '',
        startsAt: DateTime.parse(json['starts_at'] as String).toLocal(),
        endsAt: DateTime.parse(json['ends_at'] as String).toLocal(),
        revision: (json['revision'] as num?)?.toInt() ?? 0,
        published: json['published'] == true,
        theme: json['theme'] as String? ?? '',
        goal: json['goal'] as String? ?? '',
        eventPlan: json['event_plan'] as String?,
        updatedBy: json['updated_by'] as String?,
        blocks: [
          for (final row
              in (json['blocks'] as List? ?? const []).whereType<Map>())
            TrainingBlock.fromJson(Map<String, dynamic>.from(row)),
        ],
      );
  final String eventId, title, theme, goal;
  final bool canEdit, published;
  final DateTime startsAt, endsAt;
  final int revision;
  final String? eventPlan, updatedBy;
  final List<TrainingBlock> blocks;

  int get minutes => blocks.fold(0, (sum, block) => sum + block.minutes);
  int get eventMinutes => endsAt.difference(startsAt).inMinutes;
}

/// A training in the module's list, with how far its session is planned:
/// `none`, `draft` or `published`.
class ModuleTraining {
  const ModuleTraining({
    required this.eventId,
    required this.title,
    required this.startsAt,
    required this.endsAt,
    required this.state,
    required this.session,
    this.theme,
    this.minutes = 0,
    this.blocks = 0,
  });
  factory ModuleTraining.fromJson(Map<String, dynamic> json) => ModuleTraining(
    eventId: json['event_id'] as String,
    title: json['title'] as String? ?? '',
    startsAt: DateTime.parse(json['starts_at'] as String).toLocal(),
    endsAt: DateTime.parse(json['ends_at'] as String).toLocal(),
    state: json['state'] as String? ?? 'scheduled',
    session: json['session'] as String? ?? 'none',
    theme: json['theme'] as String?,
    minutes: (json['minutes'] as num?)?.toInt() ?? 0,
    blocks: (json['blocks'] as num?)?.toInt() ?? 0,
  );
  final String eventId, title, state, session;
  final String? theme;
  final DateTime startsAt, endsAt;
  final int minutes, blocks;
}
