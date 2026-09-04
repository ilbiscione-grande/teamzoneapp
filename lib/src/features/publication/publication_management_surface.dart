part of '../../app/teamzone_app.dart';

class _PublicationManagementSurface extends StatefulWidget {
  const _PublicationManagementSurface({
    required this.clubId,
    required this.editorial,
  });
  final String clubId;
  final EditorialServices editorial;
  @override
  State<_PublicationManagementSurface> createState() =>
      _PublicationManagementSurfaceState();
}

class _PublicationManagementSurfaceState
    extends State<_PublicationManagementSurface> {
  late Future<PublicationManagement> _load = _reload();
  bool _busy = false;
  Future<PublicationManagement> _reload() =>
      widget.editorial.getPublicationManagement(widget.clubId);
  void _refresh() => setState(() => _load = _reload());

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await action();
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

  Future<void> _event(PublicEventItem item) async {
    final title = TextEditingController(text: item.publicTitle ?? item.title);
    var publishLocation = item.publishLocation;
    final publish = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(
            AppStrings.of(context).feature('Förhandsgranska händelse'),
          ),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  maxLength: 160,
                  decoration: InputDecoration(
                    labelText: AppStrings.of(context).feature('Publik titel'),
                  ),
                ),
                SwitchListTile(
                  value: publishLocation,
                  onChanged: (v) => setDialog(() => publishLocation = v),
                  title: Text(
                    AppStrings.of(context).feature('Visa plats publikt'),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.preview_outlined),
                  title: Text(title.text),
                  subtitle: Text(
                    '${item.teamName} · ${item.startsAt.toLocal()}',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(AppStrings.of(context).feature('Gör privat')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(AppStrings.of(context).feature('Publicera')),
            ),
          ],
        ),
      ),
    );
    final value = title.text.trim();
    title.dispose();
    if (publish == null) return;
    await _run(
      () => widget.editorial.configureEvent(
        eventId: item.id,
        state: publish ? 'published' : 'private',
        publicTitle: value.isEmpty ? null : value,
        publishLocation: publishLocation,
        expectedRevision: item.revision,
        idempotencyKey: _newUuid(),
      ),
    );
  }

  Future<void> _partner([PublicPartnerItem? item]) async {
    final name = TextEditingController(text: item?.name);
    final website = TextEditingController(text: item?.websiteUrl);
    final order = TextEditingController(text: '${item?.sortOrder ?? 0}');
    var state = item?.state ?? 'draft';
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(
            AppStrings.of(
              context,
            ).feature(item == null ? 'Ny partner' : 'Redigera partner'),
          ),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  maxLength: 120,
                  decoration: InputDecoration(
                    labelText: AppStrings.of(context).feature('Namn'),
                  ),
                ),
                TextField(
                  controller: website,
                  maxLength: 1000,
                  decoration: InputDecoration(
                    labelText: AppStrings.of(context).feature('HTTPS-adress'),
                  ),
                ),
                TextField(
                  controller: order,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: AppStrings.of(context).feature('Sortering'),
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: state,
                  items: const ['draft', 'published', 'unpublished']
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (v) => setDialog(() => state = v!),
                  decoration: InputDecoration(
                    labelText: AppStrings.of(context).feature('Status'),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.image_not_supported_outlined),
                  title: Text(
                    AppStrings.of(
                      context,
                    ).feature('Partnerlogotyp kommer senare'),
                  ),
                  subtitle: Text(
                    AppStrings.of(
                      context,
                    ).feature('Säker mediaworker är ännu inte konfigurerad.'),
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
              child: Text(AppStrings.of(context).feature('Spara')),
            ),
          ],
        ),
      ),
    );
    final partnerName = name.text.trim(), url = website.text.trim();
    final sort = int.tryParse(order.text) ?? 0;
    name.dispose();
    website.dispose();
    order.dispose();
    if (save != true || partnerName.isEmpty) return;
    await _run(
      () => widget.editorial.savePartner(
        clubId: widget.clubId,
        partnerId: item?.id,
        name: partnerName,
        websiteUrl: url.isEmpty ? null : url,
        state: state,
        sortOrder: sort,
        expectedRevision: item?.revision ?? 0,
        idempotencyKey: _newUuid(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(AppStrings.of(context).feature('Event och partners')),
      actions: [
        IconButton(
          onPressed: () => Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => _DomainManagementSurface(
                clubId: widget.clubId,
                editorial: widget.editorial,
              ),
            ),
          ),
          tooltip: AppStrings.of(context).feature('Domäner'),
          icon: const Icon(Icons.language),
        ),
        IconButton(
          onPressed: _refresh,
          tooltip: AppStrings.of(context).feature('Uppdatera'),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<PublicationManagement>(
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
            ).feature('Publiceringsdata kunde inte laddas'),
            message: AppStrings.of(context).safeError,
            action: FilledButton(
              onPressed: _refresh,
              child: Text(AppStrings.of(context).retry),
            ),
          );
        }
        final data = snapshot.requireData;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              AppStrings.of(context).feature('Publika händelser'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              AppStrings.of(context).feature(
                'Endast titel, tid, typ och uttryckligt vald plats publiceras.',
              ),
            ),
            if (data.events.isEmpty) ...[
              ListTile(
                leading: const Icon(Icons.event_busy),
                title: Text(
                  AppStrings.of(context).feature('Inga publicerbara händelser'),
                ),
              ),
            ],
            for (final item in data.events)
              Card(
                child: ListTile(
                  leading: Icon(
                    item.publicationState == 'published'
                        ? Icons.public
                        : Icons.public_off,
                  ),
                  title: Text(item.publicTitle ?? item.title),
                  subtitle: Text(
                    '${item.teamName} · ${item.eventType} · ${item.startsAt.toLocal()}',
                  ),
                  trailing: IconButton(
                    onPressed: _busy ? null : () => _event(item),
                    tooltip: AppStrings.of(
                      context,
                    ).feature('Hantera publicering'),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ),
              ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    AppStrings.of(context).feature('Partners'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (data.canManagePartners)
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _partner(),
                    icon: const Icon(Icons.add),
                    label: Text(AppStrings.of(context).feature('Ny partner')),
                  ),
              ],
            ),
            if (!data.canManagePartners) ...[
              Text(
                AppStrings.of(
                  context,
                ).feature('Partnerhantering kräver klubbmandat.'),
              ),
            ],
            for (final item in data.partners)
              Card(
                child: ListTile(
                  leading: Icon(
                    item.mediaStatus == 'ready'
                        ? Icons.image_outlined
                        : Icons.image_not_supported_outlined,
                  ),
                  title: Text(item.name),
                  subtitle: Text(
                    '${item.state}${item.websiteUrl == null ? '' : ' · ${item.websiteUrl}'}',
                  ),
                  onTap: _busy ? null : () => _partner(item),
                ),
              ),
          ],
        );
      },
    ),
  );
}
