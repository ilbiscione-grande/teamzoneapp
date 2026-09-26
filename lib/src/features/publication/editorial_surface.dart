part of '../../app/teamzone_app.dart';

class _EditorialSurface extends StatefulWidget {
  const _EditorialSurface({
    required this.contextValue,
    required this.contexts,
    required this.editorial,
  });

  final TeamZoneContext contextValue;
  final List<TeamZoneContext> contexts;
  final EditorialServices editorial;

  @override
  State<_EditorialSurface> createState() => _EditorialSurfaceState();
}

class _EditorialSurfaceState extends State<_EditorialSurface> {
  late final AsyncDataController<List<EditorialArticle>> _data;
  String? _pendingId;

  @override
  void initState() {
    super.initState();
    _data = AsyncDataController<List<EditorialArticle>>(
      scopeKey: widget.contextValue.clubId,
      loader: () => widget.editorial.listArticles(widget.contextValue.clubId),
      isEmpty: (items) => items.isEmpty,
    )..addListener(_changed);
    unawaited(_data.load());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _data
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  Future<void> _edit([EditorialArticle? article]) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _EditorialEditor(
          clubId: widget.contextValue.clubId,
          teams: {
            for (final value in widget.contexts)
              if (value.clubId == widget.contextValue.clubId &&
                  value.teamId != null)
                value.teamId!: value.teamName ?? value.clubName,
          },
          editorial: widget.editorial,
          article: article,
        ),
      ),
    );
    if (changed == true) await _data.refresh();
  }

  Future<void> _transition(EditorialArticle article, String state) async {
    if (state == 'published' || state == 'scheduled') {
      try {
        final domain = await widget.editorial.getDomainManagement(
          widget.contextValue.clubId,
        );
        if (!mounted) return;
        if (!domain.clubPublished) {
          _showEditorialPublicationPrerequisite(context);
          return;
        }
      } catch (_) {
        if (!mounted) return;
        _showEditorialPublicationFailure(context);
        return;
      }
    }
    DateTime? publishAt;
    if (state == 'scheduled') {
      final date = await showDatePicker(
        context: context,
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 366)),
        initialDate: DateTime.now().add(const Duration(days: 1)),
      );
      if (date == null || !mounted) return;
      final time = await showTimePicker(
        context: context,
        initialTime: const TimeOfDay(hour: 8, minute: 0),
      );
      if (time == null) return;
      publishAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    }
    setState(() => _pendingId = article.id);
    try {
      await widget.editorial.transition(
        articleId: article.id,
        state: state,
        publishAt: publishAt,
        expectedRevision: article.revision,
        idempotencyKey: _newUuid(),
      );
      await _data.refresh();
    } catch (_) {
      if (mounted) {
        _showEditorialPublicationFailure(context);
      }
    } finally {
      if (mounted) setState(() => _pendingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    if (!widget.contextValue.can('publication.manage')) {
      return Scaffold(
        appBar: AppBar(title: Text(strings.feature('Nyhetsredaktion'))),
        body: _StateCard(
          icon: Icons.lock_outline,
          title: strings.feature('Redaktionen är inte tillgänglig'),
          message: strings.feature(
            'Ditt aktuella klubbmandat saknar publiceringsbehörighet.',
          ),
        ),
      );
    }
    return Scaffold(
      floatingActionButtonLocation: _assistantUsesFab(context)
          ? _aboveAssistantFabLocation
          : null,
      appBar: AppBar(
        title: Text(strings.feature('Nyhetsredaktion')),
        actions: [
          IconButton(
            tooltip: strings.feature('Event och partners'),
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => _PublicationManagementSurface(
                  clubId: widget.contextValue.clubId,
                  editorial: widget.editorial,
                ),
              ),
            ),
            icon: const Icon(Icons.public),
          ),
          IconButton(
            tooltip: strings.feature('Uppdatera'),
            onPressed: _data.refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _edit,
        tooltip: strings.feature('Ny artikel'),
        child: const Icon(Icons.add),
      ),
      body: AnimatedBuilder(
        animation: _data,
        builder: (context, _) {
          final state = _data.state;
          if (state.phase == AsyncDataPhase.loading) {
            return AppLoadingIndicator(
              label: strings.feature('Laddar artiklar'),
            );
          }
          if (state.phase == AsyncDataPhase.failed) {
            return _StateCard(
              icon: Icons.cloud_off,
              title: strings.feature('Artiklarna kunde inte laddas'),
              message: strings.safeError,
              action: FilledButton(
                onPressed: _data.load,
                child: Text(strings.retry),
              ),
            );
          }
          final articles = state.data ?? const [];
          if (articles.isEmpty) {
            return _StateCard(
              icon: Icons.newspaper_outlined,
              title: strings.feature('Inga artiklar ännu'),
              message: strings.feature(
                'Skapa ett utkast och välj sedan när det ska publiceras.',
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _data.refresh,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: articles.length,
              separatorBuilder: (_, _) => const Divider(),
              itemBuilder: (context, index) {
                final article = articles[index];
                final pending = _pendingId == article.id;
                return ListTile(
                  leading: Icon(_articleIcon(article.state)),
                  title: Text(article.title),
                  subtitle: Text(
                    '${strings.domainValue(article.state)} · /${article.slug}\n'
                    '${[if (article.publishToClub) strings.feature('Klubbens publika sida'), for (final teamId in article.teamIds) widget.contexts.where((value) => value.teamId == teamId).map((value) => value.teamName).firstOrNull ?? strings.feature('Vald publik lagsida')].join(' · ')}',
                  ),
                  isThreeLine: true,
                  onTap: pending || article.state == 'published'
                      ? null
                      : () => _edit(article),
                  trailing: pending
                      ? const SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator(),
                        )
                      : PopupMenuButton<String>(
                          tooltip: strings.feature('Artikelåtgärder'),
                          onSelected: (value) => value == 'edit'
                              ? _edit(article)
                              : _transition(article, value),
                          itemBuilder: (_) => [
                            if (article.state != 'published')
                              PopupMenuItem(
                                value: 'edit',
                                child: Text(strings.feature('Redigera')),
                              ),
                            if (article.state != 'published')
                              PopupMenuItem(
                                value: 'scheduled',
                                child: Text(strings.feature('Schemalägg')),
                              ),
                            if (article.state != 'published')
                              PopupMenuItem(
                                value: 'published',
                                child: Text(strings.feature('Publicera nu')),
                              ),
                            if (article.state == 'published')
                              PopupMenuItem(
                                value: 'unpublished',
                                child: Text(strings.feature('Avpublicera')),
                              ),
                          ],
                        ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

IconData _articleIcon(String state) => switch (state) {
  'published' => Icons.public,
  'scheduled' => Icons.schedule,
  'unpublished' => Icons.public_off,
  _ => Icons.edit_note,
};

void _showEditorialPublicationPrerequisite(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        AppStrings.of(context).feature(
          'Klubbsidan är inte publicerad. Aktivera klubbens publika sida innan du publicerar nyheter.',
        ),
      ),
    ),
  );
}

void _showEditorialPublicationFailure(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        AppStrings.of(context).feature(
          'Publiceringen kunde inte genomföras. Ladda om och försök igen.',
        ),
      ),
    ),
  );
}

class _EditorialEditor extends StatefulWidget {
  const _EditorialEditor({
    required this.clubId,
    required this.teams,
    required this.editorial,
    this.article,
  });
  final String clubId;
  final Map<String, String> teams;
  final EditorialServices editorial;
  final EditorialArticle? article;
  @override
  State<_EditorialEditor> createState() => _EditorialEditorState();
}

class _EditorialEditorState extends State<_EditorialEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title = TextEditingController(
    text: widget.article?.title,
  );
  late final TextEditingController _slug = TextEditingController(
    text: widget.article?.slug,
  );
  late final TextEditingController _summary = TextEditingController(
    text: widget.article?.summary,
  );
  late final TextEditingController _author = TextEditingController(
    text: widget.article?.authorLabel,
  );
  late final TextEditingController _body = TextEditingController(
    text: widget.article?.blocks.map((block) => block.text).join('\n\n'),
  );
  late bool _club = widget.article?.publishToClub ?? true;
  late final Set<String> _teams = {...?widget.article?.teamIds};
  late bool _automaticSlug = widget.article == null;
  bool _saving = false;

  bool get _hasUnsavedChanges {
    final article = widget.article;
    if (article == null) return true;
    return _title.text.trim() != article.title ||
        _slug.text.trim().toLowerCase() != article.slug ||
        _summary.text.trim() != (article.summary ?? '') ||
        _author.text.trim() != (article.authorLabel ?? '') ||
        _body.text.trim() !=
            article.blocks.map((block) => block.text).join('\n\n').trim() ||
        _club != article.publishToClub ||
        _teams.length != article.teamIds.length ||
        !_teams.containsAll(article.teamIds);
  }

  @override
  void initState() {
    super.initState();
    _title.addListener(_updateSuggestedSlug);
  }

  void _updateSuggestedSlug() {
    if (!_automaticSlug) return;
    final suggestion = _suggestArticleSlug(_title.text);
    if (_slug.text == suggestion) return;
    _slug.value = TextEditingValue(
      text: suggestion,
      selection: TextSelection.collapsed(offset: suggestion.length),
    );
  }

  void _preview() {
    FocusScope.of(context).unfocus();
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _EditorialDraftPreview(
          title: _title.text.trim(),
          summary: _summary.text.trim(),
          body: _body.text.trim(),
          author: _author.text.trim(),
          slug: _slug.text.trim(),
          publishToClub: _club,
          teams: [
            for (final entry in widget.teams.entries)
              if (_teams.contains(entry.key)) entry.value,
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _title.removeListener(_updateSuggestedSlug);
    _title.dispose();
    _slug.dispose();
    _summary.dispose();
    _author.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || (!_club && _teams.isEmpty)) {
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.editorial.saveArticle(
        EditorialSaveInput(
          clubId: widget.clubId,
          articleId: widget.article?.id,
          slug: _slug.text.trim().toLowerCase(),
          title: _title.text.trim(),
          summary: _summary.text.trim().isEmpty ? null : _summary.text.trim(),
          authorLabel: _author.text.trim().isEmpty ? null : _author.text.trim(),
          blocks: [EditorialBlock(type: 'paragraph', text: _body.text.trim())],
          publishToClub: _club,
          teamIds: _teams,
          expectedRevision: widget.article?.revision,
          idempotencyKey: _newUuid(),
        ),
      );
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(context).feature(
                'Utkastet kunde inte sparas. Försök igen eller kontakta support.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _publish() async {
    final article = widget.article;
    if (article == null || _saving) return;
    if (_hasUnsavedChanges) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.of(
              context,
            ).feature('Spara ändringarna i utkastet innan du publicerar.'),
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final domain = await widget.editorial.getDomainManagement(widget.clubId);
      if (!mounted) return;
      if (!domain.clubPublished) {
        _showEditorialPublicationPrerequisite(context);
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            AppStrings.of(dialogContext).feature('Publicera nyheten?'),
          ),
          content: Text(article.title),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(AppStrings.of(dialogContext).cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(AppStrings.of(dialogContext).feature('Publicera nu')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await widget.editorial.transition(
        articleId: article.id,
        state: 'published',
        expectedRevision: article.revision,
        idempotencyKey: _newUuid(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) _showEditorialPublicationFailure(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          strings.feature(
            widget.article == null ? 'Ny artikel' : 'Redigera artikel',
          ),
        ),
        actions: [
          IconButton(
            tooltip: strings.feature('Förhandsgranska utkast'),
            onPressed: _preview,
            icon: const Icon(Icons.preview_outlined),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _title,
              decoration: InputDecoration(labelText: strings.feature('Rubrik')),
              maxLength: 160,
              validator: _required,
            ),
            TextFormField(
              controller: _slug,
              decoration: InputDecoration(
                labelText: strings.feature('Adressnamn'),
                helperText: strings.feature(
                  'Föreslås från rubriken. Du kan ändra adressen.',
                ),
                suffixIcon: IconButton(
                  tooltip: strings.feature('Föreslå adress från rubriken'),
                  onPressed: () {
                    setState(() => _automaticSlug = true);
                    _updateSuggestedSlug();
                  },
                  icon: const Icon(Icons.auto_fix_high_outlined),
                ),
              ),
              maxLength: 100,
              onChanged: (_) => _automaticSlug = false,
              validator: _slugValidator,
            ),
            TextFormField(
              controller: _summary,
              decoration: InputDecoration(
                labelText: strings.feature('Ingress'),
              ),
              maxLength: 1000,
              maxLines: 3,
            ),
            TextFormField(
              controller: _body,
              decoration: InputDecoration(
                labelText: strings.feature('Artikeltext'),
              ),
              maxLength: 4000,
              minLines: 8,
              maxLines: 16,
              validator: _required,
            ),
            TextFormField(
              controller: _author,
              decoration: InputDecoration(
                labelText: strings.feature('Avsändare'),
              ),
              maxLength: 120,
            ),
            SwitchListTile(
              value: _club,
              onChanged: (value) => setState(() => _club = value),
              title: Text(strings.feature('Visa på klubbens publika sida')),
              subtitle: Text(
                strings.feature('Nyheten kan läsas utan inloggning.'),
              ),
            ),
            for (final team in widget.teams.entries)
              CheckboxListTile(
                value: _teams.contains(team.key),
                onChanged: (value) => setState(
                  () => value == true
                      ? _teams.add(team.key)
                      : _teams.remove(team.key),
                ),
                title: Text(team.value),
                subtitle: Text(
                  strings.feature(
                    'Visa på lagets publika sida och i följarnas flöde',
                  ),
                ),
              ),
            if (!_club && _teams.isEmpty)
              Text(
                strings.feature('Välj minst en publik klubb- eller lagsida.'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _preview,
              icon: const Icon(Icons.preview_outlined),
              label: Text(strings.feature('Förhandsgranska utkast')),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(),
                    )
                  : const Icon(Icons.save),
              label: Text(strings.feature('Spara utkast')),
            ),
            if (widget.article != null &&
                widget.article!.state != 'published') ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _saving ? null : _publish,
                icon: const Icon(Icons.public),
                label: Text(strings.feature('Publicera nu')),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              strings.feature(
                'Bilder är inte aktiverade ännu. Endast strukturerad text publiceras.',
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String? _required(String? value) => value == null || value.trim().isEmpty
      ? AppStrings.of(context).feature('Fältet krävs')
      : null;
  String? _slugValidator(String? value) =>
      RegExp(
            r'^[a-z0-9]+(?:-[a-z0-9]+)*$',
          ).hasMatch(value?.trim().toLowerCase() ?? '') &&
          (value?.trim().length ?? 0) >= 2
      ? null
      : AppStrings.of(context).feature(
          'Använd 2–100 tecken: små bokstäver, siffror och bindestreck.',
        );
}

String _suggestArticleSlug(String title) {
  final folded = title.toLowerCase().trim().replaceAllMapped(
    RegExp(r'[åäöéèü]'),
    (match) => switch (match.group(0)) {
      'å' || 'ä' => 'a',
      'ö' => 'o',
      'é' || 'è' => 'e',
      'ü' => 'u',
      _ => '',
    },
  );
  final slug = folded
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (slug.length <= 100) return slug;
  return slug.substring(0, 100).replaceAll(RegExp(r'-+$'), '');
}

class _EditorialDraftPreview extends StatelessWidget {
  const _EditorialDraftPreview({
    required this.title,
    required this.summary,
    required this.body,
    required this.author,
    required this.slug,
    required this.publishToClub,
    required this.teams,
  });

  final String title, summary, body, author, slug;
  final bool publishToClub;
  final List<String> teams;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final paragraphs = body
        .split(RegExp(r'\n\s*\n'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty);
    return Scaffold(
      appBar: AppBar(title: Text(strings.feature('Förhandsgranska utkast'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    strings.feature(
                      'Endast förhandsgranskning i appen. Inget har sparats eller publicerats.',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                title.isEmpty ? strings.feature('Rubrik saknas') : title,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              if (summary.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(summary, style: Theme.of(context).textTheme.titleMedium),
              ],
              if (author.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(author, style: Theme.of(context).textTheme.bodySmall),
              ],
              const SizedBox(height: 24),
              for (final paragraph in paragraphs) ...[
                Text(paragraph, style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 16),
              ],
              if (body.isEmpty) Text(strings.feature('Artikeltext saknas')),
              const Divider(height: 40),
              Text(
                strings.feature('Nyheten visas på dessa publika sidor'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (publishToClub) Text(strings.feature('Klubbens publika sida')),
              for (final team in teams) Text(team),
              if (!publishToClub && teams.isEmpty)
                Text(strings.feature('Ingen kanal vald')),
              const SizedBox(height: 12),
              Text(
                '${strings.feature('Adressnamn')}: ${slug.isEmpty ? strings.feature('Saknas') : slug}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
