part of '../../app/teamzone_app.dart';

class _SignInScreen extends StatefulWidget {
  const _SignInScreen({
    required this.identity,
    required this.authEntry,
    required this.environment,
    required this.isConfigured,
    required this.sessionEnded,
  });

  final IdentityServices identity;
  final AuthEntryServices authEntry;
  final AppEnvironment environment;
  final bool isConfigured;
  final bool sessionEnded;

  @override
  State<_SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<_SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _submission = AppFormController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _code = TextEditingController();
  final _challenge = EmailChallengeController();
  Timer? _challengeTimer;
  _AuthStartMode _mode = _AuthStartMode.signIn;
  _AuthMethod _method = _AuthMethod.password;
  String? _error;
  String? _message;
  bool _sharedDevice = false;

  Future<void> _prepareSessionPersistence() async {
    final identity = widget.identity;
    if (identity is SessionPersistenceControl) {
      await (identity as SessionPersistenceControl).setSessionPersistence(
        persist: !_sharedDevice,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _email.addListener(_submission.markDirty);
    _password.addListener(_submission.markDirty);
    _confirmPassword.addListener(_submission.markDirty);
    _code.addListener(_submission.markDirty);
    _challengeTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _challenge.tick(),
    );
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _code.dispose();
    _challengeTimer?.cancel();
    _challenge.dispose();
    _submission.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!widget.isConfigured || !_submission.canSubmit) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _error = null);
    try {
      await _prepareSessionPersistence();
      await _submission.run(
        () => widget.identity
            .signIn(email: _email.text.trim(), password: _password.text)
            .timeout(const Duration(seconds: 15)),
      );
    } on TimeoutException {
      if (!mounted) return;
      setState(() => _error = AppStrings.of(context).signInTimeout);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = AppStrings.of(context).signInFailed);
    }
  }

  bool _validEmail() => _formKey.currentState?.validate() ?? false;

  bool _emailValueIsValid() =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_email.text.trim());

  Future<void> _submitPassword() async {
    if (_mode == _AuthStartMode.signIn) {
      return _signIn();
    }
    if (!widget.isConfigured || !_submission.canSubmit || !_validEmail()) {
      return;
    }
    setState(() {
      _error = null;
      _message = null;
    });
    try {
      await _prepareSessionPersistence();
      final result = await _run(
        () => widget.authEntry.signUpWithPassword(
          email: _email.text.trim(),
          password: _password.text,
        ),
      );
      if (result != null && mounted) {
        setState(
          () => _message = AppStrings.of(context).feature(
            'Kontrollera din e-post och verifiera adressen innan du loggar in.',
          ),
        );
      }
    } catch (_) {
      _safeFailure();
    }
  }

  Future<T?> _run<T>(Future<T> Function() action) async {
    T? value;
    final completed = await _submission.run(() async {
      value = await action().timeout(const Duration(seconds: 15));
    });
    return completed ? value : null;
  }

  Future<void> _requestChallenge() async {
    if (!widget.isConfigured || !_submission.canSubmit || !_validEmail()) {
      return;
    }
    setState(() {
      _error = null;
      _message = null;
    });
    try {
      await _prepareSessionPersistence();
      await _run(
        () => widget.authEntry.requestEmailChallenge(
          email: _email.text.trim(),
          purpose: _mode == _AuthStartMode.signIn
              ? EmailChallengePurpose.signIn
              : EmailChallengePurpose.signUp,
        ),
      );
      _challenge.markSent();
      if (mounted) {
        setState(
          () => _message = AppStrings.of(
            context,
          ).feature('Vi har skickat en e-postkod eller säker inloggningslänk.'),
        );
      }
    } catch (_) {
      _safeFailure();
    }
  }

  Future<void> _verifyChallenge() async {
    if (_challenge.isExpired) {
      setState(
        () => _error = AppStrings.of(
          context,
        ).feature('Koden har gått ut. Skicka en ny kod.'),
      );
      return;
    }
    if (_code.text.trim().length < 6 || !_submission.canSubmit) {
      return;
    }
    setState(() => _error = null);
    try {
      await _run(
        () => widget.authEntry.verifyEmailChallenge(
          email: _email.text.trim(),
          code: _code.text.trim(),
        ),
      );
    } catch (_) {
      _safeFailure();
    }
  }

  Future<void> _requestReset() async {
    if (!_emailValueIsValid() || !_submission.canSubmit) {
      _formKey.currentState?.validate();
      return;
    }
    try {
      await _run(
        () => widget.authEntry.requestPasswordReset(email: _email.text.trim()),
      );
    } catch (_) {
      // The same response prevents account enumeration.
    }
    if (mounted) {
      setState(
        () => _message = AppStrings.of(context).feature(
          'Om adressen är registrerad skickas instruktioner för att återställa lösenordet.',
        ),
      );
    }
  }

  void _safeFailure() {
    if (!mounted) return;
    setState(
      () => _error = AppStrings.of(context).feature(
        'Det gick inte att slutföra åtgärden. Kontrollera uppgifterna och försök igen.',
      ),
    );
  }

  void _changeMode(_AuthStartMode mode) {
    setState(() {
      _mode = mode;
      _error = null;
      _message = null;
      _challenge.clear();
      _code.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([_submission, _challenge]),
      builder: (context, _) => Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: AutofillGroup(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'TeamZone',
                          style: Theme.of(context).textTheme.displaySmall,
                        ),
                        const SizedBox(height: 8),
                        Text(strings.environment(widget.environment.name)),
                        const SizedBox(height: 32),
                        if (!widget.isConfigured)
                          _StateCard(
                            icon: Icons.construction,
                            title: strings.backendNotConnected,
                            message: strings.backendInstructions,
                          )
                        else ...[
                          if (widget.sessionEnded) ...[
                            _StateCard(
                              icon: Icons.lock_clock_outlined,
                              title: strings.feature('Sessionen har avslutats'),
                              message: strings.feature(
                                'Logga in igen för att fortsätta. Ingen skyddad data visas.',
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          SegmentedButton<_AuthStartMode>(
                            segments: [
                              ButtonSegment(
                                value: _AuthStartMode.signIn,
                                label: Text(strings.signIn),
                                icon: const Icon(Icons.login),
                              ),
                              ButtonSegment(
                                value: _AuthStartMode.createAccount,
                                label: Text(strings.feature('Skapa konto')),
                                icon: const Icon(Icons.person_add_alt_1),
                              ),
                            ],
                            selected: {_mode},
                            onSelectionChanged: _submission.isPending
                                ? null
                                : (selection) => _changeMode(selection.single),
                          ),
                          const SizedBox(height: 16),
                          SegmentedButton<_AuthMethod>(
                            segments: [
                              ButtonSegment(
                                value: _AuthMethod.password,
                                label: Text(strings.password),
                              ),
                              ButtonSegment(
                                value: _AuthMethod.emailCode,
                                label: Text(strings.feature('E-postkod/länk')),
                              ),
                            ],
                            selected: {_method},
                            onSelectionChanged: _submission.isPending
                                ? null
                                : (selection) => setState(() {
                                    _method = selection.single;
                                    _error = null;
                                    _message = null;
                                  }),
                          ),
                          const SizedBox(height: 20),
                          if (kIsWeb) ...[
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _sharedDevice,
                              onChanged: _submission.isPending
                                  ? null
                                  : (value) => setState(
                                      () => _sharedDevice = value ?? false,
                                    ),
                              title: Text(strings.feature('Delad enhet')),
                              subtitle: Text(
                                strings.feature(
                                  'Spara inte inloggningen i den här webbläsaren.',
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          TextFormField(
                            controller: _email,
                            enabled: !_submission.isPending,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.email],
                            validator: (value) {
                              final email = value?.trim() ?? '';
                              if (email.isEmpty) return strings.emailRequired;
                              if (!RegExp(
                                r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                              ).hasMatch(email)) {
                                return strings.emailInvalid;
                              }
                              return null;
                            },
                            decoration: InputDecoration(
                              labelText: strings.email,
                            ),
                          ),
                          if (_method == _AuthMethod.password) ...[
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _password,
                              enabled: !_submission.isPending,
                              obscureText: true,
                              textInputAction:
                                  _mode == _AuthStartMode.createAccount
                                  ? TextInputAction.next
                                  : TextInputAction.done,
                              autofillHints: [
                                _mode == _AuthStartMode.createAccount
                                    ? AutofillHints.newPassword
                                    : AutofillHints.password,
                              ],
                              onFieldSubmitted: (_) {
                                if (_mode == _AuthStartMode.signIn) {
                                  _submitPassword();
                                }
                              },
                              validator: (value) {
                                if (value?.isEmpty ?? true) {
                                  return strings.passwordRequired;
                                }
                                if (_mode == _AuthStartMode.createAccount &&
                                    value!.length < 8) {
                                  return strings.feature(
                                    'Lösenordet måste innehålla minst 8 tecken.',
                                  );
                                }
                                return null;
                              },
                              decoration: InputDecoration(
                                labelText: strings.password,
                              ),
                            ),
                            if (_mode == _AuthStartMode.createAccount) ...[
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _confirmPassword,
                                enabled: !_submission.isPending,
                                obscureText: true,
                                textInputAction: TextInputAction.done,
                                autofillHints: const [
                                  AutofillHints.newPassword,
                                ],
                                validator: (value) => value != _password.text
                                    ? strings.feature(
                                        'Lösenorden måste vara identiska.',
                                      )
                                    : null,
                                onFieldSubmitted: (_) => _submitPassword(),
                                decoration: InputDecoration(
                                  labelText: strings.feature(
                                    'Bekräfta lösenord',
                                  ),
                                ),
                              ),
                            ],
                          ] else if (_challenge.hasChallenge) ...[
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _code,
                              enabled: !_submission.isPending,
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.oneTimeCode],
                              onFieldSubmitted: (_) => _verifyChallenge(),
                              decoration: InputDecoration(
                                labelText: strings.feature('E-postkod'),
                                helperText: _challenge.isExpired
                                    ? strings.feature('Koden har gått ut.')
                                    : strings.feature(
                                        'Koden gäller i 10 minuter. Du kan också använda länken i mejlet.',
                                      ),
                              ),
                            ),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: 16),
                            Semantics(liveRegion: true, child: Text(_error!)),
                          ],
                          if (_message != null) ...[
                            const SizedBox(height: 16),
                            Semantics(liveRegion: true, child: Text(_message!)),
                          ],
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: _submission.isPending
                                ? null
                                : _method == _AuthMethod.password
                                ? _submitPassword
                                : _challenge.hasChallenge
                                ? _verifyChallenge
                                : _requestChallenge,
                            child: _submission.isPending
                                ? SizedBox.square(
                                    dimension: 20,
                                    child: Semantics(
                                      label: strings.loading,
                                      liveRegion: true,
                                      child: const ExcludeSemantics(
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    ),
                                  )
                                : Text(
                                    _method == _AuthMethod.emailCode
                                        ? _challenge.hasChallenge
                                              ? strings.feature('Verifiera kod')
                                              : strings.feature(
                                                  'Skicka e-postkod/länk',
                                                )
                                        : _mode == _AuthStartMode.signIn
                                        ? strings.signIn
                                        : strings.feature('Skapa konto'),
                                  ),
                          ),
                          if (_method == _AuthMethod.emailCode &&
                              _challenge.hasChallenge) ...[
                            TextButton(
                              onPressed:
                                  _submission.isPending || !_challenge.canResend
                                  ? null
                                  : _requestChallenge,
                              child: Text(
                                _challenge.canResend
                                    ? strings.feature('Skicka ny kod')
                                    : strings
                                          .feature(
                                            'Skicka ny kod om {seconds} s',
                                          )
                                          .replaceFirst(
                                            '{seconds}',
                                            '${_challenge.resendWait.inSeconds + 1}',
                                          ),
                              ),
                            ),
                          ],
                          if (_mode == _AuthStartMode.signIn &&
                              _method == _AuthMethod.password)
                            TextButton(
                              onPressed: _submission.isPending
                                  ? null
                                  : _requestReset,
                              child: Text(strings.feature('Glömt lösenord?')),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _AuthStartMode { signIn, createAccount }

enum _AuthMethod { password, emailCode }

class _ResetPasswordScreen extends StatefulWidget {
  const _ResetPasswordScreen({
    required this.authEntry,
    required this.onComplete,
  });
  final AuthEntryServices authEntry;
  final VoidCallback onComplete;
  @override
  State<_ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<_ResetPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _submission = AppFormController();
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    _submission.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    try {
      await _submission.run(
        () => widget.authEntry.updatePassword(password: _password.text),
      );
      widget.onComplete();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = AppStrings.of(context).feature(
            'Lösenordet kunde inte uppdateras. Begär en ny återställningslänk.',
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(AppStrings.of(context).feature('Nytt lösenord')),
    ),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    autofillHints: const [AutofillHints.newPassword],
                    textInputAction: TextInputAction.next,
                    validator: (value) => (value?.length ?? 0) < 8
                        ? AppStrings.of(context).feature(
                            'Lösenordet måste innehålla minst 8 tecken.',
                          )
                        : null,
                    decoration: InputDecoration(
                      labelText: AppStrings.of(context).password,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirm,
                    obscureText: true,
                    autofillHints: const [AutofillHints.newPassword],
                    textInputAction: TextInputAction.done,
                    validator: (value) => value != _password.text
                        ? AppStrings.of(
                            context,
                          ).feature('Lösenorden måste vara identiska.')
                        : null,
                    onFieldSubmitted: (_) => _save(),
                    decoration: InputDecoration(
                      labelText: AppStrings.of(
                        context,
                      ).feature('Bekräfta lösenord'),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Semantics(liveRegion: true, child: Text(_error!)),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _submission.isPending ? null : _save,
                    child: Text(
                      AppStrings.of(context).feature('Spara lösenord'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _ContextBootstrap extends StatefulWidget {
  const _ContextBootstrap({
    required this.services,
    required this.matchSpaceV2,
    required this.onSignOut,
  });

  final AppServices services;
  final bool matchSpaceV2;
  final Future<void> Function() onSignOut;

  @override
  State<_ContextBootstrap> createState() => _ContextBootstrapState();
}

class _ContextBootstrapState extends State<_ContextBootstrap> {
  late Future<({TeamZoneProfile profile, List<TeamZoneContext> contexts})>
  _load;

  @override
  void initState() {
    super.initState();
    _retry();
  }

  void _retry() {
    _load =
        Future.wait<Object>([
              widget.services.identity.getProfile(),
              widget.services.identity.getContexts(),
            ])
            .timeout(const Duration(seconds: 15))
            .then(
              (values) => (
                profile: values[0] as TeamZoneProfile,
                contexts: values[1] as List<TeamZoneContext>,
              ),
            );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<
      ({TeamZoneProfile profile, List<TeamZoneContext> contexts})
    >(
      future: _load,
      builder: (context, snapshot) {
        final strings = AppStrings.of(context);
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(body: AppLoadingIndicator(label: strings.loading));
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: _StateCard(
                icon: Icons.sync_problem,
                title: strings.startupFailed,
                message: strings.retryProfile,
                action: FilledButton(
                  onPressed: () => setState(_retry),
                  child: Text(strings.retry),
                ),
              ),
            ),
          );
        }
        final data = snapshot.requireData;
        if (data.contexts.isEmpty) {
          return _WaitingRoom(
            profile: data.profile,
            identity: widget.services.identity,
            contextPersistence: widget.services.contextPersistence,
            onSignOut: widget.onSignOut,
            roster: widget.services.roster,
            membership: widget.services.membership,
            onClaimed: () => setState(_retry),
          );
        }
        return _ContextSelector(
          profile: data.profile,
          contexts: data.contexts,
          identity: widget.services.identity,
          contextPersistence: widget.services.contextPersistence,
          onSignOut: widget.onSignOut,
          roster: widget.services.roster,
          membership: widget.services.membership,
          legal: widget.services.legal,
          calendar: widget.services.calendar,
          overview: widget.services.overview,
          messaging: widget.services.messaging,
          match: widget.services.match,
          development: widget.services.development,
          billing: widget.services.billing,
          economy: widget.services.economy,
          board: widget.services.board,
          matchSpaceV2: widget.matchSpaceV2,
        );
      },
    );
  }
}

class _WaitingRoom extends StatefulWidget {
  const _WaitingRoom({
    required this.profile,
    required this.identity,
    required this.contextPersistence,
    required this.onSignOut,
    required this.roster,
    required this.membership,
    required this.onClaimed,
  });

  final TeamZoneProfile profile;
  final IdentityServices identity;
  final ContextPersistence contextPersistence;
  final Future<void> Function() onSignOut;
  final RosterServices roster;
  final MembershipServices membership;
  final VoidCallback onClaimed;

  @override
  State<_WaitingRoom> createState() => _WaitingRoomState();
}

class _WaitingRoomState extends State<_WaitingRoom> {
  final _token = TextEditingController();
  bool _pending = false;
  String? _message;

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _claim() async {
    if (_pending || _token.text.trim().isEmpty) return;
    setState(() {
      _pending = true;
      _message = null;
    });
    try {
      await widget.roster.claim(
        token: _token.text.trim(),
        idempotencyKey: _newUuid(),
      );
      widget.onClaimed();
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = AppStrings.of(
            context,
          ).feature('Inbjudan är ogiltig eller har gått ut.'),
        );
      }
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  Future<void> _acceptGuardianInvite() async {
    if (_pending || _token.text.trim().isEmpty) return;
    setState(() {
      _pending = true;
      _message = null;
    });
    try {
      await widget.roster.acceptGuardianInvite(
        token: _token.text.trim(),
        idempotencyKey: _newUuid(),
      );
      widget.onClaimed();
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = AppStrings.of(
            context,
          ).feature('Guardianinbjudan är ogiltig eller har gått ut.'),
        );
      }
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('TeamZone'),
        actions: [
          IconButton(
            tooltip: strings.signOut,
            onPressed: widget.onSignOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: _StateCard(
          icon: Icons.hourglass_top,
          title: strings.welcome(widget.profile.displayName),
          message: strings.waitingRoom,
          action: Column(
            children: [
              TextField(
                controller: _token,
                enabled: !_pending,
                decoration: InputDecoration(
                  labelText: AppStrings.of(
                    context,
                  ).feature('Säker inbjudningskod'),
                ),
              ),
              if (_message != null) ...[
                const SizedBox(height: 8),
                Semantics(liveRegion: true, child: Text(_message!)),
              ],
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _pending ? null : _claim,
                child: Text(_pending ? 'Verifierar…' : 'Acceptera inbjudan'),
              ),
              TextButton(
                onPressed: _pending ? null : _acceptGuardianInvite,
                child: Text(
                  AppStrings.of(context).feature('Acceptera som guardian'),
                ),
              ),
              const Divider(height: 32),
              OutlinedButton.icon(
                onPressed: _pending
                    ? null
                    : () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: true,
                        builder: (_) => _MembershipJoinSheet(
                          membership: widget.membership,
                          onApproved: widget.onClaimed,
                        ),
                      ),
                icon: const Icon(Icons.search),
                label: Text(strings.feature('Hitta klubb eller lag')),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _pending
                    ? null
                    : () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: true,
                        builder: (_) => _CreateClubSheet(
                          membership: widget.membership,
                          onCreated: () {
                            Navigator.pop(context);
                            widget.onClaimed();
                          },
                        ),
                      ),
                icon: const Icon(Icons.add_business_outlined),
                label: Text(strings.feature('Skapa klubb och första lag')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreateClubSheet extends StatefulWidget {
  const _CreateClubSheet({required this.membership, required this.onCreated});

  final MembershipServices membership;
  final VoidCallback onCreated;

  @override
  State<_CreateClubSheet> createState() => _CreateClubSheetState();
}

class _CreateClubSheetState extends State<_CreateClubSheet> {
  final _formKey = GlobalKey<FormState>();
  final _clubName = TextEditingController();
  final _teamName = TextEditingController();
  bool _pending = false;
  String? _error;

  @override
  void dispose() {
    _clubName.dispose();
    _teamName.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_pending || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _pending = true;
      _error = null;
    });
    try {
      final nameCheck = await widget.membership
          .checkClubName(name: _clubName.text.trim())
          .timeout(const Duration(seconds: 15));
      if (nameCheck.status != ClubNameCheckStatus.available) {
        if (mounted) {
          setState(
            () => _error = AppStrings.of(context).feature(
              nameCheck.status == ClubNameCheckStatus.reviewRequired
                  ? 'Namnet är skyddat eller används redan. Välj ett tydligt alternativt namn eller kontakta TeamZone för granskning.'
                  : 'Klubbnamnet kan inte användas. Kontrollera namnet och försök igen.',
            ),
          );
        }
        return;
      }
      await widget.membership
          .createClubWithFirstTeam(
            clubName: _clubName.text.trim(),
            teamName: _teamName.text.trim(),
            idempotencyKey: _newUuid(),
          )
          .timeout(const Duration(seconds: 15));
      if (mounted) widget.onCreated();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = AppStrings.of(context).feature(
            'Klubben kunde inte skapas. Kontrollera namnen och försök igen.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: ListView(
          children: [
            Text(
              strings.feature('Skapa klubb och första lag'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              strings.feature(
                'Klubben skapas som inofficiell. Du blir klubbadministratör och får en aktiv lagkontext.',
              ),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _clubName,
              enabled: !_pending,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: strings.feature('Klubbnamn'),
              ),
              validator: (value) {
                final length = value?.trim().length ?? 0;
                return length < 2 || length > 120
                    ? strings.feature('Ange ett klubbnamn med 2–120 tecken.')
                    : null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _teamName,
              enabled: !_pending,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: strings.feature('Första lagets namn'),
              ),
              validator: (value) {
                final length = value?.trim().length ?? 0;
                return length < 1 || length > 120
                    ? strings.feature('Ange ett lagnamn med 1–120 tecken.')
                    : null;
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Semantics(liveRegion: true, child: Text(_error!)),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _pending ? null : _submit,
              icon: _pending
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_business_outlined),
              label: Text(strings.feature('Skapa klubb och lag')),
            ),
          ],
        ),
      ),
    );
  }
}

class _MembershipJoinSheet extends StatefulWidget {
  const _MembershipJoinSheet({
    required this.membership,
    required this.onApproved,
  });

  final MembershipServices membership;
  final VoidCallback onApproved;

  @override
  State<_MembershipJoinSheet> createState() => _MembershipJoinSheetState();
}

class _MembershipJoinSheetState extends State<_MembershipJoinSheet> {
  final _query = TextEditingController();
  bool _pending = false;
  String? _error;
  List<ClubTeamSearchResult> _results = const [];
  List<MembershipApplication> _applications = const [];

  @override
  void initState() {
    super.initState();
    _loadApplications();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _loadApplications() async {
    try {
      final value = await widget.membership.listMine().timeout(
        const Duration(seconds: 15),
      );
      if (mounted) setState(() => _applications = value);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = AppStrings.of(
            context,
          ).feature('Ansökningarna kunde inte hämtas.'),
        );
      }
    }
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    if (_pending || query.length < 3) return;
    setState(() {
      _pending = true;
      _error = null;
    });
    try {
      final value = await widget.membership
          .search(query: query)
          .timeout(const Duration(seconds: 15));
      if (mounted) setState(() => _results = value);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = AppStrings.of(
            context,
          ).feature('Sökningen kunde inte genomföras. Försök igen.'),
        );
      }
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  Future<void> _apply(ClubTeamSearchResult target) async {
    final strings = AppStrings.of(context);
    MembershipRole role = MembershipRole.player;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('${target.clubName} – ${target.teamName}'),
          content: DropdownButtonFormField<MembershipRole>(
            initialValue: role,
            decoration: InputDecoration(
              labelText: strings.feature('Ansök som'),
            ),
            items: MembershipRole.values
                .map(
                  (value) => DropdownMenuItem(
                    value: value,
                    child: Text(switch (value) {
                      MembershipRole.player => strings.feature('Spelare'),
                      MembershipRole.leader => strings.feature('Ledare'),
                      MembershipRole.guardian => strings.feature(
                        'Vårdnadshavare',
                      ),
                      MembershipRole.clubFunctionary => strings.feature(
                        'Klubbfunktionär',
                      ),
                    }),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              if (value != null) setDialogState(() => role = value);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(strings.feature('Avbryt')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(strings.feature('Skicka ansökan')),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _pending = true);
    try {
      await widget.membership.apply(
        teamId: target.teamId,
        role: role,
        idempotencyKey: _newUuid(),
      );
      await _loadApplications();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = AppStrings.of(
            context,
          ).feature('Ansökan kunde inte skickas.'),
        );
      }
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  Future<void> _withdraw(MembershipApplication application) async {
    setState(() => _pending = true);
    try {
      await widget.membership.withdraw(
        applicationId: application.id,
        idempotencyKey: _newUuid(),
      );
      await _loadApplications();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = AppStrings.of(
            context,
          ).feature('Ansökan kunde inte återkallas.'),
        );
      }
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: ListView(
        children: [
          Text(
            strings.feature('Hitta klubb eller lag'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            strings.feature(
              'Sök med minst tre tecken. Endast grundläggande, offentlig organisationsinformation visas.',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _query,
            enabled: !_pending,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              labelText: strings.feature('Klubb eller lag'),
              suffixIcon: IconButton(
                onPressed: _pending ? null : _search,
                icon: const Icon(Icons.search),
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Semantics(liveRegion: true, child: Text(_error!)),
            ),
          if (_applications.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              strings.feature('Mina ansökningar'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            ..._applications.map(
              (application) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${application.clubName} – ${application.teamName}',
                ),
                subtitle: Text(
                  '${strings.statusLabel}: ${strings.domainValue(application.status.name)}',
                ),
                trailing:
                    application.status == MembershipApplicationStatus.pending
                    ? TextButton(
                        onPressed: _pending
                            ? null
                            : () => _withdraw(application),
                        child: Text(strings.feature('Dra tillbaka ansökan')),
                      )
                    : null,
              ),
            ),
          ],
          const SizedBox(height: 16),
          ..._results.map(
            (result) => Card(
              child: ListTile(
                leading: Icon(
                  result.clubIsOfficial
                      ? Icons.verified
                      : Icons.groups_outlined,
                ),
                title: Text(result.clubName),
                subtitle: Text(
                  '${result.teamName}\n${result.clubIsOfficial ? strings.feature('Officiell klubb') : strings.feature('Inofficiell klubb')}',
                ),
                isThreeLine: true,
                trailing: FilledButton(
                  onPressed: _pending ? null : () => _apply(result),
                  child: Text(strings.feature('Ansök')),
                ),
              ),
            ),
          ),
          if (_pending)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

String _newUuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class _ContextSelector extends StatefulWidget {
  const _ContextSelector({
    required this.profile,
    required this.contexts,
    required this.identity,
    required this.contextPersistence,
    required this.onSignOut,
    required this.roster,
    required this.membership,
    required this.legal,
    required this.calendar,
    required this.overview,
    required this.messaging,
    required this.match,
    required this.development,
    required this.billing,
    required this.economy,
    required this.board,
    required this.matchSpaceV2,
  });

  final TeamZoneProfile profile;
  final List<TeamZoneContext> contexts;
  final IdentityServices identity;
  final ContextPersistence contextPersistence;
  final Future<void> Function() onSignOut;
  final RosterServices roster;
  final MembershipServices membership;
  final LegalServices legal;
  final CalendarServices calendar;
  final OverviewServices overview;
  final MessagingServices messaging;
  final MatchServices match;
  final DevelopmentServices development;
  final BillingServices billing;
  final EconomyServices economy;
  final BoardServices board;
  final bool matchSpaceV2;

  @override
  State<_ContextSelector> createState() => _ContextSelectorState();
}

class _ContextSelectorState extends State<_ContextSelector> {
  TeamZoneContext? _activeContext;

  @override
  void initState() {
    super.initState();
    _restoreContext();
  }

  Future<void> _restoreContext() async {
    final stored = await widget.contextPersistence.readActiveContextId(
      widget.profile.id,
    );
    if (!mounted) return;
    final selected = selectValidContext(widget.contexts, stored);
    setState(() => _activeContext = selected);
    if (stored != selected.id) {
      await widget.contextPersistence.writeActiveContextId(
        widget.profile.id,
        selected.id,
      );
    }
  }

  Future<void> _changeContext(TeamZoneContext value) async {
    setState(() => _activeContext = value);
    await widget.contextPersistence.writeActiveContextId(
      widget.profile.id,
      value.id,
    );
  }

  Future<void> _signOut() async {
    await widget.contextPersistence.clear(widget.profile.id);
    await widget.onSignOut();
  }

  @override
  Widget build(BuildContext context) {
    final activeContext = _activeContext;
    if (activeContext == null) {
      return Scaffold(
        body: AppLoadingIndicator(label: AppStrings.of(context).loading),
      );
    }
    return _ProductShell(
      key: ValueKey(activeContext.id),
      contextValue: activeContext,
      contexts: widget.contexts,
      onContextChanged: _changeContext,
      onSignOut: _signOut,
      roster: widget.roster,
      membership: widget.membership,
      legal: widget.legal,
      calendar: widget.calendar,
      overview: widget.overview,
      messaging: widget.messaging,
      match: widget.match,
      development: widget.development,
      billing: widget.billing,
      economy: widget.economy,
      board: widget.board,
      matchSpaceV2: widget.matchSpaceV2,
    );
  }
}
