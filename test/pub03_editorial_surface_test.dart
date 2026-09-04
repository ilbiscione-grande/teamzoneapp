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
  testWidgets('publisher creates a structured club news draft', (tester) async {
    final editorial = _Editorial();
    await tester.pumpWidget(_app(editorial, canPublish: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Nyhetsredaktion'));
    await tester.pumpAndSettle();
    expect(find.text('Inga artiklar ännu'), findsOneWidget);
    await tester.tap(find.text('Ny artikel'));
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
    await tester.drag(find.byType(ListView).last, const Offset(0, -1200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spara utkast'));
    await tester.pumpAndSettle();
    expect(editorial.saved?.title, 'Säsongen startar');
    expect(editorial.saved?.blocks.single.type, 'paragraph');
    expect(find.text('Säsongen startar'), findsOneWidget);
  });

  testWidgets('newsroom entry is hidden without publication capability', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_Editorial(), canPublish: false));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Nyhetsredaktion'), findsNothing);
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
  EditorialSaveInput? saved;

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
            mediaStatus: 'not_configured',
          ),
        ];

  @override
  Future<void> saveArticle(EditorialSaveInput input) async {
    saved = input;
  }
}

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
