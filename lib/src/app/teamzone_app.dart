import 'dart:async';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/core/identity/identity_services.dart';
import 'package:teamzone_app/src/core/identity/auth_entry_services.dart';
import 'package:teamzone_app/src/core/identity/session_persistence.dart';
import 'package:teamzone_app/src/core/localization/app_strings.dart';
import 'package:teamzone_app/src/core/localization/board_strings.dart';
import 'package:teamzone_app/src/core/localization/economy_strings.dart';
import 'package:teamzone_app/src/core/supabase/measured_rpc.dart';
import 'package:teamzone_app/src/core/supabase/supabase_bootstrap.dart';
import 'package:teamzone_app/src/app/product_route_contract.dart';
import 'package:teamzone_app/src/features/calendar/calendar_models.dart';
import 'package:teamzone_app/src/features/calendar/calendar_services.dart';
import 'package:teamzone_app/src/features/assistant_coach/assistant_identity.dart';
import 'package:teamzone_app/src/features/assistant_coach/assistant_queue.dart';
import 'package:teamzone_app/src/features/assistant_coach/assistant_presentation.dart';
import 'package:teamzone_app/src/features/assistant_coach/assistant_policy.dart';
import 'package:teamzone_app/src/features/assistant_coach/assistant_specialist_registry.dart';
import 'package:teamzone_app/src/features/billing/billing_models.dart';
import 'package:teamzone_app/src/features/billing/billing_services.dart';
import 'package:teamzone_app/src/features/board/board_models.dart';
import 'package:teamzone_app/src/features/board/board_services.dart';
import 'package:teamzone_app/src/features/development/development_models.dart';
import 'package:teamzone_app/src/features/development/development_services.dart';
import 'package:teamzone_app/src/features/economy/economy_models.dart';
import 'package:teamzone_app/src/features/economy/economy_services.dart';
import 'package:teamzone_app/src/features/overview/overview_models.dart';
import 'package:teamzone_app/src/features/overview/overview_services.dart';
import 'package:teamzone_app/src/features/publication/editorial_models.dart';
import 'package:teamzone_app/src/features/publication/editorial_services.dart';
import 'package:teamzone_app/src/features/messaging/messaging_models.dart';
import 'package:teamzone_app/src/features/messaging/messaging_services.dart';
import 'package:teamzone_app/src/features/match/match_models.dart';
import 'package:teamzone_app/src/features/match/match_services.dart';
import 'package:teamzone_app/src/features/membership/membership_models.dart';
import 'package:teamzone_app/src/features/membership/membership_services.dart';
import 'package:teamzone_app/src/features/legal/legal_models.dart';
import 'package:teamzone_app/src/features/legal/legal_services.dart';
import 'package:teamzone_app/src/features/roster/roster_models.dart';
import 'package:teamzone_app/src/features/roster/roster_services.dart';
import 'package:teamzone_app/src/shared/layout/app_breakpoints.dart';
import 'package:teamzone_app/src/shared/async/async_data_controller.dart';
import 'package:teamzone_app/src/shared/forms/app_form_controller.dart';
import 'package:teamzone_app/src/shared/lists/app_list_controller.dart';
import 'package:teamzone_app/src/shared/theme/app_theme.dart';
import 'package:teamzone_app/src/shared/widgets/app_states.dart';
import 'package:url_launcher/url_launcher.dart';

part 'product_shell.dart';
part 'product_routes.dart';
part '../features/assistant_coach/assistant_coach_entry.dart';
part '../features/auth/auth_surfaces.dart';
part '../features/auth/invitation_flow.dart';
part '../features/legal/legal_acceptance_surface.dart';
part '../features/billing/billing_surface.dart';
part '../features/board/board_surface.dart';
part '../features/calendar/calendar_surface.dart';
part '../features/development/development_surface.dart';
part '../features/economy/economy_surface.dart';
part '../features/match/match_space_dialog.dart';
part '../features/messaging/inbox_surface.dart';
part '../features/overview/overview_surface.dart';
part '../features/publication/editorial_surface.dart';
part '../features/publication/publication_management_surface.dart';
part '../features/publication/domain_management_surface.dart';
part '../features/roster/roster_surface.dart';

class TeamZoneApp extends StatefulWidget {
  const TeamZoneApp({
    required this.environment,
    required this.services,
    this.locale,
    super.key,
  });

  final AppEnvironment environment;
  final AppServices services;
  final Locale? locale;

  @override
  State<TeamZoneApp> createState() => _TeamZoneAppState();
}

class _TeamZoneAppState extends State<TeamZoneApp> {
  late SessionStatus _sessionStatus;
  StreamSubscription<SessionStatus>? _sessionSubscription;
  StreamSubscription<AuthEntryEvent>? _authEntrySubscription;
  StreamSubscription<Uri>? _invitationLinkSubscription;
  bool _recoveringPassword = false;
  bool _signingOut = false;
  bool _sessionEnded = false;
  String? _pendingInvitationToken;
  bool _showInvitationSignIn = false;

  @override
  void initState() {
    super.initState();
    _sessionStatus = widget.services.identity.sessionStatus;
    _pendingInvitationToken = invitationTokenFromUri(
      Uri.tryParse(WidgetsBinding.instance.platformDispatcher.defaultRouteName),
    );
    if (kIsWeb) {
      _pendingInvitationToken ??= invitationTokenFromUri(Uri.base);
    }
    _sessionSubscription = widget.services.identity.sessionChanges.listen((
      status,
    ) {
      if (!mounted) return;
      setState(() {
        if (_sessionStatus == SessionStatus.authenticated &&
            status == SessionStatus.unauthenticated &&
            !_signingOut) {
          _sessionEnded = true;
        }
        _sessionStatus = status;
        if (status == SessionStatus.authenticated) _sessionEnded = false;
        if (status == SessionStatus.authenticated) {
          _showInvitationSignIn = false;
        }
      });
    });
    _authEntrySubscription = widget.services.authEntry.entryEvents.listen((
      event,
    ) {
      if (event == AuthEntryEvent.passwordRecovery && mounted) {
        setState(() => _recoveringPassword = true);
      }
    });
    _invitationLinkSubscription = AppLinks().uriLinkStream.listen((uri) {
      final token = invitationTokenFromUri(uri);
      if (token != null && mounted) {
        setState(() {
          _pendingInvitationToken = token;
          _showInvitationSignIn = false;
        });
      }
    }, onError: (_) {});
  }

  @override
  void dispose() {
    unawaited(_sessionSubscription?.cancel());
    unawaited(_authEntrySubscription?.cancel());
    unawaited(_invitationLinkSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.light();
    final darkTheme = AppTheme.dark();
    final invitationToken = _pendingInvitationToken;
    final root = _recoveringPassword
        ? _ResetPasswordScreen(
            authEntry: widget.services.authEntry,
            onComplete: () => setState(() => _recoveringPassword = false),
          )
        : invitationToken != null && !_showInvitationSignIn
        ? _InvitationFlow(
            token: invitationToken,
            authenticated: _sessionStatus == SessionStatus.authenticated,
            roster: widget.services.roster,
            onAuthenticate: () => setState(() => _showInvitationSignIn = true),
            onComplete: () => setState(() => _pendingInvitationToken = null),
            onCancel: () => setState(() => _pendingInvitationToken = null),
          )
        : _sessionStatus == SessionStatus.authenticated
        ? _LegalBootstrap(
            legal: widget.services.legal,
            onSignOut: _signOut,
            child: _ContextBootstrap(
              services: widget.services,
              matchSpaceV2: widget.environment.matchSpaceV2,
              onSignOut: _signOut,
            ),
          )
        : _SignInScreen(
            identity: widget.services.identity,
            authEntry: widget.services.authEntry,
            environment: widget.environment,
            isConfigured: widget.services.isConfigured,
            sessionEnded: _sessionEnded,
          );

    final appKey = ValueKey(
      '${_sessionStatus.name}:$_recoveringPassword:'
      '${invitationToken != null}:$_showInvitationSignIn',
    );
    if (kIsWeb) {
      return MaterialApp.router(
        key: appKey,
        routerDelegate: _StaticRootRouterDelegate(root),
        debugShowCheckedModeBanner: false,
        title: 'TeamZone',
        theme: theme,
        darkTheme: darkTheme,
        themeMode: ThemeMode.system,
        supportedLocales: const [Locale('sv'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        locale: widget.locale,
      );
    }
    return MaterialApp(
      key: appKey,
      debugShowCheckedModeBanner: false,
      title: 'TeamZone',
      theme: theme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.system,
      supportedLocales: const [Locale('sv'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      locale: widget.locale,
      onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => root),
    );
  }

  Future<void> _signOut() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    try {
      await widget.services.identity.signOut();
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }
}

class _StaticRootRouterDelegate extends RouterDelegate<Object>
    with ChangeNotifier {
  _StaticRootRouterDelegate(this.root);

  final Widget root;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) => Navigator(
    key: _navigatorKey,
    pages: [MaterialPage<void>(key: const ValueKey('root'), child: root)],
    onDidRemovePage: (_) {},
  );

  @override
  Future<bool> popRoute() async => false;

  @override
  Future<void> setNewRoutePath(Object configuration) async {}
}

class _NotFoundSurface extends StatelessWidget {
  const _NotFoundSurface();

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Center(
      child: _StateCard(
        icon: Icons.link_off,
        title: strings.pageNotFound,
        message: strings.linkNotAvailable,
      ),
    );
  }
}

class _StateCard extends AppStateCard {
  const _StateCard({
    required super.icon,
    required super.title,
    required super.message,
    super.action,
  });
}
