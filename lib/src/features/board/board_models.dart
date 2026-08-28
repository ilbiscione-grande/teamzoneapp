class BoardAssignment {
  const BoardAssignment({
    required this.id,
    required this.name,
    required this.rolePackage,
  });
  final String id;
  final String name;
  final String rolePackage;
  factory BoardAssignment.fromJson(Map<String, dynamic> value) =>
      BoardAssignment(
        id: value['id'] as String,
        name: value['name'] as String,
        rolePackage: value['role_package'] as String,
      );
}

class BoardMandate {
  const BoardMandate({
    required this.id,
    required this.assignmentId,
    required this.name,
    required this.office,
    required this.startsAt,
    required this.endsAt,
    required this.state,
  });
  final String id;
  final String assignmentId;
  final String name;
  final String office;
  final DateTime startsAt;
  final DateTime endsAt;
  final String state;
  factory BoardMandate.fromJson(Map<String, dynamic> value) => BoardMandate(
    id: value['id'] as String,
    assignmentId: value['assignment_id'] as String,
    name: value['name'] as String,
    office: value['office'] as String,
    startsAt: DateTime.parse(value['starts_at'] as String),
    endsAt: DateTime.parse(value['ends_at'] as String),
    state: value['state'] as String,
  );
}

class BoardApprover {
  const BoardApprover({required this.displayName, required this.decision});
  final String displayName;
  final String decision;
  factory BoardApprover.fromJson(Map<String, dynamic> value) => BoardApprover(
    displayName: value['display_name'] as String,
    decision: value['decision'] as String,
  );
}

class BoardMandateChange {
  const BoardMandateChange({
    required this.id,
    required this.assignmentId,
    required this.name,
    required this.action,
    required this.office,
    required this.state,
    required this.createdBy,
    required this.approvalCount,
    required this.currentActorApproved,
    required this.approvers,
    this.mandateId,
    this.startsAt,
    this.endsAt,
  });
  final String id;
  final String assignmentId;
  final String? mandateId;
  final String name;
  final String action;
  final String office;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String state;
  final String createdBy;
  final int approvalCount;
  final bool currentActorApproved;
  final List<BoardApprover> approvers;
  factory BoardMandateChange.fromJson(Map<String, dynamic> value) =>
      BoardMandateChange(
        id: value['id'] as String,
        assignmentId: value['assignment_id'] as String,
        mandateId: value['mandate_id'] as String?,
        name: value['name'] as String,
        action: value['action'] as String,
        office: value['office'] as String,
        startsAt: value['starts_at'] == null
            ? null
            : DateTime.parse(value['starts_at'] as String),
        endsAt: value['ends_at'] == null
            ? null
            : DateTime.parse(value['ends_at'] as String),
        state: value['state'] as String,
        createdBy: value['created_by'] as String,
        approvalCount: value['approval_count'] as int? ?? 0,
        currentActorApproved: value['current_actor_approved'] as bool? ?? false,
        approvers: (value['approvers'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map(
              (item) => BoardApprover.fromJson(Map<String, dynamic>.from(item)),
            )
            .toList(growable: false),
      );
}

class BoardOverview {
  const BoardOverview({
    required this.assignments,
    required this.mandates,
    required this.changes,
  });
  final List<BoardAssignment> assignments;
  final List<BoardMandate> mandates;
  final List<BoardMandateChange> changes;
  factory BoardOverview.fromJson(Map<String, dynamic> value) => BoardOverview(
    assignments: (value['assignments'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map(
          (item) => BoardAssignment.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false),
    mandates: (value['mandates'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => BoardMandate.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false),
    changes: (value['changes'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map(
          (item) =>
              BoardMandateChange.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false),
  );
}
