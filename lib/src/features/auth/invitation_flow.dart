part of '../../app/teamzone_app.dart';

String? invitationTokenFromUri(Uri? uri) {
  if (uri == null) return null;
  final isInvitePath =
      uri.path == '/invite' ||
      (uri.scheme == 'teamzone' && uri.host == 'app' && uri.path == '/invite');
  if (!isInvitePath) return null;
  final token = uri.queryParameters['token']?.trim();
  if (token == null || token.length < 32 || token.length > 512) return null;
  return token;
}

class _InvitationFlow extends StatefulWidget {
  const _InvitationFlow({
    required this.token,
    required this.authenticated,
    required this.roster,
    required this.onAuthenticate,
    required this.onComplete,
    required this.onCancel,
  });

  final String token;
  final bool authenticated;
  final RosterServices roster;
  final VoidCallback onAuthenticate, onComplete, onCancel;

  @override
  State<_InvitationFlow> createState() => _InvitationFlowState();
}

class _InvitationFlowState extends State<_InvitationFlow> {
  late Future<InvitationPreview> _preview = _loadPreview();
  bool _pending = false;
  InvitationClaimResult? _result;
  String? _error;

  @override
  void didUpdateWidget(covariant _InvitationFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.token == widget.token) return;
    _preview = _loadPreview();
    _pending = false;
    _result = null;
    _error = null;
  }

  Future<InvitationPreview> _loadPreview() => widget.roster
      .previewInvitation(token: widget.token)
      .timeout(const Duration(seconds: 15));

  Future<void> _claim() async {
    if (_pending || !widget.authenticated) return;
    setState(() {
      _pending = true;
      _error = null;
    });
    try {
      final result = await widget.roster
          .claimInvitation(token: widget.token, idempotencyKey: _newUuid())
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() => _result = result);
      if (result.status == InvitationClaimStatus.claimed) widget.onComplete();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = AppStrings.of(context).feature(
            'Inbjudan kunde inte accepteras. Kontrollera att den fortfarande gäller.',
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
        title: Text(strings.feature('Inbjudan')),
        leading: IconButton(
          tooltip: strings.cancel,
          onPressed: widget.onCancel,
          icon: const Icon(Icons.close),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: FutureBuilder<InvitationPreview>(
            future: _preview,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return AppLoadingIndicator(label: strings.loading);
              }
              final preview = snapshot.data;
              if (snapshot.hasError || preview == null || !preview.isValid) {
                return _StateCard(
                  icon: Icons.link_off,
                  title: strings.feature('Inbjudan är inte tillgänglig'),
                  message: strings.feature(
                    'Länken är ogiltig, återkallad eller har gått ut.',
                  ),
                  action: FilledButton(
                    onPressed: () => setState(() => _preview = _loadPreview()),
                    child: Text(strings.retry),
                  ),
                );
              }
              if (_result?.status == InvitationClaimStatus.reviewRequired) {
                return _StateCard(
                  icon: Icons.fact_check_outlined,
                  title: strings.feature('Manuell granskning krävs'),
                  message: strings.feature(
                    'Vi kunde inte koppla inbjudan automatiskt. TeamZone visar inga kontouppgifter medan ärendet granskas.',
                  ),
                  action: FilledButton(
                    onPressed: widget.onComplete,
                    child: Text(strings.feature('Klart')),
                  ),
                );
              }
              return _StateCard(
                icon: Icons.mark_email_read_outlined,
                title: strings.feature('Du har blivit inbjuden'),
                message: [
                  preview.clubName,
                  preview.teamName,
                  preview.personName,
                  preview.rolePackage == null
                      ? null
                      : strings.feature(preview.rolePackage!),
                  preview.expiresAt == null
                      ? null
                      : '${strings.feature('Giltig till')} '
                            '${MaterialLocalizations.of(context).formatMediumDate(preview.expiresAt!.toLocal())}',
                ].whereType<String>().join('\n'),
                action: Column(
                  children: [
                    if (_error != null) ...[
                      Semantics(liveRegion: true, child: Text(_error!)),
                      const SizedBox(height: 12),
                    ],
                    FilledButton(
                      onPressed: _pending
                          ? null
                          : widget.authenticated
                          ? _claim
                          : widget.onAuthenticate,
                      child: Text(
                        widget.authenticated
                            ? strings.feature('Acceptera inbjudan')
                            : strings.feature('Logga in för att fortsätta'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
