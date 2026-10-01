part of '../../app/teamzone_app.dart';

String _publicationModeLabel(Object? mode) => switch (mode) {
  'private' => 'Privat',
  'listed' => 'Endast i katalogen',
  'published' => 'Publicerad',
  _ => 'Okänd synlighet',
};

String _publicationRequestLabel(Object? status) => switch (status) {
  'pending' => 'Väntar på beslut',
  'approved' => 'Godkänd',
  'rejected' => 'Avslagen',
  null => 'Ingen ansökan',
  _ => 'Okänd status',
};

class _PublicationSelfServiceSurface extends StatefulWidget {
  const _PublicationSelfServiceSurface({
    required this.clubId,
    required this.editorial,
  });
  final String clubId;
  final EditorialServices editorial;
  @override
  State<_PublicationSelfServiceSurface> createState() =>
      _PublicationSelfServiceSurfaceState();
}

class _PublicationSelfServiceSurfaceState
    extends State<_PublicationSelfServiceSurface> {
  late Future<Map<String, dynamic>> _data = widget.editorial
      .getPublicationSelfService(widget.clubId);
  bool _busy = false;

  void _reload() {
    final next = widget.editorial.getPublicationSelfService(widget.clubId);
    setState(() {
      _data = next;
    });
  }

  Future<void> _run(
    Future<void> Function() command, {
    Future<bool> Function()? verifySave,
    String successMessage = 'Ändringen är sparad.',
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    var saved = false;
    var verified = false;
    try {
      await command();
      saved = true;
    } catch (_) {
      if (verifySave != null) {
        try {
          verified = true;
          saved = await verifySave();
        } catch (_) {
          verified = false;
        }
      }
    } finally {
      if (mounted) {
        _reload();
        setState(() => _busy = false);
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(context).feature(
                saved
                    ? successMessage
                    : verifySave != null && !verified
                    ? 'Kunde inte bekräfta om ändringen sparades. Uppdatera sidan innan du försöker igen.'
                    : 'Ändringen kunde inte sparas. Kontrollera behörighet och försök igen.',
              ),
            ),
          ),
        );
      }
    }
  }

  Future<bool> _publicationWasSaved({
    required String type,
    required String id,
    required String mode,
    required String slug,
    required List<String> fields,
    required String locality,
    required String description,
    required String ageClass,
    required int previousRevision,
  }) async {
    final data = await widget.editorial.getPublicationSelfService(
      widget.clubId,
    );
    final Map<String, dynamic> current;
    if (type == 'club') {
      current = Map<String, dynamic>.from(data['club'] as Map);
    } else {
      final teams = (data['teams'] as List? ?? []).whereType<Map>();
      final match = teams.where((team) => '${team['id']}' == id);
      if (match.isEmpty) return false;
      current = Map<String, dynamic>.from(match.first);
    }
    if ((current['revision'] as num?)?.toInt() != previousRevision + 1 ||
        current['mode'] != mode ||
        current['slug'] != slug ||
        (current['fields'] as List? ?? [])
            .whereType<String>()
            .toSet()
            .difference(fields.toSet())
            .isNotEmpty ||
        fields
            .toSet()
            .difference(
              (current['fields'] as List? ?? []).whereType<String>().toSet(),
            )
            .isNotEmpty) {
      return false;
    }
    if (type == 'club') {
      return '${current['locality'] ?? ''}' == locality &&
          '${current['description'] ?? ''}' == description;
    }
    return '${current['age_class'] ?? ''}' == ageClass;
  }

  Future<void> _configure(
    Map<String, dynamic> item,
    String type, {
    bool clubPublished = false,
  }) async {
    // Never-published pages have no address yet; suggest one from the name.
    final slug = TextEditingController(
      text: '${item['slug'] ?? ''}'.isNotEmpty
          ? '${item['slug']}'
          : _publicationSlug('${item['name'] ?? ''}'),
    );
    bool slugValid() {
      final value = slug.text.trim().toLowerCase();
      return value.length >= 2 &&
          value.length <= 80 &&
          RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(value);
    }

    final locality = TextEditingController(text: '${item['locality'] ?? ''}');
    final description = TextEditingController(
      text: '${item['description'] ?? ''}',
    );
    final ageClass = TextEditingController(text: '${item['age_class'] ?? ''}');
    final currentFields = (item['fields'] as List? ?? [])
        .whereType<String>()
        .toSet();
    var publishLocality = currentFields.contains('locality');
    var publishDescription = currentFields.contains('description');
    var publishAgeClass = currentFields.contains('age_class');
    var mode = '${item['mode'] ?? 'private'}';
    if (type == 'team' && mode == 'listed') mode = 'private';
    if (type == 'team' && !clubPublished) mode = 'private';
    var confirmed = false;
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialog) => AlertDialog(
          title: Text(
            type == 'club' ? 'Klubbens publika sida' : 'Lagets publika sida',
          ),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${item['name'] ?? ''}'),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: mode,
                    decoration: const InputDecoration(labelText: 'Synlighet'),
                    items: [
                      const DropdownMenuItem(
                        value: 'private',
                        child: Text('Privat'),
                      ),
                      if (type == 'club')
                        const DropdownMenuItem(
                          value: 'listed',
                          child: Text('Endast i klubbkatalogen'),
                        ),
                      if (type == 'club' || clubPublished)
                        DropdownMenuItem(
                          value: 'published',
                          child: Text(
                            type == 'club'
                                ? 'Publik sida och klubbkatalog'
                                : 'Publik lagsida',
                          ),
                        ),
                    ],
                    onChanged: (value) => setDialog(() => mode = value ?? mode),
                  ),
                  if (type == 'club')
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        mode == 'published'
                            ? 'Tidigare publicerade lag kan visas igen när klubbsidan återpubliceras, om deras bekräftelse fortfarande gäller. Privata lag förblir privata.'
                            : mode == 'listed'
                            ? 'Klubben visas endast i katalogen. Klubbsidan och alla lagsidor döljs. Lagens publiceringsval sparas.'
                            : 'Klubben döljs från katalogen och klubbsidan och alla lagsidor döljs. Lagens publiceringsval sparas.',
                      ),
                    ),
                  if (type == 'team' && !clubPublished)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Klubbens sida måste publiceras innan laget kan få en publik sida. Be klubbansvarig aktivera klubbsidan först.',
                      ),
                    ),
                  TextField(
                    controller: slug,
                    onChanged: (_) => setDialog(() {}),
                    decoration: InputDecoration(
                      labelText: 'Webbadress (slug)',
                      helperText: 'Små bokstäver a–z, siffror och bindestreck.',
                      errorText: slugValid()
                          ? null
                          : 'Använd 2–80 tecken: a–z, 0–9 och bindestreck, t.ex. f2014.',
                    ),
                  ),
                  if (type == 'club') ...[
                    TextField(
                      controller: locality,
                      onChanged: (_) => setDialog(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Ort (publik)',
                      ),
                    ),
                    TextField(
                      controller: description,
                      onChanged: (_) => setDialog(() {}),
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Presentation (publik)',
                      ),
                    ),
                    CheckboxListTile(
                      value: publishLocality,
                      onChanged: (value) =>
                          setDialog(() => publishLocality = value ?? false),
                      title: const Text('Visa ort publikt'),
                    ),
                    CheckboxListTile(
                      value: publishDescription,
                      onChanged: (value) =>
                          setDialog(() => publishDescription = value ?? false),
                      title: const Text('Visa presentation publikt'),
                    ),
                  ] else ...[
                    TextField(
                      controller: ageClass,
                      onChanged: (_) => setDialog(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Åldersklass (publik)',
                      ),
                    ),
                    CheckboxListTile(
                      value: publishAgeClass,
                      onChanged: (value) =>
                          setDialog(() => publishAgeClass = value ?? false),
                      title: const Text('Visa åldersklass publikt'),
                    ),
                  ],
                  if (mode != 'private')
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Förhandsgranskning',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '${item['name']} · ${mode == 'listed' ? 'katalogpost' : 'publik sida'}',
                            ),
                            Text('/${slug.text.trim().toLowerCase()}'),
                            if (type == 'club' &&
                                publishLocality &&
                                locality.text.trim().isNotEmpty)
                              Text(locality.text.trim()),
                            if (type == 'club' &&
                                publishDescription &&
                                description.text.trim().isNotEmpty)
                              Text(description.text.trim()),
                            if (type == 'team' &&
                                publishAgeClass &&
                                ageClass.text.trim().isNotEmpty)
                              Text(ageClass.text.trim()),
                          ],
                        ),
                      ),
                    ),
                  if (mode != 'private')
                    CheckboxListTile(
                      value: confirmed,
                      onChanged: (value) =>
                          setDialog(() => confirmed = value ?? false),
                      title: const Text(
                        'Jag bekräftar att namn och valda uppgifter får publiceras på webben.',
                      ),
                      subtitle: const Text(
                        'Bekräftelsen gäller i högst ett år och kan återkallas genom att göra sidan privat.',
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Avbryt'),
            ),
            FilledButton(
              onPressed: (mode == 'private' || confirmed) && slugValid()
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              child: const Text('Spara'),
            ),
          ],
        ),
      ),
    );
    if (save == true) {
      final selectedSlug = slug.text.trim().toLowerCase();
      final selectedLocality = locality.text.trim();
      final selectedDescription = description.text.trim();
      final selectedAgeClass = ageClass.text.trim();
      final selectedFields = mode == 'private'
          ? <String>[]
          : type == 'club'
          ? <String>[
              'name',
              if (publishLocality && selectedLocality.isNotEmpty) 'locality',
              if (publishDescription && selectedDescription.isNotEmpty)
                'description',
            ]
          : <String>[
              'name',
              if (publishAgeClass && selectedAgeClass.isNotEmpty) 'age_class',
            ];
      final previousRevision = (item['revision'] as num?)?.toInt() ?? 0;
      await _run(
        () => widget.editorial.configurePublication(
          clubId: widget.clubId,
          aggregateType: type,
          aggregateId: '${item['id']}',
          mode: mode,
          slug: selectedSlug,
          fields: selectedFields,
          locality: selectedLocality,
          description: selectedDescription,
          ageClass: selectedAgeClass,
          expectedRevision: previousRevision,
          idempotencyKey: _newUuid(),
        ),
        verifySave: () => _publicationWasSaved(
          type: type,
          id: '${item['id']}',
          mode: mode,
          slug: selectedSlug,
          fields: selectedFields,
          locality: selectedLocality,
          description: selectedDescription,
          ageClass: selectedAgeClass,
          previousRevision: previousRevision,
        ),
      );
    }
    slug.dispose();
    locality.dispose();
    description.dispose();
    ageClass.dispose();
  }

  Future<void> _request(Map<String, dynamic> team) async {
    final message = TextEditingController();
    final send = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Ansök om lagsida för ${team['name']}'),
        content: TextField(
          controller: message,
          maxLength: 1000,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Meddelande till klubben (valfritt)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Skicka ansökan'),
          ),
        ],
      ),
    );
    if (send == true) {
      await _run(
        () => widget.editorial.requestTeamPublication(
          clubId: widget.clubId,
          teamId: '${team['id']}',
          message: message.text.trim(),
        ),
        successMessage: 'Ansökan är skickad till klubben och väntar på beslut.',
        verifySave: () async {
          final data = await widget.editorial.getPublicationSelfService(
            widget.clubId,
          );
          return (data['teams'] as List? ?? []).whereType<Map>().any(
            (current) =>
                current['id'] == team['id'] &&
                current['request_status'] == 'pending',
          );
        },
      );
    }
    message.dispose();
  }

  Future<void> _decide(Map<String, dynamic> request, bool approve) => _run(
    () => widget.editorial.decideTeamPublication(
      requestId: '${request['id']}',
      approve: approve,
    ),
    successMessage: approve
        ? 'Ansökan är godkänd. Välj lagets synlighet för att publicera sidan.'
        : 'Ansökan är avslagen.',
    verifySave: () async {
      final data = await widget.editorial.getPublicationSelfService(
        widget.clubId,
      );
      return (data['requests'] as List? ?? []).whereType<Map>().any(
        (current) =>
            current['id'] == request['id'] &&
            current['status'] == (approve ? 'approved' : 'rejected'),
      );
    },
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Publika sidor'),
      actions: [
        IconButton(
          onPressed: _reload,
          tooltip: 'Uppdatera',
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<Map<String, dynamic>>(
      future: _data,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Publika sidor kunde inte laddas.'),
                  TextButton(
                    onPressed: _reload,
                    child: const Text('Försök igen'),
                  ),
                ],
              ),
            );
          }
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!;
        final club = Map<String, dynamic>.from(data['club'] as Map);
        final canManage = data['can_manage_club'] == true;
        final teams = (data['teams'] as List? ?? []).whereType<Map>().map(
          (v) => Map<String, dynamic>.from(v),
        );
        final requests = (data['requests'] as List? ?? []).whereType<Map>().map(
          (v) => Map<String, dynamic>.from(v),
        );
        final pendingCount = requests
            .where((r) => r['status'] == 'pending')
            .length;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (canManage && pendingCount > 0)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.pending_actions),
                  title: Text(
                    'Ansökningar som väntar på beslut: $pendingCount',
                  ),
                  subtitle: const Text(
                    'Granska lagens ansökningar längre ned på sidan.',
                  ),
                ),
              ),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('1. Klubbsidan', style: TextStyle(fontSize: 20)),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.public),
                title: Text('${club['name']}'),
                subtitle: Text(
                  '${club['official'] == true ? 'Officiellt verifierad' : 'Inofficiell klubb'} · ${_publicationModeLabel(club['mode'])} · /${club['slug']}',
                ),
                trailing: canManage
                    ? OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => _configure(club, 'club'),
                        child: const Text('Ändra'),
                      )
                    : null,
              ),
            ),
            if (!canManage)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Klubben bestämmer om klubbsidan och vilka lag som får egna sidor.',
                ),
              ),
            const Divider(),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('2. Lagens sidor', style: TextStyle(fontSize: 20)),
            ),
            for (final team in teams)
              ListTile(
                title: Text('${team['name']}'),
                subtitle: Text(
                  'Sida: ${team['mode'] == 'published' && club['mode'] != 'published' ? 'Dold – klubbsidan är inte publicerad (lagets publiceringsval är sparat)' : _publicationModeLabel(team['mode'])} · Ansökan: ${_publicationRequestLabel(team['request_status'])}'
                  '${team['request_status'] == 'approved' && team['mode'] != 'published' ? '\nKlubben har godkänt ansökan. Sidan väntar på att klubben väljer publik synlighet.' : ''}',
                ),
                trailing: canManage
                    ? OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => _configure(
                                team,
                                'team',
                                clubPublished: club['mode'] == 'published',
                              ),
                        child: Text(
                          club['mode'] == 'published'
                              ? 'Välj synlighet'
                              : 'Klubbsidan krävs',
                        ),
                      )
                    : team['can_request'] == true &&
                          team['request_status'] != 'pending' &&
                          team['request_status'] != 'approved' &&
                          team['mode'] != 'published'
                    ? OutlinedButton(
                        onPressed: _busy ? null : () => _request(team),
                        child: const Text('Ansök om lagsida'),
                      )
                    : null,
              ),
            if (canManage && requests.isNotEmpty) ...[
              const Divider(),
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Ansökningar om lagsida',
                  style: TextStyle(fontSize: 20),
                ),
              ),
              for (final request in requests)
                ListTile(
                  title: Text(
                    '${request['team_name']} · ${_publicationRequestLabel(request['status'])}',
                  ),
                  subtitle: Text('${request['message'] ?? ''}'),
                  trailing: request['status'] == 'pending'
                      ? Wrap(
                          spacing: 8,
                          children: [
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _decide(request, false),
                              child: const Text('Avslå'),
                            ),
                            FilledButton(
                              onPressed: _busy
                                  ? null
                                  : () => _decide(request, true),
                              child: const Text('Godkänn'),
                            ),
                          ],
                        )
                      : null,
                ),
            ],
            if (canManage)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Efter godkännande väljer klubben synlighet för laget ovan. Bara publicerade klubbsidor kan ha publika lagsidor.',
                ),
              ),
          ],
        );
      },
    ),
  );
}

/// A web address suggestion from a club or team name: "Örby IF F2014"
/// becomes "orby-if-f2014".
String _publicationSlug(String name) {
  const letters = {'å': 'a', 'ä': 'a', 'ö': 'o', 'é': 'e', 'ü': 'u'};
  final lower = name.toLowerCase().split('').map((c) => letters[c] ?? c).join();
  final slug = lower
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.length > 80
      ? slug.substring(0, 80).replaceAll(RegExp(r'-+$'), '')
      : slug;
}
