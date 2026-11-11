import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/core/identity/identity_services.dart';
import 'package:teamzone_app/src/core/supabase/supabase_bootstrap.dart';
import 'package:teamzone_app/src/features/membership/club_fees.dart';
import 'package:teamzone_app/src/features/membership/club_register.dart';
import 'package:teamzone_app/src/features/membership/membership_services.dart';
import 'package:teamzone_app/src/features/overview/overview_models.dart';
import 'package:teamzone_app/src/features/overview/overview_services.dart';

// Avgifter och familjer (club-members-and-fees.md, step 2).
void main() {
  Future<_Fees> openFees(WidgetTester tester, Set<String> capabilities) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fees = _Fees();
    await tester.pumpWidget(
      TeamZoneApp(
        environment: const AppEnvironment(name: 'audit'),
        locale: const Locale('sv'),
        services: AppServices(
          identity: _Identity(capabilities),
          membership: _Membership(fees),
          overview: _ClubOverview(),
          isConfigured: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.byKey(const ValueKey('club-home-club')));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.byKey(const ValueKey('club-admin-fees')));
    await tester.pumpAndSettle();
    return fees;
  }

  testWidgets('a membership round with the family rule is created and issued', (
    tester,
  ) async {
    final fees = await openFees(tester, {'club.memberships.manage'});
    expect(find.text('Medlemsavgift 2026'), findsOneWidget);
    expect(find.text('3 obetalda\n600 kr av 1 900 kr'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('club-fees-new')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('club-fee-amount-youth')),
      '300',
    );
    await tester.enterText(
      find.byKey(const ValueKey('club-fee-amount-adult')),
      '500',
    );
    await tester.enterText(
      find.byKey(const ValueKey('club-fee-sibling')),
      '50',
    );
    await tester.enterText(find.byKey(const ValueKey('club-fee-cap')), '400');
    await _tapVisible(tester, find.byKey(const ValueKey('club-fee-save')));
    await tester.pumpAndSettle();
    final payload = fees.saved.single;
    expect(payload['kind'], 'membership');
    expect(payload['amount_youth'], 30000);
    expect(payload['amount_adult'], 50000);
    expect(payload.containsKey('amount_supporter'), isFalse);
    expect(payload['sibling_discount_percent'], 50);
    expect(payload['family_cap'], 40000);
    expect(payload['title'], startsWith('Medlemsavgift '));

    // The draft's fees: the family rule shown per fee.
    expect(find.byKey(const ValueKey('club-fee-round')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('club-fee-summary'))).data,
      '2 att betala · 400 kr · familjerabatt 500 kr',
    );
    expect(find.text('täcks av familjetaket'), findsOneWidget);
    expect(find.text('rabatt 200 kr'), findsOneWidget);
    expect(
      find.text(
        'Barn och ungdom · betalas av Föräldern · familj med Bertil, Cissi',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('club-fee-missing')), findsOneWidget);

    await _tapVisible(tester, find.byKey(const ValueKey('club-fee-issue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('club-fee-confirm')));
    await tester.pumpAndSettle();
    expect(fees.decisions, [(round: 'r2', decision: 'issue', rev: 1)]);
    expect(find.text('Avgifterna är skapade.'), findsOneWidget);
    expect(find.byKey(const ValueKey('club-fee-issue')), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('families are split, merged and reset by hand', (tester) async {
    final fees = await openFees(tester, {'club.memberships.manage'});
    await tester.tap(find.byKey(const ValueKey('club-fees-families')));
    await tester.pumpAndSettle();
    expect(find.text('Alva, Bertil'), findsOneWidget);
    expect(find.text('Ändrad för hand'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('club-family-split-bertil')));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.byKey(const ValueKey('club-family-add-k1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('club-family-pick-alva')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('club-family-pick-cissi')));
    await tester.pumpAndSettle();
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('club-family-reset-k2')),
    );
    await tester.pumpAndSettle();
    expect(fees.changes.map((c) => '${c.$1} ${c.$2.join(',')}'), [
      'split bertil',
      'merge alva,cissi',
      'reset cissi',
    ]);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('fees are marked paid together, waived and exported', (
    tester,
  ) async {
    final exported = <String>[];
    final original = saveClubRegisterCsv;
    saveClubRegisterCsv = (name, csv) async {
      exported.add(csv);
      return true;
    };
    addTearDown(() => saveClubRegisterCsv = original);
    final fees = await openFees(tester, {'economy.manage'});
    await tester.tap(find.byKey(const ValueKey('club-fee-round-r1')));
    await tester.pumpAndSettle();
    String summary() => tester
        .widget<Text>(find.byKey(const ValueKey('club-fee-payment-summary')))
        .data!;
    expect(summary(), 'Betalt 0 · 0 kr   Obetalt 2 · 400 kr');
    expect(find.text('Täcks av familjetaket · betalas av Föräldern'), findsOne);

    // Both unpaid at once, by bank.
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('club-fee-select-open')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Markera betalda (2)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('club-fee-mark-paid')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('club-fee-method-bank')));
    await tester.enterText(find.byKey(const ValueKey('club-fee-note')), 'OCR');
    await tester.tap(find.byKey(const ValueKey('club-fee-paid-save')));
    await tester.pumpAndSettle();
    expect(fees.marks, ['paid fee-alva,fee-bertil bank OCR']);
    expect(find.text('2 markerade som betalda'), findsOneWidget);
    for (final messenger in tester.stateList<ScaffoldMessengerState>(
      find.byType(ScaffoldMessenger),
    )) {
      messenger.removeCurrentSnackBar();
    }
    await tester.pumpAndSettle();

    // One waived with a reason; the capped one has nothing to pay.
    await _tapVisible(tester, find.byKey(const ValueKey('club-fee-alva')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('club-fee-sheet-waive')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('club-fee-waive-note')),
      'Syskon i annan klubb',
    );
    await tester.tap(find.byKey(const ValueKey('club-fee-waive-save')));
    await tester.pumpAndSettle();
    expect(fees.marks.last, 'waived fee-alva - Syskon i annan klubb');
    await _tapVisible(tester, find.byKey(const ValueKey('club-fee-cissi')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('club-fee-sheet-paid')), findsNothing);
    expect(find.byKey(const ValueKey('club-fee-sheet-reopen')), findsNothing);
    Navigator.of(
      tester.element(find.byKey(const ValueKey('club-fee-sheet'))),
    ).pop();
    await tester.pumpAndSettle();

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('club-fee-filter-waived')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('club-fee-alva')), findsNothing);
    expect(find.byKey(const ValueKey('club-fee-cissi')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('club-fee-export')));
    await tester.pumpAndSettle();
    final lines = exported.single.split('\r\n');
    expect(lines.first, startsWith('﻿Namn;Kategori;Betalas av;Belopp'));
    expect(lines[1], 'Alva;Barn och ungdom;Föräldern;300,00;0,00;Obetald;;;');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('the treasurer sees only the fees on the Klubb page', (
    tester,
  ) async {
    await openFees(tester, {'economy.manage'});
    expect(find.byKey(const ValueKey('club-fees')), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator).last).pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('club-admin-fees')), findsOneWidget);
    expect(find.byKey(const ValueKey('club-admin-register')), findsNothing);
    expect(find.byKey(const ValueKey('club-admin-applications')), findsNothing);
    expect(find.text('Lag och uppdrag'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  test('kronor are shown and read in Swedish', () {
    expect(clubFeeKronor(190000), '1 900 kr');
    expect(clubFeeKronor(30050), '300,50 kr');
    expect(clubFeeMinorFrom('1 200,5'), 120050);
    expect(clubFeeMinorFrom('abc'), isNull);
    expect(clubFeeMinorFrom(''), isNull);
  });
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}

class _Identity implements IdentityServices {
  _Identity(this.capabilities);
  final Set<String> capabilities;
  @override
  SessionStatus get sessionStatus => SessionStatus.authenticated;
  @override
  Stream<SessionStatus> get sessionChanges => const Stream.empty();
  @override
  Future<TeamZoneProfile> getProfile() async =>
      const TeamZoneProfile(id: 'profile', displayName: 'Admin', locale: 'sv');
  @override
  Future<List<TeamZoneContext>> getContexts() async => [
    TeamZoneContext(
      id: 'club-ctx',
      clubId: 'club-a',
      clubName: 'Demoklubben IF',
      rolePackage: 'club_functionary',
      capabilities: capabilities,
    ),
  ];
  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}
  @override
  Future<void> signOut() async {}
}

class _Membership extends UnconfiguredMembershipServices
    implements ClubFeesProvider {
  _Membership(this.clubFees);
  @override
  final ClubFeeServices clubFees;
}

Map<String, dynamic> _fee(
  String id,
  String name,
  int base,
  int discount, {
  bool issued = false,
  String key = 'k1',
  List<String> guardians = const ['Föräldern'],
}) => {
  if (issued) 'fee_id': 'fee-$id',
  if (issued) 'revision': 1,
  'person_id': id,
  'name': name,
  'category': 'youth',
  'family_key': key,
  'base_amount': base,
  'discount_amount': discount,
  'amount': base - discount,
  'state': base == discount ? 'waived' : 'open',
  'guardians': guardians,
};

class _Fees implements ClubFeeServices {
  final saved = <Map<String, Object?>>[];
  final decisions = <({String round, String decision, int rev})>[];
  final changes = <(String, List<String>)>[];
  final marks = <String>[];
  var _issued = false;
  bool _isIssued(String roundId) => roundId == 'r1' || _issued;

  @override
  Future<List<ClubFeeRound>> loadClubFeeRounds(String clubId) async => [
    ClubFeeRound.fromJson({
      'round_id': 'r1',
      'kind': 'membership',
      'title': 'Medlemsavgift 2026',
      'due_on': '2026-03-31',
      'amounts': {'youth': 30000},
      'state': 'issued',
      'revision': 2,
      'fee_count': 5,
      'total': 190000,
      'open_count': 3,
      'paid_total': 60000,
    }),
  ];

  @override
  Future<ClubFeeRoundDetail> loadClubFeeRound(
    String clubId,
    String roundId,
  ) async => ClubFeeRoundDetail.fromJson({
    'round_id': roundId,
    'kind': 'membership',
    'title': 'Medlemsavgift 2027',
    'due_on': '2027-03-31',
    'amounts': {'youth': 30000, 'adult': 50000},
    'family_cap': 40000,
    'sibling_discount_percent': 50,
    'state': _isIssued(roundId) ? 'issued' : 'draft',
    'revision': _isIssued(roundId) ? 2 : 1,
    'fees': [
      _fee('alva', 'Alva', 30000, 0, issued: _isIssued(roundId)),
      _fee('bertil', 'Bertil', 30000, 20000, issued: _isIssued(roundId)),
      _fee('cissi', 'Cissi', 30000, 30000, issued: _isIssued(roundId)),
    ],
    'missing': _isIssued(roundId) ? [] : ['Admin'],
  });

  @override
  Future<String> saveClubFeeRound({
    required String clubId,
    required String? roundId,
    required ClubFeeRoundDraft draft,
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    saved.add(draft.toPayload());
    return 'r2';
  }

  @override
  Future<void> decideClubFeeRound({
    required String clubId,
    required String roundId,
    required String decision,
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    decisions.add((round: roundId, decision: decision, rev: expectedRevision));
    _issued = decision == 'issue';
  }

  @override
  Future<void> markClubFees({
    required String clubId,
    required List<ClubFee> fees,
    required String decision,
    DateTime? paidOn,
    String? method,
    String? note,
    required String idempotencyKey,
  }) async => marks.add(
    '$decision ${fees.map((fee) => fee.feeId).join(',')} ${method ?? '-'} ${note ?? '-'}',
  );

  @override
  Future<List<ClubFamilyMember>> loadClubFamilies(String clubId) async => [
    for (final (id, name, key, manual) in [
      ('alva', 'Alva', 'k1', false),
      ('bertil', 'Bertil', 'k1', false),
      ('cissi', 'Cissi', 'k2', true),
      ('dan', 'Dan', 'dan', false),
    ])
      ClubFamilyMember.fromJson({
        'person_id': id,
        'name': name,
        'category': 'youth',
        'family_key': key,
        'manual': manual,
        'guardians': const <String>[],
      }),
  ];

  @override
  Future<void> changeClubFamily({
    required String clubId,
    required String change,
    required List<String> personIds,
    required String idempotencyKey,
  }) async => changes.add((change, personIds));
}

class _ClubOverview extends UnconfiguredOverviewServices
    implements ClubHomeServices {
  @override
  Future<MainSurfacesProjection> load({
    required List<String> contextIds,
  }) async => MainSurfacesProjection.fromJson({
    'schema_version': 1,
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'sync_cursor': '',
    'contexts': const [],
    'actions': const [],
    'home': {
      'upcoming_count': 0,
      'pending_callup_count': 0,
      'next_event': null,
    },
    'inbox': {'messages_available': false, 'pending_notification_count': 0},
    'statistics': {
      'present': 0,
      'late': 0,
      'partial': 0,
      'absent': 0,
      'unknown': 0,
    },
  });
  @override
  Future<ClubHome> loadClubHome(String contextId) async => ClubHome.fromJson({
    'club_id': 'club-a',
    'members': <String, dynamic>{
      'pending_applications': 0,
      'pending_team_requests': 0,
    },
    'can_announce': false,
    'teams': [
      <String, dynamic>{
        'team_id': 'p2014',
        'name': 'P2014',
        'member_count': 10,
        'upcoming': const [],
      },
    ],
  });
}
