part of '../../app/teamzone_app.dart';

class _DomainManagementSurface extends StatefulWidget {
  const _DomainManagementSurface({
    required this.clubId,
    required this.editorial,
  });
  final String clubId;
  final EditorialServices editorial;
  @override
  State<_DomainManagementSurface> createState() =>
      _DomainManagementSurfaceState();
}

class _DomainManagementSurfaceState extends State<_DomainManagementSurface> {
  late Future<DomainManagement> _load = _reload();
  bool _busy = false;
  Future<DomainManagement> _reload() =>
      widget.editorial.getDomainManagement(widget.clubId);
  void _refresh() => setState(() => _load = _reload());
  Future<void> _request() async {
    final controller = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppStrings.of(context).feature('Anslut egen domän')),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: AppStrings.of(context).feature('Domännamn'),
                  hintText: 'www.example.se',
                ),
              ),
              const SizedBox(height: 12),
              Text(
                AppStrings.of(context).feature(
                  'Domänen aktiveras först efter betalningsgodkännande, DNS-verifiering och färdigt TLS-certifikat.',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppStrings.of(context).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              AppStrings.of(context).feature('Skapa DNS-instruktion'),
            ),
          ),
        ],
      ),
    );
    final hostname = controller.text.trim().toLowerCase();
    controller.dispose();
    if (accepted != true || hostname.isEmpty) return;
    setState(() => _busy = true);
    try {
      final result = await widget.editorial.requestDomain(
        clubId: widget.clubId,
        kind: 'custom',
        hostname: hostname,
        idempotencyKey: _newUuid(),
      );
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(AppStrings.of(context).feature('DNS-instruktion')),
            content: SelectableText(
              '${result.verificationRecord}\nTXT ${result.verificationToken ?? AppStrings.of(context).feature('Token visas bara vid första begäran')}\nCNAME public.teamzoneapp.se',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppStrings.of(context).feature('Klar')),
              ),
            ],
          ),
        );
        _refresh();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).safeError)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _canonical(String? id) async {
    setState(() => _busy = true);
    try {
      await widget.editorial.setCanonicalDomain(
        clubId: widget.clubId,
        domainId: id,
      );
      if (mounted) _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).safeError)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(AppStrings.of(context).feature('Domäner')),
      actions: [
        IconButton(
          onPressed: _refresh,
          tooltip: AppStrings.of(context).feature('Uppdatera'),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _busy ? null : _request,
      icon: const Icon(Icons.add_link),
      label: Text(AppStrings.of(context).feature('Egen domän')),
    ),
    body: FutureBuilder<DomainManagement>(
      future: _load,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return AppLoadingIndicator(label: AppStrings.of(context).loading);
        }
        if (snapshot.hasError) {
          return _StateCard(
            icon: Icons.cloud_off,
            title: AppStrings.of(
              context,
            ).feature('Domänstatus kunde inte laddas'),
            message: AppStrings.of(context).safeError,
            action: FilledButton(
              onPressed: _refresh,
              child: Text(AppStrings.of(context).retry),
            ),
          );
        }
        final data = snapshot.requireData;
        final canonicalId = data.domains
            .where((domain) => domain.canonical)
            .firstOrNull
            ?.id;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.link),
                title: Text(
                  AppStrings.of(context).feature('Kostnadsfri standardadress'),
                ),
                subtitle: SelectableText(
                  data.pathAddress ??
                      AppStrings.of(
                        context,
                      ).feature('Publicera klubbsidan först'),
                ),
                trailing: IconButton(
                  tooltip: AppStrings.of(
                    context,
                  ).feature('Använd standardadressen som huvudadress'),
                  onPressed: _busy || canonicalId == null
                      ? null
                      : () => _canonical(null),
                  icon: Icon(
                    canonicalId == null
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                ),
              ),
            ),
            if (!data.teamzoneSubdomainAvailable)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.lock_clock_outlined),
                  title: Text(
                    AppStrings.of(
                      context,
                    ).feature('Premiumsubdomän kommer senare'),
                  ),
                  subtitle: Text(
                    AppStrings.of(context).feature(
                      'Wildcard DNS, TLS och automatisk routing är ännu inte aktiverade.',
                    ),
                  ),
                ),
              ),
            for (final domain in data.domains)
              Card(
                child: ListTile(
                  leading: Icon(
                    domain.state == 'active'
                        ? Icons.verified_outlined
                        : Icons.pending_outlined,
                  ),
                  title: Text(domain.hostname),
                  subtitle: Text(
                    '${domain.state} · ${domain.commercialState} · TLS ${domain.tlsState}\n${domain.verificationRecord}',
                  ),
                  isThreeLine: true,
                  trailing: domain.state == 'active'
                      ? IconButton(
                          tooltip: AppStrings.of(
                            context,
                          ).feature('Använd som huvudadress'),
                          onPressed: _busy || canonicalId == domain.id
                              ? null
                              : () => _canonical(domain.id),
                          icon: Icon(
                            canonicalId == domain.id
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                          ),
                        )
                      : null,
                ),
              ),
          ],
        );
      },
    ),
  );
}
