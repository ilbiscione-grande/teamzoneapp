import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/core/identity/identity_services.dart';
import 'package:teamzone_app/src/core/supabase/supabase_bootstrap.dart';
import 'package:teamzone_app/src/shared/async/async_data_controller.dart';
import 'package:teamzone_app/src/shared/forms/app_form_controller.dart';

void main() {
  group('FND-02 shared state widget contract', () {
    testWidgets('renders loading, empty, ready, stale and safe failure', (
      tester,
    ) async {
      final firstLoad = Completer<List<String>>();
      var failRefresh = false;
      final controller = AsyncDataController<List<String>>(
        scopeKey: 'verification',
        loader: () async {
          if (!firstLoad.isCompleted) return firstLoad.future;
          if (failRefresh) throw StateError('private backend detail');
          return const ['Ready item'];
        },
        isEmpty: (items) => items.isEmpty,
      );

      await tester.pumpWidget(_AsyncStateHarness(controller: controller));
      unawaited(controller.load());
      await tester.pump();
      expect(find.text('loading'), findsOneWidget);

      firstLoad.complete(const []);
      await tester.pumpAndSettle();
      expect(find.text('empty'), findsOneWidget);

      controller.replaceScope(
        scopeKey: 'ready',
        loader: () async {
          if (failRefresh) throw StateError('private backend detail');
          return const ['Ready item'];
        },
      );
      await tester.pumpAndSettle();
      expect(find.text('Ready item'), findsOneWidget);

      failRefresh = true;
      await controller.refresh();
      await tester.pumpAndSettle();
      expect(find.text('stale: Ready item'), findsOneWidget);
      expect(find.textContaining('private backend detail'), findsNothing);

      controller.replaceScope(
        scopeKey: 'failed',
        loader: () async => throw StateError('private backend detail'),
      );
      await tester.pumpAndSettle();
      expect(find.text('failed'), findsOneWidget);
      expect(find.textContaining('private backend detail'), findsNothing);

      controller.dispose();
    });
  });

  group('FND-03 responsive product shell', () {
    for (final window in const [
      (name: 'phone', size: Size(390, 844), usesRail: false),
      (name: 'tablet', size: Size(800, 1100), usesRail: true),
      (name: 'desktop', size: Size(1440, 900), usesRail: true),
    ]) {
      testWidgets('${window.name} uses the canonical navigation layout', (
        tester,
      ) async {
        tester.view.physicalSize = window.size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_verifiedApp());
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('permanent-navigation-sidebar')),
          window.usesRail ? findsOneWidget : findsNothing,
        );
        expect(
          find.byType(NavigationBar),
          window.usesRail ? findsNothing : findsOneWidget,
        );
        expect(find.textContaining('Verifieringslaget'), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('cold link and app rebuild retain a canonical destination', (
      tester,
    ) async {
      tester.binding.platformDispatcher.defaultRouteNameTestValue = '/team';
      addTearDown(
        tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
      );

      await tester.pumpWidget(_verifiedApp());
      await tester.pumpAndSettle();
      expect(find.text('Översikt'), findsOneWidget);
      expect(find.textContaining('Verifieringslaget'), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(_verifiedApp());
      await tester.pumpAndSettle();
      expect(find.text('Översikt'), findsOneWidget);
      expect(find.textContaining('Verifieringslaget'), findsWidgets);
    });

    testWidgets('system back returns from assistant to the previous surface', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_verifiedApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('assistant-coach-mobile-fab')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('assistant-coach-holding-surface')),
        findsOneWidget,
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('assistant-coach-holding-surface')),
        findsNothing,
      );
      expect(find.text('Hem'), findsWidgets);
    });

    testWidgets('system back steps through visited pages before exiting', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_verifiedApp());
      await tester.pumpAndSettle();
      expect(find.text('Hem'), findsWidgets);

      // .go()-based navigation (bottom nav, drawer) replaces the current
      // location rather than pushing a history entry, so without the
      // shell's own history tracking there would be nothing to pop here.
      await tester.tap(find.text('Kalender').last);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Filtrera kalendern'), findsOneWidget);

      final popped = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(popped, isTrue);
      expect(find.byTooltip('Filtrera kalendern'), findsNothing);
      expect(find.text('Hem'), findsWidgets);
    });

    testWidgets(
      'system back on the first page opened asks before exiting',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final exitCalls = <MethodCall>[];
        TestDefaultBinaryMessengerBinding
            .instance
            .defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              exitCalls.add(call);
              return null;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding.instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null),
        );

        await tester.pumpWidget(_verifiedApp());
        await tester.pumpAndSettle();

        // Startup already sends unrelated SystemChrome.* calls over this
        // same channel, so check for the specific exit method rather than
        // asserting the call log stays empty.
        bool exitRequested() =>
            exitCalls.any((call) => call.method == 'SystemNavigator.pop');

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('Stäng TeamZone?'), findsOneWidget);
        expect(exitRequested(), isFalse);

        await tester.tap(find.text('Avbryt'));
        await tester.pumpAndSettle();
        expect(find.text('Hem'), findsWidgets);
        expect(exitRequested(), isFalse);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Stäng'));
        await tester.pumpAndSettle();
        expect(
          exitCalls.map((call) => call.method),
          contains('SystemNavigator.pop'),
        );
      },
    );

    testWidgets('phone drawer closes after tapping a nav item', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_verifiedApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.person));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('app-navigation-panel-list')),
        findsOneWidget,
      );

      await tester.tap(find.text('Kalender').last);
      await tester.pumpAndSettle();

      final scaffoldState = tester.state<ScaffoldState>(
        find.byType(Scaffold).first,
      );
      expect(scaffoldState.isDrawerOpen, isFalse);
    });
  });

  testWidgets('system back warns before discarding unsaved changes', (
    tester,
  ) async {
    final controller = AppFormController()..markDirty();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => AppUnsavedChangesScope(
                    controller: controller,
                    title: 'Discard changes?',
                    message: 'Unsaved data will be lost.',
                    discardLabel: 'Discard',
                    cancelLabel: 'Keep editing',
                    child: const Scaffold(body: Text('Editing event')),
                  ),
                ),
              ),
              child: const Text('Open editor'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Editing event'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Open editor'), findsOneWidget);
  });
}

Widget _verifiedApp() => TeamZoneApp(
  environment: const AppEnvironment(name: 'verification'),
  locale: const Locale('sv'),
  services: AppServices(identity: _VerificationIdentity(), isConfigured: true),
);

class _VerificationIdentity implements IdentityServices {
  @override
  SessionStatus get sessionStatus => SessionStatus.authenticated;

  @override
  Stream<SessionStatus> get sessionChanges => const Stream.empty();

  @override
  Future<List<TeamZoneContext>> getContexts() async => const [
    TeamZoneContext(
      id: 'verification-context',
      clubId: 'verification-club',
      clubName: 'Verifieringsklubben',
      teamId: 'verification-team',
      teamName: 'Verifieringslaget',
      rolePackage: 'leader',
      capabilities: {'team.read'},
    ),
  ];

  @override
  Future<TeamZoneProfile> getProfile() async => const TeamZoneProfile(
    id: 'verification-profile',
    displayName: 'Verifierare',
    locale: 'sv',
  );

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async {}
}

class _AsyncStateHarness extends StatelessWidget {
  const _AsyncStateHarness({required this.controller});

  final AsyncDataController<List<String>> controller;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final state = controller.state;
        return switch (state.phase) {
          AsyncDataPhase.loading => const Text('loading'),
          AsyncDataPhase.empty => const Text('empty'),
          AsyncDataPhase.failed => const Text('failed'),
          AsyncDataPhase.ready => Text(
            '${state.isStale ? 'stale: ' : ''}${state.data!.join(', ')}',
          ),
        };
      },
    ),
  );
}
