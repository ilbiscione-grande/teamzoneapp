import 'package:supabase_flutter/supabase_flutter.dart';

import 'club_register.dart';

// Avgiftsomgångar och familjer (docs/implementation/club-members-and-fees.md,
// step 2). Amounts are in öre; the pages show kronor.

/// Whole kronor from öre, for display: 30000 → "300 kr".
String clubFeeKronor(int minor) {
  final kronor = minor ~/ 100;
  final rest = minor % 100;
  final digits = '$kronor'.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ' ',
  );
  return rest == 0
      ? '$digits kr'
      : '$digits,${rest.toString().padLeft(2, '0')} kr';
}

/// Öre from what someone typed in kronor ("300", "300,50"); null if empty
/// or not a number.
int? clubFeeMinorFrom(String text) {
  final value = text.replaceAll(' ', '').replaceAll(',', '.').trim();
  if (value.isEmpty) return null;
  final number = double.tryParse(value);
  if (number == null || number < 0) return null;
  return (number * 100).round();
}

class ClubFeeRound {
  const ClubFeeRound({
    required this.roundId,
    required this.kind,
    required this.teamId,
    required this.teamName,
    required this.title,
    required this.dueOn,
    required this.amounts,
    required this.familyCap,
    required this.siblingDiscountPercent,
    required this.state,
    required this.revision,
    this.feeCount = 0,
    this.total = 0,
    this.paidCount = 0,
    this.paidTotal = 0,
    this.openCount = 0,
    this.openTotal = 0,
  });

  factory ClubFeeRound.fromJson(Map<String, dynamic> json) => ClubFeeRound(
    roundId: json['round_id'] as String,
    kind: json['kind'] as String? ?? 'membership',
    teamId: json['team_id'] as String?,
    teamName: json['team_name'] as String?,
    title: json['title'] as String? ?? '',
    dueOn: DateTime.parse(json['due_on'] as String),
    amounts: {
      for (final entry in (json['amounts'] as Map? ?? const {}).entries)
        '${entry.key}': (entry.value as num).toInt(),
    },
    familyCap: (json['family_cap'] as num?)?.toInt(),
    siblingDiscountPercent: (json['sibling_discount_percent'] as num?)?.toInt(),
    state: json['state'] as String? ?? 'draft',
    revision: (json['revision'] as num?)?.toInt() ?? 0,
    feeCount: (json['fee_count'] as num?)?.toInt() ?? 0,
    total: (json['total'] as num?)?.toInt() ?? 0,
    paidCount: (json['paid_count'] as num?)?.toInt() ?? 0,
    paidTotal: (json['paid_total'] as num?)?.toInt() ?? 0,
    openCount: (json['open_count'] as num?)?.toInt() ?? 0,
    openTotal: (json['open_total'] as num?)?.toInt() ?? 0,
  );

  final String roundId;

  /// membership (per category, family rule) or team (per player).
  final String kind;
  final String? teamId;
  final String? teamName;
  final String title;
  final DateTime dueOn;

  /// youth, adult, supporter or player → öre.
  final Map<String, int> amounts;
  final int? familyCap;
  final int? siblingDiscountPercent;

  /// draft or issued.
  final String state;
  final int revision;
  final int feeCount;
  final int total;

  /// Issued rounds: what is paid and what is left.
  final int paidCount;
  final int paidTotal;
  final int openCount;
  final int openTotal;

  bool get isDraft => state == 'draft';
  bool get isMembership => kind == 'membership';
}

class ClubFee {
  const ClubFee({
    required this.personId,
    required this.name,
    required this.category,
    required this.familyKey,
    required this.baseAmount,
    required this.discountAmount,
    required this.amount,
    required this.state,
    required this.guardians,
    this.feeId,
    this.revision = 0,
    this.paidOn,
    this.paymentMethod,
    this.note,
  });

  factory ClubFee.fromJson(Map<String, dynamic> json) => ClubFee(
    personId: json['person_id'] as String,
    name: json['name'] as String? ?? '',
    category: json['category'] as String?,
    familyKey: json['family_key'] as String?,
    baseAmount: (json['base_amount'] as num?)?.toInt() ?? 0,
    discountAmount: (json['discount_amount'] as num?)?.toInt() ?? 0,
    amount: (json['amount'] as num?)?.toInt() ?? 0,
    state: json['state'] as String? ?? 'open',
    guardians: (json['guardians'] as List? ?? const [])
        .whereType<String>()
        .toList(),
    feeId: json['fee_id'] as String?,
    revision: (json['revision'] as num?)?.toInt() ?? 0,
    paidOn: switch (json['paid_on']) {
      final String day => DateTime.parse(day),
      _ => null,
    },
    paymentMethod: json['payment_method'] as String?,
    note: json['note'] as String?,
  );

  final String personId;
  final String name;
  final String? category;
  final String? familyKey;
  final int baseAmount;
  final int discountAmount;
  final int amount;

  /// open, paid, waived (nothing to pay) or cancelled.
  final String state;

  /// Who pays for a child.
  final List<String> guardians;

  /// Null while the round is a draft.
  final String? feeId;
  final int revision;
  final DateTime? paidOn;

  /// swish, bank, cash or other.
  final String? paymentMethod;
  final String? note;

  bool get isOpen => state == 'open' && amount > 0;
  bool get canReopen => feeId != null && amount > 0 && state != 'open';
}

class ClubFeeRoundDetail {
  const ClubFeeRoundDetail({
    required this.round,
    required this.fees,
    required this.missing,
  });

  factory ClubFeeRoundDetail.fromJson(Map<String, dynamic> json) =>
      ClubFeeRoundDetail(
        round: ClubFeeRound.fromJson(json),
        fees: (json['fees'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ClubFee.fromJson)
            .toList(growable: false),
        missing: (json['missing'] as List? ?? const [])
            .whereType<String>()
            .toList(growable: false),
      );

  final ClubFeeRound round;
  final List<ClubFee> fees;

  /// Members a membership round cannot charge: no category known.
  final List<String> missing;

  int get total => fees.fold(0, (sum, fee) => sum + fee.amount);
  int get discount => fees.fold(0, (sum, fee) => sum + fee.discountAmount);
}

/// What a round is saved with; amounts in öre.
class ClubFeeRoundDraft {
  const ClubFeeRoundDraft({
    required this.kind,
    required this.title,
    required this.dueOn,
    this.teamId,
    this.amounts = const {},
    this.familyCap,
    this.siblingDiscountPercent,
  });
  final String kind;
  final String? teamId;
  final String title;
  final DateTime dueOn;
  final Map<String, int> amounts;
  final int? familyCap;
  final int? siblingDiscountPercent;

  Map<String, Object?> toPayload() => {
    'kind': kind,
    'team_id': teamId,
    'title': title,
    'due_on':
        '${dueOn.year.toString().padLeft(4, '0')}-${dueOn.month.toString().padLeft(2, '0')}-${dueOn.day.toString().padLeft(2, '0')}',
    for (final entry in amounts.entries) 'amount_${entry.key}': entry.value,
    'family_cap': familyCap,
    'sibling_discount_percent': siblingDiscountPercent,
  };
}

class ClubFamilyMember {
  const ClubFamilyMember({
    required this.personId,
    required this.name,
    required this.category,
    required this.familyKey,
    required this.manual,
    required this.guardians,
  });

  factory ClubFamilyMember.fromJson(Map<String, dynamic> json) =>
      ClubFamilyMember(
        personId: json['person_id'] as String,
        name: json['name'] as String? ?? '',
        category: json['category'] as String?,
        familyKey: json['family_key'] as String? ?? json['person_id'] as String,
        manual: json['manual'] as bool? ?? false,
        guardians: (json['guardians'] as List? ?? const [])
            .whereType<String>()
            .toList(),
      );

  final String personId;
  final String name;
  final String? category;
  final String familyKey;

  /// The club has placed this person by hand.
  final bool manual;
  final List<String> guardians;
}

class ClubFamily {
  const ClubFamily(this.key, this.members);
  final String key;
  final List<ClubFamilyMember> members;
  bool get manual => members.any((member) => member.manual);
  List<String> get guardians =>
      {for (final member in members) ...member.guardians}.toList()..sort();
}

/// The families worth showing: two or more members, or placed by hand.
List<ClubFamily> clubFamiliesOf(List<ClubFamilyMember> members) {
  final byKey = <String, List<ClubFamilyMember>>{};
  for (final member in members) {
    byKey.putIfAbsent(member.familyKey, () => []).add(member);
  }
  final families = [
    for (final entry in byKey.entries)
      if (entry.value.length > 1 || entry.value.any((member) => member.manual))
        ClubFamily(entry.key, entry.value),
  ];
  families.sort((a, b) => a.members.first.name.compareTo(b.members.first.name));
  return families;
}

abstract interface class ClubFeeServices {
  Future<List<ClubFeeRound>> loadClubFeeRounds(String clubId);
  Future<ClubFeeRoundDetail> loadClubFeeRound(String clubId, String roundId);

  /// [roundId] null creates a draft; returns the round id.
  Future<String> saveClubFeeRound({
    required String clubId,
    required String? roundId,
    required ClubFeeRoundDraft draft,
    required int expectedRevision,
    required String idempotencyKey,
  });

  /// [decision]: issue (create the fees) or cancel (drop the draft).
  Future<void> decideClubFeeRound({
    required String clubId,
    required String roundId,
    required String decision,
    required int expectedRevision,
    required String idempotencyKey,
  });

  /// [decision]: paid (with [paidOn] and [method]), waived or open (undo).
  Future<void> markClubFees({
    required String clubId,
    required List<ClubFee> fees,
    required String decision,
    DateTime? paidOn,
    String? method,
    String? note,
    required String idempotencyKey,
  });

  Future<List<ClubFamilyMember>> loadClubFamilies(String clubId);

  /// [change]: merge, split or reset.
  Future<void> changeClubFamily({
    required String clubId,
    required String change,
    required List<String> personIds,
    required String idempotencyKey,
  });
}

Future<Object?> _rpc(
  SupabaseClient client,
  String name,
  Map<String, Object?> params,
) async {
  try {
    return await client
        .schema('api')
        .rpc<Object?>(name, params: params)
        .timeout(const Duration(seconds: 20));
  } on PostgrestException catch (error) {
    if (error.code == 'PT409') throw const ClubRegisterConflict();
    rethrow;
  }
}

Map<String, dynamic> _map(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Invalid fee response.');
  }
  return value;
}

/// The Supabase calls behind [ClubFeeServices].
class SupabaseClubFees implements ClubFeeServices {
  const SupabaseClubFees(this._client);
  final SupabaseClient _client;

  @override
  Future<List<ClubFeeRound>> loadClubFeeRounds(String clubId) async {
    final json = _map(
      await _rpc(_client, 'get_club_fee_rounds', {'target_club_id': clubId}),
    );
    return (json['rounds'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ClubFeeRound.fromJson)
        .toList(growable: false);
  }

  @override
  Future<ClubFeeRoundDetail> loadClubFeeRound(
    String clubId,
    String roundId,
  ) async => ClubFeeRoundDetail.fromJson(
    _map(
      await _rpc(_client, 'get_club_fee_round', {
        'target_club_id': clubId,
        'target_round_id': roundId,
      }),
    ),
  );

  @override
  Future<String> saveClubFeeRound({
    required String clubId,
    required String? roundId,
    required ClubFeeRoundDraft draft,
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    final json = _map(
      await _rpc(_client, 'save_club_fee_round', {
        'target_club_id': clubId,
        'target_round_id': roundId,
        'payload': draft.toPayload(),
        'expected_revision': expectedRevision,
        'idempotency_key': idempotencyKey,
      }),
    );
    return json['round_id'] as String;
  }

  @override
  Future<void> decideClubFeeRound({
    required String clubId,
    required String roundId,
    required String decision,
    required int expectedRevision,
    required String idempotencyKey,
  }) => _rpc(_client, 'decide_club_fee_round', {
    'target_club_id': clubId,
    'target_round_id': roundId,
    'decision': decision,
    'expected_revision': expectedRevision,
    'idempotency_key': idempotencyKey,
  });

  @override
  Future<void> markClubFees({
    required String clubId,
    required List<ClubFee> fees,
    required String decision,
    DateTime? paidOn,
    String? method,
    String? note,
    required String idempotencyKey,
  }) => _rpc(_client, 'mark_club_fees', {
    'target_club_id': clubId,
    'target_fees': [
      for (final fee in fees) {'fee_id': fee.feeId, 'revision': fee.revision},
    ],
    'decision': decision,
    'new_paid_on': paidOn == null ? null : clubFeeDay(paidOn),
    'new_method': method,
    'new_note': note,
    'idempotency_key': idempotencyKey,
  });

  @override
  Future<List<ClubFamilyMember>> loadClubFamilies(String clubId) async {
    final json = _map(
      await _rpc(_client, 'get_club_families', {'target_club_id': clubId}),
    );
    return (json['members'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ClubFamilyMember.fromJson)
        .toList(growable: false);
  }

  @override
  Future<void> changeClubFamily({
    required String clubId,
    required String change,
    required List<String> personIds,
    required String idempotencyKey,
  }) => _rpc(_client, 'change_club_family', {
    'target_club_id': clubId,
    'change': change,
    'target_person_ids': personIds,
    'idempotency_key': idempotencyKey,
  });
}

/// Membership services that also handle the club's fees.
abstract interface class ClubFeesProvider {
  ClubFeeServices get clubFees;
}

/// yyyy-mm-dd, as the server reads a day.
String clubFeeDay(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

/// A round's fees as CSV for the treasurer: semicolons and a BOM, so Excel
/// opens it in Swedish. Amounts in kronor with a decimal comma.
String clubFeesCsv(
  List<ClubFee> fees, {
  required String Function(String? category) categoryLabel,
  required String Function(ClubFee fee) stateLabel,
  required String Function(String? method) methodLabel,
}) {
  String cell(Object? value) {
    final text = '${value ?? ''}';
    return text.contains(RegExp('[;"\n]'))
        ? '"${text.replaceAll('"', '""')}"'
        : text;
  }

  String kronor(int minor) =>
      '${minor ~/ 100},${(minor % 100).toString().padLeft(2, '0')}';
  final lines = <List<Object?>>[
    [
      'Namn',
      'Kategori',
      'Betalas av',
      'Belopp',
      'Rabatt',
      'Status',
      'Betald',
      'Sätt',
      'Anteckning',
    ],
    for (final fee in fees)
      [
        fee.name,
        fee.category == null ? null : categoryLabel(fee.category),
        fee.guardians.join(', '),
        kronor(fee.amount),
        kronor(fee.discountAmount),
        stateLabel(fee),
        fee.paidOn == null ? null : clubFeeDay(fee.paidOn!),
        fee.paymentMethod == null ? null : methodLabel(fee.paymentMethod),
        fee.note,
      ],
  ];
  return '﻿${lines.map((line) => line.map(cell).join(';')).join('\r\n')}\r\n';
}
