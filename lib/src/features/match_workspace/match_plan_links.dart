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
