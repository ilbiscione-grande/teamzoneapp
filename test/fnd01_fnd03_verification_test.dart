import 'dart:async';

import 'package:flutter/material.dart';
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
          find.byType(NavigationRail),
          window.usesRail ? findsOneWidget : findsNothing,
        );
        expect(
          find.byType(NavigationBar),
          window.usesRail ? findsNothing : findsOneWidget,
        );
        expect(find.text('Verifieringslaget'), findsOneWidget);
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
      expect(find.text('Verifieringslaget'), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(_verifiedApp());
      await tester.pumpAndSettle();
      expect(find.text('Översikt'), findsOneWidget);
      expect(find.text('Verifieringslaget'), findsWidgets);
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
