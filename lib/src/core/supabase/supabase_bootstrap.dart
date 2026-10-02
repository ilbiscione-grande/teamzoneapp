import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/core/identity/identity_services.dart';
import 'package:teamzone_app/src/core/identity/auth_entry_services.dart';
import 'package:teamzone_app/src/core/identity/session_persistence.dart';
import 'package:teamzone_app/src/core/preferences/calendar_preferences.dart';
import 'package:teamzone_app/src/core/preferences/theme_persistence.dart';
import 'package:teamzone_app/src/features/calendar/calendar_services.dart';
import 'package:teamzone_app/src/features/assistant_coach/assistant_identity.dart';
import 'package:teamzone_app/src/features/assistant_coach/assistant_presentation.dart';
import 'package:teamzone_app/src/features/billing/billing_services.dart';
import 'package:teamzone_app/src/features/board/board_services.dart';
import 'package:teamzone_app/src/features/development/development_services.dart';
import 'package:teamzone_app/src/features/economy/economy_services.dart';
import 'package:teamzone_app/src/features/overview/overview_services.dart';
import 'package:teamzone_app/src/features/publication/editorial_services.dart';
import 'package:teamzone_app/src/features/messaging/messaging_services.dart';
import 'package:teamzone_app/src/features/match/match_services.dart';
import 'package:teamzone_app/src/features/membership/membership_services.dart';
import 'package:teamzone_app/src/features/legal/legal_services.dart';
import 'package:teamzone_app/src/features/account/profile_services.dart';
import 'package:teamzone_app/src/features/roster/roster_services.dart';

class AppServices {
  const AppServices({
    required this.identity,
    required this.isConfigured,
    this.authEntry = const UnconfiguredAuthEntryServices(),
    this.contextPersistence = const StatelessContextPersistence(),
    this.themePersistence = const StatelessThemePersistence(),
    this.calendarPreferences = const StatelessCalendarPreferences(),
    this.roster = const UnconfiguredRosterServices(),
    this.membership = const UnconfiguredMembershipServices(),
    this.legal = const UnconfiguredLegalServices(),
    this.profile = const UnconfiguredProfileServices(),
    this.calendar = const UnconfiguredCalendarServices(),
    this.overview = const UnconfiguredOverviewServices(),
    this.messaging = const UnconfiguredMessagingServices(),
    this.match = const UnconfiguredMatchServices(),
    this.development = const UnconfiguredDevelopmentServices(),
    this.billing = const UnconfiguredBillingServices(),
    this.economy = const UnconfiguredEconomyServices(),
    this.board = const UnconfiguredBoardServices(),
    this.editorial = const UnconfiguredEditorialServices(),
    this.assistantIdentity = const UnconfiguredAssistantIdentityServices(),
    this.assistantPresentation =
        const UnconfiguredAssistantPresentationServices(),
  });

  final IdentityServices identity;
  final AuthEntryServices authEntry;
  final ContextPersistence contextPersistence;
  final ThemePersistence themePersistence;
  final CalendarPreferences calendarPreferences;
  final RosterServices roster;
  final MembershipServices membership;
  final LegalServices legal;
  final ProfileServices profile;
  final CalendarServices calendar;
  final OverviewServices overview;
  final MessagingServices messaging;
  final MatchServices match;
  final DevelopmentServices development;
  final BillingServices billing;
  final EconomyServices economy;
  final BoardServices board;
  final EditorialServices editorial;
  final AssistantIdentityServices assistantIdentity;
  final AssistantPresentationServices assistantPresentation;
  final bool isConfigured;
}

class SupabaseBootstrap {
  const SupabaseBootstrap._();

  static Future<AppServices> initialize(AppEnvironment environment) async {
    if (!environment.hasSupabaseConfiguration) {
      return const AppServices(
        identity: UnconfiguredIdentityServices(),
        // The color theme and calendar default view are pure device-local
        // preferences with no dependency on a working backend connection,
        // so they stay real even in the unconfigured "Backend är inte
        // ansluten" state.
        themePersistence: SharedPreferencesThemePersistence(),
        calendarPreferences: SharedPreferencesCalendarPreferences(),
        isConfigured: false,
      );
    }

    final sessionStorage = ToggleableSessionStorage(
      SharedPreferencesLocalStorage(
        persistSessionKey:
            'sb-${Uri.parse(environment.supabaseUrl).host.split('.').first}-auth-token',
      ),
    );
    await Supabase.initialize(
      url: environment.supabaseUrl,
      publishableKey: environment.supabasePublishableKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ).copyWith(localStorage: sessionStorage),
    );
    final identity = SupabaseIdentityServices(
      Supabase.instance.client,
      sessionStorage: sessionStorage,
    );
    return AppServices(
      identity: identity,
      authEntry: identity,
      contextPersistence: const SharedPreferencesContextPersistence(),
      themePersistence: const SharedPreferencesThemePersistence(),
      calendarPreferences: const SharedPreferencesCalendarPreferences(),
      roster: SupabaseRosterServices(Supabase.instance.client),
      membership: SupabaseMembershipServices(Supabase.instance.client),
      legal: SupabaseLegalServices(Supabase.instance.client),
      profile: SupabaseProfileServices(Supabase.instance.client),
      calendar: SupabaseCalendarServices(Supabase.instance.client),
      overview: SupabaseOverviewServices(Supabase.instance.client),
      messaging: SupabaseMessagingServices(Supabase.instance.client),
      match: SupabaseMatchServices(Supabase.instance.client),
      development: SupabaseDevelopmentServices(Supabase.instance.client),
      billing: SupabaseBillingServices(Supabase.instance.client),
      economy: SupabaseEconomyServices(Supabase.instance.client),
      board: SupabaseBoardServices(Supabase.instance.client),
      editorial: SupabaseEditorialServices(Supabase.instance.client),
      assistantIdentity: SupabaseAssistantIdentityServices(
        Supabase.instance.client,
      ),
      assistantPresentation: SupabaseAssistantPresentationServices(
        Supabase.instance.client,
      ),
      isConfigured: true,
    );
  }
}

class ToggleableSessionStorage extends LocalStorage {
  ToggleableSessionStorage(this._delegate);

  final LocalStorage _delegate;
  bool _enabled = true;

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    if (!value) await _delegate.removePersistedSession();
  }

  @override
  Future<void> initialize() => _delegate.initialize();

  @override
  Future<bool> hasAccessToken() => _delegate.hasAccessToken();

  @override
  Future<String?> accessToken() => _delegate.accessToken();

  @override
  Future<void> removePersistedSession() => _delegate.removePersistedSession();

  @override
  Future<void> persistSession(String persistSessionString) async {
    if (_enabled) await _delegate.persistSession(persistSessionString);
  }
}

class SupabaseIdentityServices
    implements IdentityServices, AuthEntryServices, SessionPersistenceControl {
  SupabaseIdentityServices(this._client, {this.sessionStorage});

  final SupabaseClient _client;
  final ToggleableSessionStorage? sessionStorage;

  @override
  Future<void> setSessionPersistence({required bool persist}) async {
    await sessionStorage?.setEnabled(persist);
  }

  static const _mobileAuthRedirect = 'teamzone://app/auth/callback';
  static const _webAuthRedirect = 'https://app.teamzoneapp.se/auth/callback';
  String get _authRedirect => kIsWeb ? _webAuthRedirect : _mobileAuthRedirect;

  @override
  Stream<AuthEntryEvent> get entryEvents => _client.auth.onAuthStateChange
      .where((state) => state.event == AuthChangeEvent.passwordRecovery)
      .map((_) => AuthEntryEvent.passwordRecovery);

  @override
  SessionStatus get sessionStatus =>
      _client.auth.currentSession == null ||
          _client.auth.currentSession!.isExpired
      ? SessionStatus.unauthenticated
      : SessionStatus.authenticated;

  @override
  Stream<SessionStatus> get sessionChanges => _client.auth.onAuthStateChange
      .map(
        (event) => event.session == null || event.session!.isExpired
            ? SessionStatus.unauthenticated
            : SessionStatus.authenticated,
      )
      .transform(
        StreamTransformer.fromHandlers(
          handleError: (_, _, sink) => sink.add(SessionStatus.unauthenticated),
        ),
      );

  @override
  Future<void> signIn({required String email, required String password}) async {
    final response = await _client.functions.invoke(
      'auth-password-sign-in',
      body: {'email': email, 'password': password},
    );
    final data = response.data;
    if (response.status != 200 || data is! Map) {
      throw const AuthException('Sign-in failed.');
    }
    final refreshToken = data['refresh_token'];
    if (refreshToken is! String) {
      throw const AuthException('Sign-in failed.');
    }
    final authResponse = await _client.auth.setSession(refreshToken);
    if (authResponse.session == null) {
      throw const AuthException('Sign-in failed.');
    }
  }

  @override
  Future<void> signOut() => _client.auth.signOut(scope: SignOutScope.local);

  @override
  Future<PasswordSignUpResult> signUpWithPassword({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: _authRedirect,
    );
    final verified = response.user?.emailConfirmedAt != null;
    if (!verified && response.session != null) await _client.auth.signOut();
    return PasswordSignUpResult(verificationRequired: !verified);
  }

  @override
  Future<void> requestEmailChallenge({
    required String email,
    required EmailChallengePurpose purpose,
  }) => _client.auth.signInWithOtp(
    email: email,
    emailRedirectTo: _authRedirect,
    shouldCreateUser: purpose == EmailChallengePurpose.signUp,
  );

  @override
  Future<void> verifyEmailChallenge({
    required String email,
    required String code,
  }) async {
    final response = await _client.auth.verifyOTP(
      email: email,
      token: code,
      type: OtpType.email,
    );
    if (response.session == null || response.user?.emailConfirmedAt == null) {
      await _client.auth.signOut();
      throw const AuthException('Email verification failed.');
    }
  }

  @override
  Future<void> requestPasswordReset({required String email}) =>
      _client.auth.resetPasswordForEmail(email, redirectTo: _authRedirect);

  @override
  Future<void> updatePassword({required String password}) async {
    await _client.auth.updateUser(UserAttributes(password: password));
  }

  @override
  Future<TeamZoneProfile> getProfile() async {
    final value = await _client.schema('api').rpc<Object?>('get_profile');
    final row = _singleRow(value);
    return TeamZoneProfile.fromJson(row);
  }

  @override
  Future<List<TeamZoneContext>> getContexts() async {
    final value = await _client.schema('api').rpc<Object?>('get_my_contexts');
    if (value is! List) {
      throw const FormatException('Context response is not a list.');
    }
    // One context per team you hold roles in, not one per assignment.
    final contexts = mergeTeamContexts(
      value
          .whereType<Map<String, dynamic>>()
          .map(TeamZoneContext.fromJson)
          .toList(growable: false),
    );
    return _withOwnTitles(contexts);
  }

  /// Adds your titles (e.g. Huvudtränare) to the team contexts. Titles are
  /// descriptive only, so a failure leaves the contexts as they are.
  Future<List<TeamZoneContext>> _withOwnTitles(
    List<TeamZoneContext> contexts,
  ) async {
    if (!contexts.any((context) => context.roles.contains('leader'))) {
      return contexts;
    }
    try {
      final value = await _client
          .schema('api')
          .rpc<Object?>('get_my_team_titles')
          .timeout(const Duration(seconds: 10));
      if (value is! List) return contexts;
      final byTeam = {
        for (final row in value.whereType<Map<String, dynamic>>())
          '${row['club_id']}:${row['team_id']}': row,
      };
      List<String> strings(Object? raw) =>
          (raw as List? ?? const []).whereType<String>().toList();
      return [
        for (final context in contexts)
          if (context.roles.contains('leader')
                  ? byTeam['${context.clubId}:${context.teamId}']
                  : null
              case final row?)
            context.withTitles(
              strings(row['titles']),
              strings(row['custom_titles']),
              mainTitle: row['main_title'] as String?,
            )
          else
            context,
      ];
    } catch (_) {
      return contexts;
    }
  }

  Map<String, dynamic> _singleRow(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is List && value.length == 1) {
      final row = value.single;
      if (row is Map<String, dynamic>) return row;
    }
    throw const FormatException('Expected exactly one profile row.');
  }
}
