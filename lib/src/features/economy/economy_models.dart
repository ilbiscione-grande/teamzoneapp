class EconomyAccount {
  const EconomyAccount({
    required this.id,
    required this.name,
    required this.currency,
    this.teamId,
  });
  final String id;
  final String name;
  final String currency;
  final String? teamId;
  factory EconomyAccount.fromJson(Map<String, dynamic> value) => EconomyAccount(
    id: value['id'] as String,
    name: value['name'] as String,
    currency: value['currency'] as String,
    teamId: value['team_id'] as String?,
  );
}

class EconomyEntry {
  const EconomyEntry({
    required this.id,
    required this.accountId,
    required this.amountMinor,
    required this.direction,
    required this.category,
    required this.state,
    required this.riskLevel,
    required this.approvalCount,
    required this.requiredApprovals,
    required this.currentActorApproved,
    required this.approvers,
    this.reversalOf,
    this.reversalState,
  });
  final String id;
  final String accountId;
  final int amountMinor;
  final String direction;
  final String category;
  final String state;
  final String riskLevel;
  final int approvalCount;
  final int requiredApprovals;
  final bool currentActorApproved;
  final List<EconomyApprover> approvers;
  final String? reversalOf;
  final String? reversalState;
  factory EconomyEntry.fromJson(Map<String, dynamic> value) => EconomyEntry(
    id: value['id'] as String,
    accountId: value['account_id'] as String,
    amountMinor: value['amount_minor'] as int,
    direction: value['direction'] as String,
    category: value['category'] as String,
    state: value['state'] as String,
    riskLevel: value['risk_level'] as String,
    approvalCount: value['approval_count'] as int? ?? 0,
    requiredApprovals: value['required_approvals'] as int? ?? 0,
    currentActorApproved: value['current_actor_approved'] as bool? ?? false,
    approvers: (value['approvers'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map(
          (item) => EconomyApprover.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false),
    reversalOf: value['reversal_of'] as String?,
    reversalState: value['reversal_state'] as String?,
  );
}

class EconomyApprover {
  const EconomyApprover({
    required this.profileId,
    required this.displayName,
    required this.decision,
  });
  final String profileId;
  final String displayName;
  final String decision;
  factory EconomyApprover.fromJson(Map<String, dynamic> value) =>
      EconomyApprover(
        profileId: value['profile_id'] as String,
        displayName: value['display_name'] as String,
        decision: value['decision'] as String,
      );
}

class EconomyOverview {
  const EconomyOverview({required this.accounts, required this.entries});
  final List<EconomyAccount> accounts;
  final List<EconomyEntry> entries;
  factory EconomyOverview.fromJson(
    Map<String, dynamic> value,
  ) => EconomyOverview(
    accounts: (value['accounts'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => EconomyAccount.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false),
    entries: (value['entries'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => EconomyEntry.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false),
  );
}
