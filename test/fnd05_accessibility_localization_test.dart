import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/core/identity/identity_services.dart';
import 'package:teamzone_app/src/core/supabase/supabase_bootstrap.dart';
import 'package:teamzone_app/src/shared/theme/app_theme.dart';

void main() {
  test('interactive theme targets remain at least 48 logical pixels', () {
    final theme = AppTheme.light();
    for (final style in [
      theme.filledButtonTheme.style!,
      theme.outlinedButtonTheme.style!,
      theme.textButtonTheme.style!,
      theme.iconButtonTheme.style!,
    ]) {
      final size = style.minimumSize!.resolve({})!;
      expect(size.width, greaterThanOrEqualTo(AppSizes.minimumTouchTarget));
      expect(size.height, greaterThanOrEqualTo(AppSizes.minimumTouchTarget));
    }
  });

  test('light and dark semantic color pairs meet WCAG AA contrast', () {
    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      final colors = theme.colorScheme;
      for (final pair in [
        (colors.primary, colors.onPrimary, 'primary'),
        (colors.surface, colors.onSurface, 'surface'),
        (colors.error, colors.onError, 'error'),
      ]) {
        expect(
          _contrast(pair.$1, pair.$2),
          greaterThanOrEqualTo(4.5),
          reason: '${theme.brightness} ${pair.$3}',
        );
      }
    }
  });

  testWidgets('reduced motion turns shared durations off', (tester) async {
    Duration? result;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              result = AppMotion.accessible(context, AppMotion.medium);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    expect(result, Duration.zero);
  });

  testWidgets('sign-in fields follow keyboard focus order and expose actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      TeamZoneApp(
        environment: const AppEnvironment(name: 'accessibility'),
        locale: const Locale('sv'),
        services: AppServices(
          identity: _Identity(status: SessionStatus.unauthenticated),
          isConfigured: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(EditableText);
    expect(fields, findsNWidgets(2));
    final email = tester.widget<EditableText>(fields.at(0));
    final password = tester.widget<EditableText>(fields.at(1));
    expect(email.textInputAction, TextInputAction.next);
    expect(password.textInputAction, TextInputAction.done);

    await tester.tap(fields.at(0));
    await tester.pump();
    expect(email.focusNode.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(password.focusNode.hasFocus, isTrue);
  });

  for (final window in const [
    (name: 'phone', size: Size(390, 844)),
    (name: 'tablet', size: Size(800, 1100)),
    (name: 'desktop', size: Size(1440, 900)),
  ]) {
    testWidgets('${window.name} supports 200 percent text without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = window.size;
      tester.view.devicePixelRatio = 1;
      tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
      );

      await tester.pumpWidget(
        TeamZoneApp(
          environment: const AppEnvironment(name: 'accessibility'),
          locale: const Locale('sv'),
          services: AppServices(
            identity: _Identity(status: SessionStatus.authenticated),
            isConfigured: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Tillgänglighetslaget'), findsWidgets);
      if (window.name == 'phone') {
        final navigation = tester.widget<NavigationBar>(
          find.byType(NavigationBar),
        );
        expect(
          navigation.labelBehavior,
          NavigationDestinationLabelBehavior.onlyShowSelected,
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('icon buttons expose text alternatives', (tester) async {
    await tester.pumpWidget(
      TeamZoneApp(
        environment: const AppEnvironment(name: 'accessibility'),
        locale: const Locale('sv'),
        services: AppServices(
          identity: _Identity(status: SessionStatus.authenticated),
          isConfigured: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final element in find.byType(IconButton).evaluate()) {
      final button = element.widget as IconButton;
      expect(button.tooltip, isNotEmpty);
    }
  });

  test('priority surfaces keep user copy behind the locale boundary', () {
    final paths = [
      'lib/src/features/auth/auth_surfaces.dart',
      'lib/src/features/overview/overview_surface.dart',
      'lib/src/features/roster/roster_surface.dart',
      'lib/src/features/calendar/calendar_surface.dart',
      'lib/src/features/messaging/inbox_surface.dart',
      'lib/src/app/product_shell.dart',
    ];
    final strings = File(
      'lib/src/core/localization/app_strings.dart',
    ).readAsStringSync();

    for (final path in paths) {
      final source = File(path).readAsStringSync();
      for (final match in RegExp(
        r"\.feature\('([^']+)'\)",
      ).allMatches(source)) {
        expect(
          strings,
          contains("'${match.group(1)}':"),
          reason: '$path lacks English copy for ${match.group(1)}',
        );
      }
      for (final match in RegExp(r"Text\('([^'$]+)'\)").allMatches(source)) {
        expect(
          match.group(1),
          'TeamZone',
          reason: '$path contains hard-coded user copy: ${match.group(1)}',
        );
      }
    }
  });
}

double _contrast(Color first, Color second) {
  final lighter = first.computeLuminance() > second.computeLuminance()
      ? first
      : second;
  final darker = identical(lighter, first) ? second : first;
  return (lighter.computeLuminance() + 0.05) /
      (darker.computeLuminance() + 0.05);
}

class _Identity implements IdentityServices {
  _Identity({required this.status});

  final SessionStatus status;

  @override
  SessionStatus get sessionStatus => status;

  @override
  Stream<SessionStatus> get sessionChanges => const Stream.empty();

  @override
  Future<List<TeamZoneContext>> getContexts() async => const [
    TeamZoneContext(
      id: 'accessibility-context',
      clubId: 'accessibility-club',
      clubName: 'Tillgänglighetsklubben',
      teamId: 'accessibility-team',
      teamName: 'Tillgänglighetslaget',
      rolePackage: 'leader',
      capabilities: {'team.read'},
    ),
  ];

  @override
  Future<TeamZoneProfile> getProfile() async => const TeamZoneProfile(
    id: 'accessibility-profile',
    displayName: 'Tillgänglighetstestare',
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
