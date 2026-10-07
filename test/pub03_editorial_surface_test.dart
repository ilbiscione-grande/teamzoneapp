import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/core/identity/identity_services.dart';
import 'package:teamzone_app/src/core/supabase/supabase_bootstrap.dart';
import 'package:teamzone_app/src/features/publication/editorial_models.dart';
import 'package:teamzone_app/src/features/publication/editorial_services.dart';

void main() {
  testWidgets('team settings save results and training for the whole team', (
    tester,
  ) async {
    final editorial = _Editorial();
    await tester.pumpWidget(_app(editorial, canPublish: true));
    await tester.pumpAndSettle();
    await _openPublicPagesSettings(tester);
    await tester.scrollUntilVisible(
      find.text('Publika matcher, resultat och träningstider'),
      250,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Publika matcher, resultat och träningstider'));
    await tester.pumpAndSettle();
    expect(find.text('Laginställningar · F2012'), findsOneWidget);
    await tester.tap(find.text('Visa matcher'));
    await tester.tap(find.text('Visa matchresultat'));
    await tester.scrollUntilVisible(
      find.text('Spara laginställningar'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Visa träningstider'));
    await tester.tap(find.text('Spara laginställningar'));
    await tester.pumpAndSettle();
    expect(editorial.teamResults, isTrue);
    expect(editorial.teamTraining, isTrue);
    expect(editorial.teamMatches, isTrue);
    expect(editorial.teamRevision, 1);
    expect(
      find.text('Lagets publiceringsinställningar är sparade.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'match presentation saves without individual visibility controls',
    (tester) async {
      final editorial = _Editorial();
      await tester.pumpWidget(_app(editorial, canPublish: true));
      await tester.pumpAndSettle();
      await _openNewsroom(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Event och partners'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Hantera publicering'));
      await tester.pumpAndSettle();
      expect(find.text('Gör privat'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Publicera'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Spara'));
      await tester.pumpAndSettle();
      expect(editorial.eventSaved, isTrue);
      expect(editorial.eventPublished, isFalse);
      expect(editorial.resultPublished, isFalse);
      expect(editorial.managementLoads, 2);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Uppdatera').last);
      await tester.pumpAndSettle();
      expect(editorial.managementLoads, 3);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'headline suggests a Swedish-safe address and previews unsaved text',
    (tester) async {
      final editorial = _Editorial();
      await tester.pumpWidget(_app(editorial, canPublish: true));
      await tester.pumpAndSettle();
      await _openNewsroom(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Ny artikel'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Rubrik'),
        'Årets första möte!',
      );
      expect(
        tester
            .widget<TextFormField>(
              find.widgetWithText(TextFormField, 'Adressnamn'),
            )
            .controller!
            .text,
        'arets-forsta-mote',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Artikeltext'),
        'Välkommen till klubben.\n\nVi ses på torsdag.',
      );
      await tester.tap(find.byTooltip('Förhandsgranska utkast').first);
      await tester.pumpAndSettle();
      expect(find.text('Årets första möte!'), findsOneWidget);
      expect(find.text('Välkommen till klubben.'), findsOneWidget);
      expect(find.text('Vi ses på torsdag.'), findsOneWidget);
      expect(
        find.text(
          'Endast förhandsgranskning i appen. Inget har sparats eller publicerats.',
        ),
        findsOneWidget,
      );
      expect(editorial.saved, isNull);
    },
  );

  testWidgets('manual article address survives later headline edits', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_Editorial(), canPublish: true));
    await tester.pumpAndSettle();
    await _openNewsroom(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Ny artikel'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Rubrik'),
      'Första rubriken',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Adressnamn'),
      'egen-adress',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Rubrik'),
      'Ändrad rubrik',
    );
    expect(
      tester
          .widget<TextFormField>(
            find.widgetWithText(TextFormField, 'Adressnamn'),
          )
          .controller!
          .text,
      'egen-adress',
    );
    await tester.tap(find.byTooltip('Föreslå adress från rubriken'));
    await tester.pump();
    expect(
      tester
          .widget<TextFormField>(
            find.widgetWithText(TextFormField, 'Adressnamn'),
          )
          .controller!
          .text,
      'andrad-rubrik',
    );
  });

  testWidgets('publisher creates a structured club news draft', (tester) async {
    final editorial = _Editorial();
    await tester.pumpWidget(_app(editorial, canPublish: true));
    await tester.pumpAndSettle();
    await _openNewsroom(tester);
    await tester.pumpAndSettle();
    expect(find.text('Inga artiklar ännu'), findsOneWidget);
    await tester.tap(find.byTooltip('Ny artikel'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Rubrik'),
      'Säsongen startar',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Adressnamn'),
      'sasongen-startar',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Artikeltext'),
      'Välkommen till en ny säsong.',
    );
    await tester.scrollUntilVisible(
      find.text('Spara utkast'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Spara utkast'));
    await tester.pumpAndSettle();
    expect(editorial.saved?.title, 'Säsongen startar');
    expect(editorial.saved?.blocks.single.type, 'paragraph');
    expect(find.text('Säsongen startar'), findsOneWidget);
  });

  testWidgets('editor shows publish action and explains unpublished club', (
    tester,
  ) async {
    final editorial = _Editorial()..saved = _draft();
    await tester.pumpWidget(_app(editorial, canPublish: true));
    await tester.pumpAndSettle();
    await _openNewsroom(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Säsongen startar'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Publicera nu'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Publicera nu'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Klubbsidan är inte publicerad'),
      findsOneWidget,
    );
    expect(editorial.transitionedTo, isNull);
  });

  testWidgets('a draft shows its image state and the image can be removed', (
    tester,
  ) async {
    final editorial = _Editorial(heroAssetId: 'asset')..saved = _draft();
    await tester.pumpWidget(_app(editorial, canPublish: true));
    await tester.pumpAndSettle();
    await _openNewsroom(tester);
    await tester.pumpAndSettle();
    // The list tells that the image is still being processed.
    expect(find.textContaining('Bilden bearbetas'), findsOneWidget);
    await tester.tap(find.text('Säsongen startar'));
    await tester.pumpAndSettle();
    final hero = find.byKey(const ValueKey('editorial-hero-image'));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('editorial-hero-remove')),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(
      find.descendant(of: hero, matching: find.text('Bilden bearbetas')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: hero,
        matching: find.widgetWithText(TextField, 'Bildbeskrivning'),
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('editorial-hero-remove')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('editorial-hero-remove')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: hero, matching: find.text('Ingen bild vald')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Spara utkast'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Spara utkast'));
    await tester.pumpAndSettle();
    // Removed on the article's new revision after the text was saved.
    expect(editorial.heroCalls, [(null, 2)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saving without image changes leaves the image alone', (
    tester,
  ) async {
    final editorial = _Editorial(heroAssetId: 'asset')..saved = _draft();
    await tester.pumpWidget(_app(editorial, canPublish: true));
    await tester.pumpAndSettle();
    await _openNewsroom(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Säsongen startar'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Spara utkast'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Spara utkast'));
    await tester.pumpAndSettle();
    expect(editorial.heroCalls, isEmpty);
  });

  testWidgets('editor confirms publication for a ready club', (tester) async {
    final editorial = _Editorial(clubPublished: true)..saved = _draft();
    await tester.pumpWidget(_app(editorial, canPublish: true));
    await tester.pumpAndSettle();
    await _openNewsroom(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Säsongen startar'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Publicera nu'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Publicera nu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Publicera nyheten?'), findsOneWidget);
    await tester.tap(find.text('Publicera nu').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(editorial.transitionedTo, 'published');
  });

  testWidgets('newsroom entry is hidden without publication capability', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_Editorial(), canPublish: false));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Nyhetsredaktion'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Inställningar').last,
      250,
      scrollable: find.descendant(
        of: find.byKey(const Key('app-navigation-panel-list')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.text('Inställningar').last);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(Tab, 'Publika sidor'), findsNothing);
    expect(find.widgetWithText(ListTile, 'Nyheter'), findsNothing);
  });

  test(
    'editor list RPC is capability scoped and table access stays closed',
    () {
      final sql = File(
        'supabase/migrations/20260828083753_pub03_editorial_list_for_actor.sql',
      ).readAsStringSync().toLowerCase();
      expect(
        sql,
        contains(
          "actor_has_capability(target_club_id,null,'publication.manage')",
        ),
      );
      expect(sql, contains('where article.club_id=target_club_id'));
      expect(sql, contains('security definer'));
      expect(sql, contains("set search_path=''"));
      expect(sql, contains('revoke all on function'));
      expect(sql, contains('to authenticated'));
      expect(sql, isNot(contains('grant select on')));
    },
  );

  test('draft save migration disambiguates article id without weakening gates', () {
    final sql = File(
      'supabase/migrations/20260925070651_pub03_disambiguate_editorial_draft_save.sql',
    ).readAsStringSync();
    expect(sql, contains('saved_article_id uuid'));
    expect(sql, contains('channel.article_id = saved_article_id'));
    expect(sql, contains('selected_team.team_id'));
    expect(sql, contains("'publication.manage'"));
    expect(sql, contains('article.revision <> expected_revision'));
    expect(sql, contains("'publication.article.save.v1'"));
    expect(sql, contains('internal.editorial_snapshot(article)'));
    expect(
      sql,
      isNot(
        contains(
          'where article_id=save_editorial_article_for_actor.target_article_id',
        ),
      ),
    );
  });
}

/// Settings › Publika sidor, where the newsroom sits next to the public pages.
Future<void> _openPublicPagesSettings(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Inställningar').last,
    250,
    scrollable: find.descendant(
      of: find.byKey(const Key('app-navigation-panel-list')),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.tap(find.text('Inställningar').last);
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(Tab, 'Publika sidor'));
  await tester.pumpAndSettle();
}

Future<void> _openNewsroom(WidgetTester tester) async {
  await _openPublicPagesSettings(tester);
  final news = find.widgetWithText(ListTile, 'Nyheter');
  await tester.scrollUntilVisible(
    news,
    250,
    scrollable: find
        .descendant(
          of: find.byType(ListView).last,
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.tap(news);
}

Widget _app(_Editorial editorial, {required bool canPublish}) => TeamZoneApp(
  environment: const AppEnvironment(name: 'pub03-editor'),
  locale: const Locale('sv'),
  services: AppServices(
    identity: _Identity(canPublish),
    editorial: editorial,
    isConfigured: true,
  ),
);

class _Editorial extends UnconfiguredEditorialServices {
  _Editorial({this.clubPublished = false, this.heroAssetId});
  final bool clubPublished;
  EditorialSaveInput? saved;
  String? heroAssetId;
  final List<(String?, int)> heroCalls = [];
  String? transitionedTo;
  bool eventPublished = false;
  bool eventSaved = false;
  bool resultPublished = false;
  int managementLoads = 0;
  bool teamResults = false, teamTraining = false, teamMatches = false;
  int teamRevision = 0;
  @override
  Future<Map<String, dynamic>> getTeamEventVisibility(String teamId) async => {
    'show_results': teamResults,
    'show_training': teamTraining,
    'show_matches': teamMatches,
    'revision': teamRevision,
  };
  @override
  Future<void> setTeamEventVisibility({
    required String teamId,
    required bool showResults,
    required bool showTraining,
    required bool showMatches,
    required int expectedRevision,
  }) async {
    expect(teamId, 'team');
    expect(expectedRevision, teamRevision);
    teamResults = showResults;
    teamTraining = showTraining;
    teamMatches = showMatches;
    teamRevision++;
  }

  @override
  Future<PublicationManagement> getPublicationManagement(String clubId) async {
    managementLoads++;
    return PublicationManagement(
      events: [
        PublicEventItem(
          id: 'match',
          teamName: 'F2012',
          title: 'Testmatch',
          eventType: 'match',
          startsAt: DateTime(2026, 9, 26),
          publicationState: eventPublished ? 'published' : 'private',
          revision: eventPublished ? 1 : 0,
          resultAvailable: true,
          scoreUs: 3,
          scoreOpponent: 1,
          publishResult: resultPublished,
        ),
      ],
      partners: const [],
      canManagePartners: false,
      mediaUploadStatus: 'not_configured',
    );
  }

  @override
  Future<void> configureEvent({
    required String eventId,
    required String state,
    String? publicTitle,
    required bool publishLocation,
    bool publishResult = false,
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    eventSaved = true;
    eventPublished = state == 'published';
    resultPublished = publishResult;
  }

  @override
  Future<DomainManagement> getDomainManagement(String clubId) async =>
      DomainManagement(
        pathAddress: null,
        clubPublished: clubPublished,
        customDomainRequestAvailable: false,
        teamzoneSubdomainAvailable: false,
        domains: const [],
      );

  @override
  Future<void> transition({
    required String articleId,
    required String state,
    DateTime? publishAt,
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    transitionedTo = state;
  }

  @override
  Future<List<EditorialArticle>> listArticles(String clubId) async =>
      saved == null
      ? const []
      : [
          EditorialArticle(
            id: 'article',
            slug: saved!.slug,
            title: saved!.title,
            summary: saved!.summary,
            blocks: saved!.blocks,
            state: 'draft',
            publishToClub: saved!.publishToClub,
            teamIds: saved!.teamIds,
            revision: 1,
            mediaStatus: heroAssetId == null ? 'none' : 'pending',
            heroAssetId: heroAssetId,
            heroAlt: heroAssetId == null ? null : 'Laget firar',
          ),
        ];

  @override
  Future<EditorialSaveResult?> saveArticle(EditorialSaveInput input) async {
    saved = input;
    return const EditorialSaveResult(articleId: 'article', revision: 2);
  }

  @override
  Future<int> setArticleHero({
    required String articleId,
    required String? assetId,
    required String? alt,
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    heroCalls.add((assetId, expectedRevision));
    heroAssetId = assetId;
    return expectedRevision + 1;
  }
}

EditorialSaveInput _draft() => const EditorialSaveInput(
  clubId: 'club',
  slug: 'sasongen-startar',
  title: 'Säsongen startar',
  blocks: [EditorialBlock(type: 'paragraph', text: 'Välkommen tillbaka.')],
  publishToClub: true,
  teamIds: {},
  idempotencyKey: 'seed',
);

class _Identity implements IdentityServices {
  const _Identity(this.canPublish);
  final bool canPublish;
  @override
  SessionStatus get sessionStatus => SessionStatus.authenticated;
  @override
  Stream<SessionStatus> get sessionChanges => const Stream.empty();
  @override
  Future<TeamZoneProfile> getProfile() async => const TeamZoneProfile(
    id: 'profile',
    displayName: 'Redaktör',
    locale: 'sv',
  );
  @override
  Future<List<TeamZoneContext>> getContexts() async => [
    TeamZoneContext(
      id: 'context',
      clubId: 'club',
      clubName: 'Testklubben',
      teamId: 'team',
      teamName: 'F2012',
      rolePackage: 'club_functionary',
      capabilities: canPublish
          ? const {'team.read', 'publication.manage'}
          : const {'team.read'},
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
