part of '../../app/teamzone_app.dart';

/// Saves the session as a pass in Tacticsboard's library, shared with the
/// club and by a link if the leader likes; then shows the link to send.
class _TrainingPassSaveDialog extends StatefulWidget {
  const _TrainingPassSaveDialog({
    required this.services,
    required this.eventId,
    required this.title,
  });
  final TrainingPassServices services;
  final String eventId;
  final String title;

  @override
  State<_TrainingPassSaveDialog> createState() =>
      _TrainingPassSaveDialogState();
}

class _TrainingPassSaveDialogState extends State<_TrainingPassSaveDialog> {
  late final _title = TextEditingController(text: widget.title);
  late final Future<TrainingPassState?> _loaded = widget.services
      .passState(widget.eventId)
      .then((state) {
        if (state != null && mounted) {
          setState(() {
            _title.text = state.title;
            _club = state.clubName != null;
            _link = state.link != null;
          });
        }
        return state;
      });
  bool _club = true, _link = false, _busy = false;
  TrainingPassState? _saved;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final strings = AppStrings.of(context);
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = strings.feature('Ange ett namn på passet.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final before = await _loaded.catchError((Object _) => null);
      var saved = await widget.services.savePass(
        eventId: widget.eventId,
        title: title,
        club: _club,
        link: _link,
      );
      if (!_link && before?.link != null) {
        saved = await widget.services.deleteLink(widget.eventId) ?? saved;
      }
      if (mounted) setState(() => _saved = saved);
    } catch (error) {
      AppErrors.caught('training_pass._save', error);
      if (mounted) {
        setState(
          () => _error = strings.feature('Passet kunde inte sparas som pass.'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopLink() async {
    setState(() => _busy = true);
    try {
      final state = await widget.services.deleteLink(widget.eventId);
      if (mounted) setState(() => _saved = state);
    } catch (error) {
      AppErrors.caught('training_pass._stopLink', error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final saved = _saved;
    return AlertDialog(
      key: const Key('training-pass-dialog'),
      title: Text(strings.feature('Spara och dela som pass')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: saved == null ? _form(context) : _result(context, saved),
        ),
      ),
      actions: saved == null
          ? [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(strings.feature('Avbryt')),
              ),
              FilledButton(
                key: const Key('training-pass-confirm'),
                onPressed: _busy ? null : _save,
                child: Text(strings.feature(_busy ? 'Sparar…' : 'Spara')),
              ),
            ]
          : [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: Text(strings.feature('Klar')),
              ),
            ],
    );
  }

  Widget _form(BuildContext context) {
    final strings = AppStrings.of(context);
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return FutureBuilder<TrainingPassState?>(
      future: _loaded,
      builder: (context, snapshot) {
        final state = snapshot.data;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.feature(
                'Passet sparas i ditt bibliotek i Tacticsboard, med en tavla per övning att rita på. Spelarna följer inte med.',
              ),
            ),
            if (state?.updatedAt case final updatedAt?) ...[
              const SizedBox(height: 8),
              Text(
                strings.formatFeature(
                  'Sparat senast {date}. Sparar du igen uppdateras passet.',
                  {
                    'date': MaterialLocalizations.of(
                      context,
                    ).formatShortDate(updatedAt.toLocal()),
                  },
                ),
                style: muted,
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              key: const Key('training-pass-title'),
              controller: _title,
              maxLength: 120,
              decoration: InputDecoration(
                labelText: strings.feature('Namn på passet'),
                errorText: _error,
              ),
            ),
            SwitchListTile(
              key: const Key('training-pass-club'),
              contentPadding: EdgeInsets.zero,
              value: _club,
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _club = value),
              title: Text(strings.feature('Dela med klubben')),
              subtitle: Text(
                strings.feature(
                  'Klubbens ledare hittar passet i klubbens bibliotek.',
                ),
              ),
            ),
            SwitchListTile(
              key: const Key('training-pass-link'),
              contentPadding: EdgeInsets.zero,
              value: _link,
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _link = value),
              title: Text(strings.feature('Dela med en länk')),
              subtitle: Text(
                strings.feature(
                  'Ledare i andra klubbar som har träningsmodulen kan öppna länken och spara en kopia.',
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _result(BuildContext context, TrainingPassState saved) {
    final strings = AppStrings.of(context);
    final link = saved.link == null
        ? null
        : TrainingPassState.linkUri(saved.link!).toString();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.check_circle_outline),
          title: Text(strings.feature('Sparat i ditt bibliotek')),
          subtitle: Text(saved.title),
        ),
        if (saved.clubName case final club?)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.groups_outlined),
            title: Text(
              strings.formatFeature('Delat med {club}', {'club': club}),
            ),
          ),
        if (link != null) ...[
          const SizedBox(height: 8),
          Text(strings.feature('Länk att skicka')),
          const SizedBox(height: 4),
          SelectableText(
            link,
            key: const Key('training-pass-link-text'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.tonalIcon(
                key: const Key('training-pass-copy-link'),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await Clipboard.setData(ClipboardData(text: link));
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(strings.feature('Länken är kopierad.')),
                    ),
                  );
                },
                icon: const Icon(Icons.copy, size: 18),
                label: Text(strings.feature('Kopiera länk')),
              ),
              TextButton(
                key: const Key('training-pass-stop-link'),
                onPressed: _busy ? null : _stopLink,
                child: Text(strings.feature('Sluta dela länken')),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// A short line about a pass: who wrote it, its exercises and minutes.
String _trainingPassLine(BuildContext context, TrainingPass pass) {
  final strings = AppStrings.of(context);
  return [
    ?pass.author,
    if (pass.theme.isNotEmpty) pass.theme,
    if (!pass.single)
      strings.formatFeature('{count} övningar', {
        'count': pass.exercises.length,
      }),
    '${pass.minutes} min',
  ].join('  •  ');
}

/// A pass's exercises in order, each with its part and minutes. With
/// [onBoard], an exercise's board is picked by tapping it.
class _TrainingPassExercises extends StatelessWidget {
  const _TrainingPassExercises({required this.pass, this.onBoard});
  final TrainingPass pass;
  final ValueChanged<TrainingBoardLink>? onBoard;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, block) in pass.exercises.indexed)
          ListTile(
            key: ValueKey('training-board-$index'),
            dense: true,
            enabled: onBoard == null || block.board != null,
            onTap: onBoard == null || block.board == null
                ? null
                : () => onBoard!(block.board!),
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              radius: 14,
              backgroundColor: _trainingPartColors(block.part).accent,
              child: Icon(
                _trainingPartIcon(block.part),
                size: 16,
                color: Colors.white,
              ),
            ),
            title: Text(block.title),
            subtitle: Text(
              [
                strings.feature(block.part.label),
                if (block.organisation.isNotEmpty) block.organisation,
              ].join('  •  '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: muted,
            ),
            trailing: onBoard == null
                ? Text('${block.minutes} min', style: muted)
                : const Icon(Icons.link),
          ),
      ],
    );
  }
}

/// Picks a pass or an exercise from your library, your clubs' or
/// TeamZone's, to take into the session; with [board], one of its boards to
/// link to an exercise.
class _TrainingPassPicker extends StatefulWidget {
  const _TrainingPassPicker({required this.services, this.board = false});
  final TrainingPassServices services;
  final bool board;

  @override
  State<_TrainingPassPicker> createState() => _TrainingPassPickerState();
}

class _TrainingPassPickerState extends State<_TrainingPassPicker> {
  final _search = TextEditingController();
  TrainingPassSource _source = TrainingPassSource.mine;
  late Future<List<TrainingPass>> _passes = _load();
  TrainingPass? _chosen;
  Timer? _debounce;

  Future<List<TrainingPass>> _load() =>
      widget.services.listPasses(_source, search: _search.text.trim());

  void _reload() => setState(() => _passes = _load());

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chosen = _chosen;
    return Dialog(
      key: const Key('training-pass-picker'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: chosen == null ? _list(context) : _detail(context, chosen),
        ),
      ),
    );
  }

  Widget _list(BuildContext context) {
    final strings = AppStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                strings.feature(
                  widget.board ? 'Länka en tavla' : 'Från biblioteket',
                ),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SegmentedButton<TrainingPassSource>(
          showSelectedIcon: false,
          segments: [
            for (final source in TrainingPassSource.values)
              if (source != TrainingPassSource.link)
                ButtonSegment(
                  value: source,
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(strings.feature(source.label)),
                  ),
                ),
          ],
          selected: {_source},
          onSelectionChanged: (value) {
            _source = value.first;
            _reload();
          },
        ),
        const SizedBox(height: 10),
        TextField(
          key: const Key('training-pass-search'),
          controller: _search,
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search),
            hintText: strings.feature('Sök på namn eller tema'),
          ),
          onChanged: (_) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 350), _reload);
          },
        ),
        const SizedBox(height: 8),
        Flexible(
          child: FutureBuilder<List<TrainingPass>>(
            future: _passes,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Text(strings.feature('Biblioteket kunde inte läsas.')),
                );
              }
              final passes = snapshot.data;
              if (passes == null) {
                return const Center(child: CircularProgressIndicator());
              }
              if (passes.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    strings.feature(
                      _source == TrainingPassSource.mine
                          ? 'Inga pass än. Spara ett träningspass som pass, eller skapa ett i Tacticsboard.'
                          : 'Inga pass hittades.',
                    ),
                    textAlign: TextAlign.center,
                  ),
                );
              }
              return ListView.separated(
                shrinkWrap: true,
                itemCount: passes.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final pass = passes[index];
                  return ListTile(
                    key: ValueKey('training-pass-${pass.id}'),
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      pass.single
                          ? Icons.sports_soccer_outlined
                          : Icons.view_list_outlined,
                    ),
                    title: Text(pass.title),
                    subtitle: Text(
                      _trainingPassLine(context, pass),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => setState(() => _chosen = pass),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _detail(BuildContext context, TrainingPass pass) {
    final strings = AppStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () => setState(() => _chosen = null),
              icon: const Icon(Icons.arrow_back),
            ),
            Expanded(
              child: Text(
                pass.title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ],
        ),
        Text(_trainingPassLine(context, pass)),
        if (pass.goal.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(pass.goal, maxLines: 3, overflow: TextOverflow.ellipsis),
        ],
        const SizedBox(height: 8),
        if (widget.board) ...[
          const SizedBox(height: 8),
          Text(strings.feature('Välj övningen vars tavla du vill länka.')),
        ],
        Flexible(
          child: SingleChildScrollView(
            child: _TrainingPassExercises(
              pass: pass,
              onBoard: widget.board
                  ? (board) => Navigator.pop(context, board)
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (!widget.board)
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: const Key('training-pass-take'),
              onPressed: pass.exercises.isEmpty
                  ? null
                  : () => Navigator.pop(context, pass),
              child: Text(
                pass.single
                    ? strings.feature('Lägg in övningen')
                    : strings.formatFeature('Lägg in {count} övningar', {
                        'count': pass.exercises.length,
                      }),
              ),
            ),
          ),
      ],
    );
  }
}

/// A pass someone sent by link: what it holds, and a copy into your own
/// library to take into a training later.
class _TrainingPassLinkPage extends StatefulWidget {
  const _TrainingPassLinkPage({required this.services, required this.token});
  final TrainingServices services;
  final String token;

  @override
  State<_TrainingPassLinkPage> createState() => _TrainingPassLinkPageState();
}

class _TrainingPassLinkPageState extends State<_TrainingPassLinkPage> {
  TrainingPassServices? get _passes =>
      widget.services is TrainingPassSourceServices
      ? (widget.services as TrainingPassSourceServices).passes
      : null;
  late final Future<TrainingPass> _pass =
      _passes?.openLink(widget.token) ??
      Future.error(StateError('Training passes are not configured.'));
  bool _busy = false, _copied = false;

  Future<void> _copy() async {
    final strings = AppStrings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await _passes!.copyLink(widget.token);
      if (mounted) setState(() => _copied = true);
    } catch (error) {
      AppErrors.caught('training_pass._copy', error);
      messenger.showSnackBar(
        SnackBar(content: Text(strings.feature('Passet kunde inte sparas.'))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(strings.feature('Delat pass'))),
      body: FutureBuilder<TrainingPass>(
        future: _pass,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  strings.feature(
                    'Länken fungerar inte. Den kan vara borttagen, eller så leder du inget lag i en klubb med träningsmodulen.',
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final pass = snapshot.data;
          if (pass == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                key: const Key('training-pass-link-page'),
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    pass.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(_trainingPassLine(context, pass)),
                  if (pass.goal.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(pass.goal),
                  ],
                  const SizedBox(height: 12),
                  _ProgramPanel(child: _TrainingPassExercises(pass: pass)),
                  const SizedBox(height: 16),
                  if (_copied)
                    ListTile(
                      key: const Key('training-pass-copied'),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.check_circle_outline),
                      title: Text(strings.feature('Sparat i ditt bibliotek')),
                      subtitle: Text(
                        strings.feature(
                          'Lägg in det i en träning med Från biblioteket → Mina pass, eller rita på tavlorna i Tacticsboard.',
                        ),
                      ),
                    )
                  else
                    FilledButton.icon(
                      key: const Key('training-pass-copy'),
                      onPressed: _busy ? null : _copy,
                      icon: const Icon(Icons.library_add_outlined),
                      label: Text(strings.feature('Spara i mitt bibliotek')),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
