import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/core/identity/identity_services.dart';
import 'package:teamzone_app/src/core/supabase/supabase_bootstrap.dart';
import 'package:teamzone_app/src/features/publication/editorial_services.dart';

void main() {
  testWidgets('club can unpublish and republish with renewed confirmation', (
    tester,
  ) async {
    final editorial = _Editorial()..clubMode = 'published';
    await _open(tester, editorial);
    Future<void> choose(String label) async {
      await tester.tap(find.text('Ändra'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    await choose('Privat');
    await tester.tap(find.widgetWithText(FilledButton, 'Spara'));
    await tester.pumpAndSettle();
    expect(editorial.clubMode, 'private');
    expect(editorial.fields, isEmpty);
    expect(
      find.textContaining('Dold – klubbsidan är inte publicerad'),
      findsOneWidget,
    );
    await choose('Publik sida och klubbkatalog');
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Spara'))
          .onPressed,
      isNull,
    );
    final confirmation = find.widgetWithText(
      CheckboxListTile,
      'Jag bekräftar att namn och valda uppgifter får publiceras på webben.',
    );
    await tester.ensureVisible(confirmation);
    await tester.tap(confirmation);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Spara'));
    await tester.pumpAndSettle();
    expect(editorial.clubMode, 'published');
    expect(editorial.fields, ['name']);
    expect(editorial.revision, 3);
    expect(
      find.textContaining('Dold – klubbsidan är inte publicerad'),
      findsNothing,
    );
  });

  testWidgets('a never-published team gets a suggested web address', (
    tester,
  ) async {
    final editorial = _Editorial()
      ..clubMode = 'published'
      ..teamMode = 'private'
      ..teamSlug = null
      ..teamName = 'Örby F2014';
    await _open(tester, editorial);
    await tester.tap(find.text('Välj synlighet'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'orby-f2014'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Publik lagsida').last);
    await tester.pumpAndSettle();
    final confirmation = find.widgetWithText(
      CheckboxListTile,
      'Jag bekräftar att namn och valda uppgifter får publiceras på webben.',
    );
    await tester.ensureVisible(confirmation);
    await tester.tap(confirmation);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Spara'));
    await tester.pumpAndSettle();
    expect(editorial.savedSlug, 'orby-f2014');
    expect(editorial.savedMode, 'published');
  });

  testWidgets('private club explains why a published team is hidden', (
    tester,
  ) async {
    await _open(tester, _Editorial());
    expect(
      find.textContaining('Dold – klubbsidan är inte publicerad'),
      findsOneWidget,
    );
    await tester.tap(find.text('Ändra'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Lagens publiceringsval sparas.'),
      findsOneWidget,
    );
  });

  testWidgets('approval is recovered after an uncertain command response', (
    tester,
  ) async {
    final editorial = _Editorial();
    await _open(tester, editorial);
    expect(find.text('Ansökningar som väntar på beslut: 1'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Godkänn'),
      200,
      scrollable: find.descendant(
        of: find.byType(ListView).last,
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.text('Godkänn'));
    await tester.pumpAndSettle();
    expect(editorial.status, 'approved');
    expect(
      find.text(
        'Ansökan är godkänd. Välj lagets synlighet för att publicera sidan.',
      ),
      findsOneWidget,
    );
    expect(find.text('Ansökningar som väntar på beslut: 1'), findsNothing);
    expect(find.textContaining('Ändringen kunde inte sparas'), findsNothing);
  });

  testWidgets('leader sees pending request after uncertain response', (
    tester,
  ) async {
    final editorial = _Editorial(manager: false, status: null);
    await _open(tester, editorial);
    await tester.tap(find.text('Ansök om lagsida'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skicka ansökan'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ansökan: Väntar på beslut'), findsOneWidget);
    expect(
      find.text('Ansökan är skickad till klubben och väntar på beslut.'),
      findsOneWidget,
    );
    expect(find.text('Ansök om lagsida'), findsNothing);
    expect(find.text('Godkänn'), findsNothing);
  });

  testWidgets(
    'approved leader waits for club publication without duplicate request',
    (tester) async {
      await _open(tester, _Editorial(manager: false, status: 'approved'));
      expect(
        find.textContaining(
          'Sidan väntar på att klubben väljer publik synlighet.',
        ),
        findsOneWidget,
      );
      expect(find.text('Ansök om lagsida'), findsNothing);
    },
  );
}

Future<void> _open(WidgetTester tester, _Editorial editorial) async {
  await tester.pumpWidget(
    TeamZoneApp(
      environment: const AppEnvironment(name: 'pub02-test'),
      locale: const Locale('sv'),
      services: AppServices(
        identity: _Identity(editorial.manager),
        editorial: editorial,
        isConfigured: true,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.byTooltip('Publika sidor'),
    250,
    scrollable: find.descendant(
      of: find.byKey(const Key('app-navigation-panel-list')),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.tap(find.byTooltip('Publika sidor'));
  await tester.pumpAndSettle();
}

class _Editorial extends UnconfiguredEditorialServices {
  _Editorial({this.manager = true, this.status = 'pending'});
  final bool manager;
  String? status;
  String clubMode = 'private';
  String? teamMode;
  String? teamSlug = 'testlag';
  String teamName = 'Testlag';
  String? savedSlug;
  String? savedMode;
  int revision = 1;
  List<String> fields = [];
  @override
  Future<void> configurePublication({
    required String clubId,
    required String aggregateType,
    required String aggregateId,
    required String mode,
    required String slug,
    required List<String> fields,
    String? locality,
    String? description,
    String? ageClass,
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    savedSlug = slug;
    savedMode = mode;
    if (aggregateType == 'team') return;
    expect(expectedRevision, revision);
    clubMode = mode;
    this.fields = fields;
    revision++;
    throw StateError('Response lost after commit');
  }

  @override
  Future<Map<String, dynamic>> getPublicationSelfService(String clubId) async =>
      {
        'club': {
          'id': 'club',
          'name': 'Testklubb',
          'mode': clubMode,
          'slug': 'testklubb',
          'revision': revision,
          'fields': fields,
        },
        'can_manage_club': manager,
        'teams': [
          {
            'id': 'team',
            'name': teamName,
            'mode': teamMode ?? (manager ? 'published' : 'private'),
            'slug': teamSlug,
            'revision': 1,
            'can_request': true,
            'request_status': status,
          },
        ],
        'requests': manager
            ? [
                {
                  'id': 'request',
                  'team_id': 'team',
                  'team_name': 'Testlag',
                  'status': status,
                  'message': 'Vi vill ha en sida.',
                },
              ]
            : [],
      };
  @override
  Future<void> decideTeamPublication({
    required String requestId,
    required bool approve,
  }) async {
    status = approve ? 'approved' : 'rejected';
    throw StateError('Response lost after commit');
  }

  @override
  Future<void> requestTeamPublication({
    required String clubId,
    required String teamId,
    required String message,
  }) async {
    status = 'pending';
    throw StateError('Response lost after commit');
  }
}

class _Identity implements IdentityServices {
  const _Identity(this.manager);
  final bool manager;
  @override
  SessionStatus get sessionStatus => SessionStatus.authenticated;
  @override
  Stream<SessionStatus> get sessionChanges => const Stream.empty();
  @override
  Future<TeamZoneProfile> getProfile() async => const TeamZoneProfile(
    id: 'profile',
    displayName: 'Testledare',
    locale: 'sv',
  );
  @override
  Future<List<TeamZoneContext>> getContexts() async => [
    TeamZoneContext(
      id: 'context',
      clubId: 'club',
      clubName: 'Testklubb',
      teamId: 'team',
      teamName: 'Testlag',
      rolePackage: manager ? 'club_functionary' : 'leader',
      capabilities: {
        'team.read',
        'team.roster.manage',
        if (manager) 'publication.manage',
      },
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
