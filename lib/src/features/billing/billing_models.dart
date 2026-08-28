class BillingPlan {
  const BillingPlan({
    required this.key,
    required this.monthlyAmountMinor,
    required this.annualAmountMinor,
    required this.maxActiveTeams,
    required this.maxBillablePeople,
    required this.quoteRequired,
  });

  final String key;
  final int? monthlyAmountMinor;
  final int? annualAmountMinor;
  final int? maxActiveTeams;
  final int? maxBillablePeople;
  final bool quoteRequired;

  factory BillingPlan.fromJson(Map<String, dynamic> json) => BillingPlan(
    key: json['key'] as String,
    monthlyAmountMinor: json['monthly_amount_minor'] as int?,
    annualAmountMinor: json['annual_amount_minor'] as int?,
    maxActiveTeams: json['max_active_teams'] as int?,
    maxBillablePeople: json['max_billable_people'] as int?,
    quoteRequired: json['quote_required'] as bool? ?? false,
  );
}

class BillingOverview {
  const BillingOverview({
    required this.version,
    required this.state,
    required this.plans,
  });
  final String version;
  final String state;
  final List<BillingPlan> plans;

  factory BillingOverview.fromJson(Map<String, dynamic> json) =>
      BillingOverview(
        version: json['version'] as String,
        state: json['state'] as String,
        plans: (json['plans'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map(
              (value) => BillingPlan.fromJson(Map<String, dynamic>.from(value)),
            )
            .toList(growable: false),
      );
}
