part of '../../app/teamzone_app.dart';

class _LegalBootstrap extends StatefulWidget {
  const _LegalBootstrap({
    required this.legal,
    required this.onSignOut,
    required this.child,
  });
  final LegalServices legal;
  final Future<void> Function() onSignOut;
  final Widget child;

  @override
  State<_LegalBootstrap> createState() => _LegalBootstrapState();
}

class _LegalBootstrapState extends State<_LegalBootstrap> {
  late Future<LegalStatus> _load;
  bool _acceptedLocally = false;
  void _reload() =>
      _load = widget.legal.getStatus().timeout(const Duration(seconds: 15));
  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<LegalStatus>(
    future: _load,
    builder: (context, snapshot) {
      final strings = AppStrings.of(context);
      if (snapshot.connectionState != ConnectionState.done) {
        return Scaffold(body: AppLoadingIndicator(label: strings.loading));
      }
      if (snapshot.hasError || !snapshot.hasData) {
        return Scaffold(
          body: Center(
            child: _StateCard(
              icon: Icons.policy_outlined,
              title: strings.feature('Villkor kunde inte kontrolleras'),
              message: strings.feature(
                'Ingen klubb- eller lagdata visas förrän kontrollen lyckas.',
              ),
              action: FilledButton(
                onPressed: () => setState(_reload),
                child: Text(strings.feature('Försök igen')),
              ),
            ),
          ),
        );
      }
      final status = snapshot.data!;
      if (_acceptedLocally || !status.requiresAcceptance) return widget.child;
      return _LegalAcceptanceScreen(
        status: status,
        legal: widget.legal,
        onAccepted: () => setState(() => _acceptedLocally = true),
        onSignOut: widget.onSignOut,
      );
    },
  );
}

class _LegalAcceptanceScreen extends StatefulWidget {
  const _LegalAcceptanceScreen({
    required this.status,
    required this.legal,
    required this.onAccepted,
    required this.onSignOut,
  });
  final LegalStatus status;
  final LegalServices legal;
  final VoidCallback onAccepted;
  final Future<void> Function() onSignOut;

  @override
  State<_LegalAcceptanceScreen> createState() => _LegalAcceptanceScreenState();
}

class _LegalAcceptanceScreenState extends State<_LegalAcceptanceScreen> {
  bool _terms = false;
  bool _privacy = false;
  bool _marketing = false;
  bool _pending = false;
  String? _error;

  Future<void> _open(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        setState(
          () => _error = AppStrings.of(
            context,
          ).feature('Dokumentet kunde inte öppnas. Försök igen.'),
        );
      }
    }
  }

  Future<void> _accept() async {
    if (_pending || !_terms || !_privacy) return;
    setState(() {
      _pending = true;
      _error = null;
    });
    try {
      await widget.legal
          .acceptCurrent(
            termsVersion: widget.status.termsVersion,
            privacyVersion: widget.status.privacyVersion,
            marketingOptIn: _marketing,
            idempotencyKey: _newUuid(),
          )
          .timeout(const Duration(seconds: 15));
      widget.onAccepted();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = AppStrings.of(context).feature(
            'Godkännandet kunde inte sparas. Läs in den aktuella versionen och försök igen.',
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
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.feature('Villkor och integritet')),
        actions: [
          TextButton(
            onPressed: _pending ? null : widget.onSignOut,
            child: Text(strings.signOut),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  strings.feature('Läs och godkänn för att fortsätta'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  strings.feature(
                    'Obligatoriska dokument är separerade från frivillig marknadsföring.',
                  ),
                ),
                const SizedBox(height: 20),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _terms,
                  onChanged: _pending
                      ? null
                      : (value) => setState(() => _terms = value ?? false),
                  title: Text(
                    strings.feature('Jag godkänner användarvillkoren'),
                  ),
                  subtitle: Text(
                    strings
                        .feature('Version {version}')
                        .replaceFirst('{version}', widget.status.termsVersion),
                  ),
                  secondary: IconButton(
                    tooltip: strings.feature('Öppna användarvillkor'),
                    onPressed: () => _open(widget.status.termsUrl),
                    icon: const Icon(Icons.open_in_new),
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _privacy,
                  onChanged: _pending
                      ? null
                      : (value) => setState(() => _privacy = value ?? false),
                  title: Text(
                    strings.feature('Jag har läst integritetspolicyn'),
                  ),
                  subtitle: Text(
                    strings
                        .feature('Version {version}')
                        .replaceFirst(
                          '{version}',
                          widget.status.privacyVersion,
                        ),
                  ),
                  secondary: IconButton(
                    tooltip: strings.feature('Öppna integritetspolicy'),
                    onPressed: () => _open(widget.status.privacyUrl),
                    icon: const Icon(Icons.open_in_new),
                  ),
                ),
                const Divider(height: 32),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _marketing,
                  onChanged: _pending
                      ? null
                      : (value) => setState(() => _marketing = value ?? false),
                  title: Text(
                    strings.feature('Jag vill få marknadsföring från TeamZone'),
                  ),
                  subtitle: Text(
                    strings.feature(
                      'Frivilligt och kan återkallas när som helst.',
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Semantics(liveRegion: true, child: Text(_error!)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _pending || !_terms || !_privacy ? null : _accept,
                  child: Text(
                    _pending
                        ? strings.feature('Sparar…')
                        : strings.feature('Godkänn och fortsätt'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MarketingPreferenceSheet extends StatefulWidget {
  const _MarketingPreferenceSheet({required this.legal});
  final LegalServices legal;
  @override
  State<_MarketingPreferenceSheet> createState() =>
      _MarketingPreferenceSheetState();
}

class _MarketingPreferenceSheetState extends State<_MarketingPreferenceSheet> {
  late Future<LegalStatus> _load;
  bool _pending = false;
  bool? _value;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load = widget.legal.getStatus().timeout(const Duration(seconds: 15));
  }

  Future<void> _save() async {
    if (_pending || _value == null) return;
    setState(() {
      _pending = true;
      _error = null;
    });
    try {
      await widget.legal
          .setMarketingPreference(
            marketingOptIn: _value!,
            idempotencyKey: _newUuid(),
          )
          .timeout(const Duration(seconds: 15));
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _pending = false;
          _error = AppStrings.of(
            context,
          ).feature('Inställningen kunde inte sparas. Försök igen.');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: FutureBuilder<LegalStatus>(
        future: _load,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return AppLoadingIndicator(label: strings.loading);
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return _StateCard(
              icon: Icons.sync_problem,
              title: strings.feature('Inställningen kunde inte laddas'),
              message: strings.feature('Försök igen om en stund.'),
            );
          }
          _value ??= snapshot.data!.marketingOptIn;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.feature('Integritetsinställningar'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _value!,
                onChanged: _pending
                    ? null
                    : (value) => setState(() => _value = value),
                title: Text(strings.feature('Marknadsföring från TeamZone')),
                subtitle: Text(
                  strings.feature(
                    'Frivilligt. Avstängt påverkar inte appens funktioner.',
                  ),
                ),
              ),
              if (_error != null)
                Semantics(liveRegion: true, child: Text(_error!)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _pending ? null : _save,
                child: Text(strings.feature('Spara')),
              ),
            ],
          );
        },
      ),
    );
  }
}
