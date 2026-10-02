part of '../../app/teamzone_app.dart';

class _ContactChangeRequests extends StatefulWidget {
  const _ContactChangeRequests({required this.profile, this.onChanged});
  final ProfileServices profile;
  final VoidCallback? onChanged;
  @override
  State<_ContactChangeRequests> createState() => _ContactChangeRequestsState();
}

class _ContactChangeRequestsState extends State<_ContactChangeRequests> {
  late Future<List<ContactChangeRequest>> _load = widget.profile
      .listContactChanges();
  bool _busy = false;
  String? _error;
  void _refresh() => setState(() {
    _load = widget.profile.listContactChanges();
  });

  Future<void> _decide(ContactChangeRequest request, bool approve) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.profile.decideContactChange(request.id, approve: approve);
      if (!mounted) return;
      widget.onChanged?.call();
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.of(context).feature(
              approve
                  ? 'Kontaktuppgifterna är uppdaterade i alla dina lag och klubbar.'
                  : 'Ändringsförslaget är avvisat.',
            ),
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = AppStrings.of(context).feature(
            'Förslaget kunde inte hanteras. Uppdatera listan och försök igen.',
          );
        });
        _refresh();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return FutureBuilder<List<ContactChangeRequest>>(
      future: _load,
      builder: (context, snapshot) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            title: Text(strings.feature('Kontaktuppdateringar')),
            subtitle: Text(
              strings.feature(
                'För dig och barn du är behörig vårdnadshavare för.',
              ),
            ),
            trailing: IconButton(
              onPressed: _busy ? null : _refresh,
              tooltip: strings.feature('Uppdatera'),
              icon: const Icon(Icons.refresh),
            ),
          ),
          if (_error != null || snapshot.hasError)
            Text(
              _error ?? strings.feature('Förslagen kunde inte hämtas.'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (snapshot.connectionState == ConnectionState.waiting)
            const LinearProgressIndicator(),
          if (snapshot.hasData && snapshot.data!.isEmpty)
            Text(strings.feature('Inga väntande ändringsförslag.')),
          for (final request in snapshot.data ?? const <ContactChangeRequest>[])
            Card(
              key: ValueKey('contact-request-${request.id}'),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      request.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(request.clubName),
                    const SizedBox(height: 8),
                    Text(
                      strings.feature(
                        'Godkända uppgifter gäller i alla lag och klubbar. Inloggningsadressen ändras inte.',
                      ),
                    ),
                    for (final field in const {
                      'email': 'E-post',
                      'phone': 'Telefon',
                      'street': 'Gatuadress',
                      'postal': 'Postnummer',
                      'city': 'Postort',
                    }.entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              strings.feature(field.value),
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            Text(
                              '${strings.feature('Nuvarande')}: ${request.before[field.key] ?? '—'}',
                            ),
                            Text(
                              '${strings.feature('Föreslaget')}: ${request.proposed[field.key] ?? '—'}',
                            ),
                          ],
                        ),
                      ),
                    if (request.conflict)
                      Text(
                        strings.feature(
                          'Uppgifterna har ändrats sedan förslaget skapades. Avvisa och be om ett nytt förslag.',
                        ),
                      ),
                    Wrap(
                      spacing: 12,
                      children: [
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _decide(request, false),
                          child: Text(strings.feature('Avvisa')),
                        ),
                        FilledButton(
                          key: ValueKey('approve-contact-${request.id}'),
                          onPressed: _busy || request.conflict
                              ? null
                              : () => _decide(request, true),
                          child: Text(strings.feature('Godkänn ändringen')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
