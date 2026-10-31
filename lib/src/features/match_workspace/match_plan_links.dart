part of '../../app/teamzone_app.dart';

/// The match plan's links: opened in the browser; for those who edit the
/// plan also added, shown to the players or not, and removed.
class _MatchPlanLinks extends StatelessWidget {
  const _MatchPlanLinks({
    required this.eventId,
    required this.services,
    required this.links,
    required this.canEdit,
    required this.onChanged,
  });
  final String eventId;
  final MatchPlanServices services;
  final List<MatchPlanLink> links;
  final bool canEdit;
  final Future<void> Function() onChanged;

  Future<void> _add(BuildContext context) async {
    final strings = AppStrings.of(context);
    final title = TextEditingController();
    final url = TextEditingController(text: 'https://');
    var visible = false;
    final added = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(strings.feature('Lägg till länk')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                maxLength: 120,
                decoration: InputDecoration(
                  labelText: strings.feature('Rubrik'),
                ),
              ),
              TextField(
                controller: url,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: strings.feature('Adress'),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: visible,
                onChanged: (value) => setState(() => visible = value),
                title: Text(strings.feature('Visa för spelarna')),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(strings.feature('Avbryt')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(strings.feature('Lägg till')),
            ),
          ],
        ),
      ),
    );
    if (added != true || !context.mounted) return;
    try {
      await services.addLink(
        eventId: eventId,
        title: title.text.trim(),
        url: url.text.trim(),
        visible: visible,
      );
      await onChanged();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            strings.feature(
              'Länken kunde inte läggas till. Den ska börja med https://.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _change(
    BuildContext context,
    MatchPlanLink link,
    bool? visible,
  ) async {
    try {
      await services.changeLink(link.id, visible: visible);
      await onChanged();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.of(context).feature('Länken kunde inte ändras.'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    if (!canEdit && links.isEmpty) return const SizedBox.shrink();
    return Card(
      key: const Key('match-plan-links'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    strings.feature('Länkar'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (canEdit)
                  TextButton.icon(
                    key: const Key('match-plan-add-link'),
                    onPressed: () => _add(context),
                    icon: const Icon(Icons.add_link),
                    label: Text(strings.feature('Lägg till')),
                  ),
              ],
            ),
            if (links.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  strings.feature(
                    'T.ex. video på motståndaren eller ett dokument om fasta situationer.',
                  ),
                ),
              ),
            for (final link in links)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.link),
                title: Text(link.title),
                subtitle: canEdit
                    ? Text(
                        strings.feature(
                          link.visible ? 'Visas för spelarna' : 'Bara ledarna',
                        ),
                      )
                    : null,
                onTap: () => launchUrl(
                  Uri.parse(link.url),
                  mode: LaunchMode.externalApplication,
                ),
                trailing: canEdit
                    ? PopupMenuButton<String>(
                        onSelected: (choice) => _change(
                          context,
                          link,
                          choice == 'remove' ? null : choice == 'show',
                        ),
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: link.visible ? 'hide' : 'show',
                            child: Text(
                              strings.feature(
                                link.visible
                                    ? 'Dölj för spelarna'
                                    : 'Visa för spelarna',
                              ),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'remove',
                            child: Text(strings.feature('Ta bort')),
                          ),
                        ],
                      )
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}

/// The boards' own copy in Swedish or English, kept here with them.
String _boardCopy(AppStrings strings, String swedish, String english) =>
    strings.isSwedish ? swedish : english;

/// Opens a board on the plan in the shared view, through a short link of
/// the asker's own; says so when it cannot.
Future<void> _openPlanBoard(
  BuildContext context,
  MatchPlanServices services,
  MatchPlanBoard board,
) async {
  try {
    final path = await services.openBoard(board.id);
    await launchUrl(
      Uri.parse('$webtoolsOrigin$path'),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _boardCopy(
            AppStrings.of(context),
            'Tavlan kunde inte öppnas.',
            'The board could not be opened.',
          ),
        ),
      ),
    );
  }
}

/// The match plan's boards from Tacticsboard: opened in the shared view;
/// for those who edit the plan also added from their own and the team's
/// projects, shown to the players or not, and removed.
class _MatchPlanBoards extends StatelessWidget {
  const _MatchPlanBoards({
    required this.eventId,
    required this.services,
    required this.boards,
    required this.canEdit,
    required this.onChanged,
  });
  final String eventId;
  final MatchPlanServices services;
  final List<MatchPlanBoard> boards;
  final bool canEdit;
  final Future<void> Function() onChanged;

  Future<void> _add(BuildContext context) async {
    final strings = AppStrings.of(context);
    List<TacticsBoardChoice> choices;
    try {
      choices = await services.listBoardChoices(eventId);
    } catch (_) {
      choices = const [];
    }
    if (!context.mounted) return;
    if (choices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _boardCopy(
              strings,
              'Inga tavlor att välja. Gör en i Tacticsboard, för laget eller dig själv.',
              'No boards to choose from. Make one in Tacticsboard, for the team or yourself.',
            ),
          ),
        ),
      );
      return;
    }
    var project = choices.first;
    String? board;
    var visible = false;
    final added = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(_boardCopy(strings, 'Lägg till tavla', 'Add board')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                key: const Key('match-plan-board-project'),
                initialValue: project.projectId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: _boardCopy(strings, 'Projekt', 'Project'),
                ),
                items: [
                  for (final choice in choices)
                    DropdownMenuItem(
                      value: choice.projectId,
                      child: Text(
                        [
                          choice.name,
                          if (choice.teamName != null) choice.teamName!,
                        ].join(' · '),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) => setState(() {
                  project = choices.firstWhere(
                    (choice) => choice.projectId == value,
                  );
                  board = null;
                }),
              ),
              DropdownButtonFormField<String?>(
                key: ValueKey('match-plan-board-${project.projectId}'),
                initialValue: board,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: _boardCopy(strings, 'Tavla', 'Board'),
                ),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(
                      _boardCopy(
                        strings,
                        'Alla tavlor i projektet',
                        'All boards in the project',
                      ),
                    ),
                  ),
                  for (final item in project.boards)
                    DropdownMenuItem<String?>(
                      value: item.id,
                      child: Text(
                        item.name.isEmpty
                            ? _boardCopy(strings, 'Tavla', 'Board')
                            : item.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => board = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: visible,
                onChanged: (value) => setState(() => visible = value),
                title: Text(strings.feature('Visa för spelarna')),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(strings.feature('Avbryt')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(strings.feature('Lägg till')),
            ),
          ],
        ),
      ),
    );
    if (added != true || !context.mounted) return;
    try {
      await services.addBoard(
        eventId: eventId,
        projectId: project.projectId,
        boardId: board,
        visible: visible,
      );
      await onChanged();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _boardCopy(
              strings,
              'Tavlan kunde inte läggas till.',
              'The board could not be added.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _change(
    BuildContext context,
    MatchPlanBoard board,
    bool? visible,
  ) async {
    try {
      await services.changeLink(board.id, visible: visible);
      await onChanged();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _boardCopy(
              AppStrings.of(context),
              'Tavlan kunde inte ändras.',
              'The board could not be changed.',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    if (!canEdit && boards.isEmpty) return const SizedBox.shrink();
    return Card(
      key: const Key('match-plan-boards'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _boardCopy(strings, 'Tavlor', 'Boards'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (canEdit)
                  TextButton.icon(
                    key: const Key('match-plan-add-board'),
                    onPressed: () => _add(context),
                    icon: const Icon(Icons.add),
                    label: Text(strings.feature('Lägg till')),
                  ),
              ],
            ),
            if (boards.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _boardCopy(
                    strings,
                    'Tavlor från Tacticsboard som spelarna kan spela upp i mobilen.',
                    'Boards from Tacticsboard the players can play on their phones.',
                  ),
                ),
              ),
            for (final board in boards)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: TacticsBoardThumbnail(preview: board.preview),
                title: Text(board.title),
                subtitle: canEdit
                    ? Text(
                        strings.feature(
                          board.visible ? 'Visas för spelarna' : 'Bara ledarna',
                        ),
                      )
                    : null,
                onTap: () => _openPlanBoard(context, services, board),
                trailing: canEdit
                    ? PopupMenuButton<String>(
                        onSelected: (choice) => _change(
                          context,
                          board,
                          choice == 'remove' ? null : choice == 'show',
                        ),
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: board.visible ? 'hide' : 'show',
                            child: Text(
                              strings.feature(
                                board.visible
                                    ? 'Dölj för spelarna'
                                    : 'Visa för spelarna',
                              ),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'remove',
                            child: Text(strings.feature('Ta bort')),
                          ),
                        ],
                      )
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}
