import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/team_development/player_talk_editor.dart';
import 'package:teamzone_app/src/features/team_development/player_talk_services.dart';
import 'package:teamzone_app/src/features/team_development/player_talks_view.dart';
import 'package:teamzone_app/src/features/team_development/team_survey_services.dart';

/// Keeps talks as the server does: a save needs the revision it has.
class _FakeTalks implements PlayerTalkServices {
  PlayerTalk? stored;
  final saves = <PlayerTalkDraft>[];
  final deleted = <String>[];

  /// The next save lands but its answer is lost; or does not land at all.
  bool loseAnswer = false, offline = false, canEdit = true;

  @override
  Future<PlayerTalks> list(String teamId, String personId) async => PlayerTalks(
    name: 'Ada',
    canEdit: canEdit,
    isPlayer: true,
    leaders: const [
      TalkLeader(personId: 'l1', name: 'Coach', self: true),
      TalkLeader(personId: 'l2', name: 'Dan'),
    ],
    talks: [?stored],
  );

  @override
  Future<int> save(
    String teamId,
    String personId,
    PlayerTalkDraft draft,
    int? expectedRevision,
  ) async {
    if (offline) throw Exception('offline');
    if (stored?.revision != expectedRevision) {
      throw const PlayerTalkException(PlayerTalkException.conflict);
    }
    saves.add(draft);
    stored = PlayerTalk(
      id: draft.id,
      talkedOn: draft.talkedOn,
      revision: (expectedRevision ?? 0) + 1,
      leaders: [
        for (final id in draft.leaderIds) TalkLeader(personId: id, name: id),
      ],
      responseId: draft.responseId,
      leaderNotes: draft.leaderNotes,
      agreed: draft.agreed,
    );
    if (loseAnswer) {
      loseAnswer = false;
      throw Exception('timeout');
    }
    return stored!.revision;
  }

  @override
  Future<void> delete(String talkId, int expectedRevision) async =>
      deleted.add('$talkId $expectedRevision');
}

final _answer = PlayerSurveyAnswer(
  surveyId: 's1',
  responseId: 'r1',
  title: 'Inför spelarsamtal',
  questions: const [],
  answers: const {},
  updatedAt: DateTime(2026, 11, 22),
);

void main() {
  late _FakeTalks talks;
  setUp(() => PlayerTalksFeature.services = talks = _FakeTalks());
  tearDown(
    () => PlayerTalksFeature.services = const UnconfiguredPlayerTalkServices(),
  );

  Widget app(Widget home) => MaterialApp(
    locale: const Locale('sv'),
    supportedLocales: const [Locale('sv')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: home,
  );

  Future<void> open(
    WidgetTester tester, {
    PlayerTalk? talk,
    Size size = const Size(400, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final data = await talks.list('t1', 'p1');
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PlayerTalkEditor(
                  teamId: 't1',
                  personId: 'p1',
                  talks: data,
                  talk: talk,
                  answers: [_answer],
                  responseId: talk == null ? 'r1' : null,
                  answerView: (_) => const Text('SVAREN'),
                ),
              ),
            ),
            child: const Text('start'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
  }

  Future<void> write(WidgetTester tester, String key, String text) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.enterText(find.byKey(Key(key)), text);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  }

  String status(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('talk-status'))).data!;

  testWidgets('a talk is saved as it is written, from a survey answer', (
    tester,
  ) async {
    await open(tester);
    expect(talks.saves, isEmpty, reason: 'nothing before something is written');
    await write(tester, 'talk-notes', 'Vill spela centralt');
    expect(status(tester), 'Sparat');
    await write(tester, 'talk-agreed', 'Vänsterfoten');
    expect(talks.saves, hasLength(2));
    expect(talks.stored!.leaderNotes, 'Vill spela centralt');
    expect(talks.stored!.agreed, 'Vänsterfoten');
    expect(talks.stored!.responseId, 'r1');
    expect(talks.stored!.leaders.single.personId, 'l1', reason: 'the writer');
    expect(talks.saves.first.id, talks.saves.last.id);
  });

  testWidgets('leaving at once saves first', (tester) async {
    await open(tester);
    await tester.enterText(find.byKey(const Key('talk-notes')), 'Snabbt');
    await tester.pump();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(talks.stored!.leaderNotes, 'Snabbt');
    expect(find.text('start'), findsOneWidget, reason: 'the page is left');
  });

  testWidgets('leaving an untouched new talk saves nothing', (tester) async {
    await open(tester);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(talks.stored, isNull);
    expect(find.text('start'), findsOneWidget);
  });

  testWidgets('a lost answer is not mistaken for someone else\'s change', (
    tester,
  ) async {
    await open(tester);
    await write(tester, 'talk-notes', 'Ett');
    talks.loseAnswer = true;
    await write(tester, 'talk-notes', 'Ett två');
    expect(status(tester), 'Inte sparat');
    await write(tester, 'talk-notes', 'Ett två tre');
    expect(status(tester), 'Sparat');
    expect(talks.stored!.leaderNotes, 'Ett två tre');
  });

  testWidgets('someone else\'s change is never overwritten', (tester) async {
    await open(tester);
    await write(tester, 'talk-notes', 'Mitt');
    final mine = talks.stored!;
    talks.stored = PlayerTalk(
      id: mine.id,
      talkedOn: mine.talkedOn,
      revision: mine.revision + 1,
      leaderNotes: 'Någon annans',
    );
    await write(tester, 'talk-notes', 'Mitt igen');
    expect(status(tester), 'Inte sparat');
    expect(find.text('Kopiera texten'), findsOneWidget);
    expect(talks.stored!.leaderNotes, 'Någon annans');
    await write(tester, 'talk-notes', 'Mitt en gång till');
    expect(talks.stored!.leaderNotes, 'Någon annans');
  });

  testWidgets('leaving unsaved text warns, and the text can be saved later', (
    tester,
  ) async {
    await open(tester);
    talks.offline = true;
    await write(tester, 'talk-notes', 'Utan nät');
    expect(status(tester), 'Inte sparat');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Texten är inte sparad'), findsOneWidget);
    await tester.tap(find.text('Stanna kvar'));
    await tester.pumpAndSettle();
    talks.offline = false;
    await tester.tap(find.text('Försök igen'));
    await tester.pumpAndSettle();
    expect(talks.stored!.leaderNotes, 'Utan nät');
    expect(status(tester), 'Sparat');
  });

  testWidgets('a talk is deleted after two confirmations', (tester) async {
    final talk = talks.stored = PlayerTalk(
      id: 'x1',
      talkedOn: DateTime(2026, 11, 20),
      revision: 4,
      leaderNotes: 'N',
    );
    await open(tester, talk: talk);
    await tester.tap(find.byKey(const Key('talk-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('survey-delete-continue')));
    await tester.pumpAndSettle();
    expect(talks.deleted, isEmpty);
    await tester.tap(find.byKey(const Key('survey-delete-confirm')));
    await tester.pumpAndSettle();
    expect(talks.deleted, ['x1 4']);
    expect(find.text('start'), findsOneWidget);
  });

  testWidgets('the answers show beside on a wide screen, above on a phone', (
    tester,
  ) async {
    await open(tester, size: const Size(1200, 900));
    expect(find.text('SVAREN'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('SVAREN')).dx,
      lessThan(tester.getTopLeft(find.byKey(const Key('talk-notes'))).dx),
    );
    await tester.pumpWidget(const SizedBox());
    await open(tester);
    expect(find.text('SVAREN'), findsNothing);
    await tester.tap(find.byKey(const Key('talk-answers')));
    await tester.pumpAndSettle();
    expect(find.text('SVAREN'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a reader cannot write or delete', (tester) async {
    talks.canEdit = false;
    final talk = talks.stored = PlayerTalk(
      id: 'x1',
      talkedOn: DateTime(2026, 11, 20),
      revision: 1,
      leaderNotes: 'N',
    );
    await open(tester, talk: talk);
    expect(find.byKey(const Key('talk-delete')), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('talk-notes')))
          .readOnly,
      isTrue,
    );
  });

  testWidgets('the profile lists the talks', (tester) async {
    talks.stored = PlayerTalk(
      id: 'x1',
      talkedOn: DateTime(2026, 11, 20),
      revision: 1,
      surveyTitle: 'Inför spelarsamtal',
      leaders: const [TalkLeader(personId: 'l1', name: 'Coach')],
      agreed: 'Vänsterfoten',
    );
    await tester.pumpWidget(
      app(
        Scaffold(
          body: PlayerTalksView(
            teamId: 't1',
            personId: 'p1',
            answerView: (_) => const SizedBox(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2026-11-20'), findsOneWidget);
    expect(find.text('Coach · Inför spelarsamtal'), findsOneWidget);
    expect(find.text('Överens om: Vänsterfoten'), findsOneWidget);
    expect(find.byKey(const Key('talk-new')), findsOneWidget);
  });

  test('ids and days are as the server takes them', () {
    expect(
      newPlayerTalkId(),
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(
      PlayerTalkDraft(
        id: 'x',
        talkedOn: DateTime(2026, 3, 5),
        leaderIds: const {},
        leaderNotes: '',
        agreed: '',
      ).day,
      '2026-03-05',
    );
  });
}
