class DevelopmentPlan {
  const DevelopmentPlan({
    required this.id,
    required this.title,
    required this.focus,
    required this.planType,
    required this.state,
    required this.revision,
    required this.actions,
  });

  final String id;
  final String title;
  final String focus;
  final String planType;
  final String state;
  final int revision;
  final List<DevelopmentAction> actions;

  factory DevelopmentPlan.fromJson(Map<String, dynamic> json) =>
      DevelopmentPlan(
        id: json['id'] as String,
        title: json['title'] as String,
        focus: (json['focus'] as String?) ?? '',
        planType: json['plan_type'] as String,
        state: json['state'] as String,
        revision: (json['revision'] as num).toInt(),
        actions: ((json['actions'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(DevelopmentAction.fromJson)
            .toList(growable: false),
      );
}

class DevelopmentAction {
  const DevelopmentAction({
    required this.id,
    required this.title,
    required this.description,
    required this.state,
    required this.sourceKind,
  });

  final String id;
  final String title;
  final String description;
  final String state;
  final String sourceKind;

  factory DevelopmentAction.fromJson(Map<String, dynamic> json) =>
      DevelopmentAction(
        id: json['id'] as String,
        title: json['title'] as String,
        description: (json['description'] as String?) ?? '',
        state: json['state'] as String,
        sourceKind: json['source_kind'] as String,
      );
}
