import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/calendar/club_referee_pay.dart';
import 'package:teamzone_app/src/features/calendar/club_referees.dart';
import 'package:teamzone_app/src/features/calendar/event_referees.dart';
import 'package:teamzone_app/src/features/calendar/referee_services.dart';

Map<String, dynamic> _match(String id) => {
  'event_id': id,
  'title': 'Match',
  'starts_at': DateTime(2026, 10, 10, 10).toUtc().toIso8601String(),
  'ends_at': DateTime(2026, 10, 10, 11).toUtc().toIso8601String(),
  'team_name': 'P10',
  'club_name': 'IF Eksjö Fotboll',
  'opponent_name': 'Aneby',
  'home_away': 'home',
  'referee_slots': 2,
};

Map<String, dynamic> _report(
  String id,
  String name, {
  String state = 'pending',
  String slot = 'main',
  int amount = 200,
  String? control,
  String? payout,
}) => {
  'id': id,
  'slot': slot,
  'name': name,
  'person_id': 'p-$id',
  'amount': amount,
  'state': state,
  'control_state': control,
  'control_note': control == 'confirmed' ? 'Hela matchen' : null,
  'payout_id': payout,
  'match': _match('e-$id'),
};

final _payoutJson = {
  'id': 'po1',
  'through_date': '2026-10-18',
  'state': 'draft',
  'total': 30250,
  'line_count': 2,
  'limit': 29600,
  'lines': [
    {
      'id': 'l1',
      'name': 'Elin Domare',
      'report_count': 1,
      'amount': 150,
      'year_total': 150,
      'age': 17,
    },
    {
      'id': 'l2',
      'name': 'Max Domare',
      'report_count': 2,
      'amount': 30100,
      'year_total': 30100,
      'age': 13,
      'guardians': 'Gun Förälder',
    },
  ],
  'reports': [
    {
      'name': 'Max Domare',
      'slot': 'main',
      'amount': 250,
      'starts_at': DateTime(2026, 10, 10, 10).toUtc().toIso8601String(),
      'team_name': 'P10',
      'opponent_name': 'Aneby; IF',
    },
  ],
};

class _Services extends UnconfiguredRefereeServices {
  final calls = <String>[];
  bool paid = false;
  bool answered = false;

  @override
  Future<ClubRefereeReports> reports(String clubId, {String? state}) async =>
      ClubRefereeReports.fromJson({
        'reports':
            state == 'pending' && !calls.any((c) => c.startsWith('decide'))
            ? [
                _report('r1', 'Max Domare', control: 'confirmed'),
                _report('r2', 'Elin Domare', slot: 'assistant_1', amount: 120),
              ]
            : [],
        'counts': {'pending': 2, 'approved': 1},
        'can_manage': true,
      });

  @override
  Future<int> decideReports(
    String clubId,
    List<String> reportIds,
    bool approve, {
    String? reason,
  }) async {
    calls.add(
      'decide:${(reportIds.toList()..sort()).join(',')}:$approve:$reason',
    );
    return reportIds.length;
  }

  @override
  Future<void> askControl(String reportId) async => calls.add('ask:$reportId');

  @override
  Future<ClubRefereeFees> fees(String clubId) async =>
      ClubRefereeFees.fromJson({
        'club': {'fee_main': 150, 'fee_assistant': 100},
        'teams': [
          {'team_id': 'p10', 'team_name': 'P10'},
        ],
      });

  @override
  Future<int> saveFee(
    String clubId,
    String? teamId,
    int? main,
    int? assistant,
  ) async {
    calls.add('fee:$teamId:$main:$assistant');
    return 2;
  }

  @override
  Future<RefereePayouts> payouts(String clubId) async =>
      RefereePayouts.fromJson({
        'payouts': [],
        'ready_count': 3,
        'ready_total': 30250,
        'payers': [
          {'person_id': 'lena', 'name': 'Lena Kassör'},
        ],
        'can_appoint_payers': true,
      });

  @override
  Future<String> createPayout(String clubId, DateTime throughDate) async {
    calls.add('create:$clubId');
    return 'po1';
  }

  @override
  Future<RefereePayout> payout(String payoutId) async =>
      RefereePayout.fromJson({..._payoutJson, if (paid) 'state': 'paid'});

  @override
  Future<void> markPayoutPaid(String payoutId) async {
    calls.add('paid:$payoutId');
    paid = true;
  }

  @override
  Future<List<MyRefereePay>> myPay() async => [
    MyRefereePay.fromJson({
      'person_id': 'elin',
      'name': 'Elin Domare',
      'year': 2026,
      'year_total': 1250,
      'limit': 29600,
      'can_note': true,
      'reports': [_report('r2', 'Elin Domare', amount: 120)],
    }),
  ];

  @override
  Future<void> noteReport(String reportId, String note) async =>
      calls.add('note:$reportId:$note');

  @override
  Future<EventRefereeView> getEventReferees(String eventId) async =>
      EventRefereeView.fromJson({
        'slots': 1,
        'referee_kind': 'club',
        'can_manage': true,
        'referees': [
          {
            'id': 'er1',
            'slot': 'main',
            'state': 'confirmed',
            'name': 'Max Domare',
            'kind': 'club',
          },
        ],
        'control_questions': answered
            ? []
            : [
                {'id': 'r1', 'slot': 'main', 'name': 'Max Domare'},
              ],
      });

  @override
  Future<void> answerControl(
    String reportId,
    bool confirmed, {
    String? note,
  }) async {
    calls.add('answer:$reportId:$confirmed:$note');
    answered = true;
  }

  @override
  Future<RefereeSummary> summary() async => RefereeSummary.fromJson({
    'coordinator_clubs': [
      {
        'club_id': 'eksjo',
        'club_name': 'IF Eksjö Fotboll',
        'can_manage': false,
        'can_pay': true,
        'pending_reports': 4,
      },
    ],
  });
}

Widget _page(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  test('kronor and the payout export', () {
    expect(formatKronor(30250), '30 250 kr');
    expect(formatKronor(150), '150 kr');
    final csv = refereePayoutCsv(RefereePayout.fromJson(_payoutJson));
    expect(csv.startsWith('﻿Namn;Antal uppdrag;Belopp (kr)'), isTrue);
    expect(csv, contains('Max Domare;2;30100;Gun Förälder;30100\r\n'));
    expect(csv, contains('Summa;;30250;;\r\n'));
    expect(csv, contains('2026-10-10;P10;"Aneby; IF";Huvuddomare;250'));
  });

  testWidgets('the domaransvarig approves all and sends a control question', (
    tester,
  ) async {
    final services = _Services();
    await tester.pumpWidget(
      _page(ClubRefereeReportsView(services: services, clubId: 'eksjo')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Att godkänna (2)'), findsOneWidget);
    expect(
      find.textContaining('Ledaren bekräftar: Hela matchen'),
      findsOneWidget,
    );
    expect(find.textContaining('Max Domare · 200'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('referee-report-menu-r2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skicka kontrollfråga till ledaren'));
    await tester.pumpAndSettle();
    expect(services.calls.last, 'ask:r2');

    await tester.tap(find.byKey(const ValueKey('referee-reports-select-all')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('referee-reports-approve-selected')),
    );
    await tester.pumpAndSettle();
    expect(services.calls.last, 'decide:r1,r2:true:null');
    expect(find.text('2 uppdrag är godkända.'), findsOneWidget);
  });

  testWidgets('a team fee is set in kronor', (tester) async {
    final services = _Services();
    await tester.pumpWidget(
      _page(
        SingleChildScrollView(
          child: ClubRefereeFeesSection(services: services, clubId: 'eksjo'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Klubbens arvode'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('referee-fee-p10')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('referee-fee-main')),
      '200',
    );
    await tester.enterText(
      find.byKey(const ValueKey('referee-fee-assistant')),
      '120',
    );
    await tester.tap(find.byKey(const ValueKey('referee-fee-save')));
    await tester.pumpAndSettle();
    expect(services.calls.last, 'fee:p10:200:120');
    expect(find.textContaining('2 uppdrag att godkänna'), findsOneWidget);
  });

  testWidgets('the payer makes a list, exports it and marks it paid', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final saved = <String>[];
    final original = saveRefereePayoutCsv;
    saveRefereePayoutCsv = (name, csv) async {
      saved.add(name);
      return true;
    };
    addTearDown(() => saveRefereePayoutCsv = original);
    final services = _Services();
    await tester.pumpWidget(
      MaterialApp(
        home: ClubRefereeBoardPage(
          services: services,
          clubId: 'eksjo',
          clubName: 'IF Eksjö Fotboll',
          canManage: false,
          canPay: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Domarersättning · IF Eksjö Fotboll'), findsOneWidget);
    expect(find.text('Matcher'), findsNothing);
    expect(find.textContaining('3 godkända uppdrag'), findsOneWidget);
    expect(find.text('Lena Kassör'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('referee-payout-create')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(services.calls.last, 'create:eksjo');
    expect(find.text('Utbetalningslista'), findsOneWidget);
    expect(find.textContaining('vårdnadshavare: Gun Förälder'), findsOneWidget);
    expect(find.byTooltip('Över halva prisbasbeloppet i år'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('referee-payout-export')));
    await tester.pumpAndSettle();
    expect(saved, ['domarersattning-2026-10-18.csv']);

    await tester.tap(find.byKey(const ValueKey('referee-payout-paid')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('referee-payout-paid-confirm')));
    await tester.pumpAndSettle();
    expect(services.calls.last, 'paid:po1');
    expect(find.byKey(const ValueKey('referee-payout-paid')), findsNothing);
  });

  testWidgets('the home page has no card for the one who only pays', (
    tester,
  ) async {
    await tester.pumpWidget(_page(RefereeHomeCards(services: _Services())));
    await tester.pumpAndSettle();
    expect(find.text('Domarersättning'), findsNothing);
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('the referee sees the pay and leaves a note', (tester) async {
    final services = _Services();
    await tester.pumpWidget(
      _page(
        SingleChildScrollView(child: MyRefereePaySection(services: services)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('2026: 1 250 kr'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('my-referee-note-r2')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('referee-text-field')),
      'Matchen blev inte av',
    );
    await tester.tap(find.byKey(const ValueKey('referee-text-save')));
    await tester.pumpAndSettle();
    expect(services.calls.last, 'note:r2:Matchen blev inte av');
  });

  testWidgets('the leader answers the control question on the match', (
    tester,
  ) async {
    final services = _Services();
    await tester.pumpWidget(
      _page(
        SingleChildScrollView(
          child: EventRefereesSection(eventId: 'e1', services: services),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('dömde Max Domare matchen som huvuddomare?'),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('event-referee-control-yes-r1')),
    );
    await tester.pumpAndSettle();
    expect(services.calls.last, 'answer:r1:true:null');
    expect(find.textContaining('Kontrollfråga'), findsNothing);
  });
}
