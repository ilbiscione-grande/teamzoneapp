part of '../../app/teamzone_app.dart';

// Familjer (club-members-and-fees.md, step 2): members linked through a
// shared guardian are one family for the family discount. The club can move
// someone out, add someone and reset a family to follow the guardians again.

class _ClubFamiliesPage extends StatefulWidget {
  const _ClubFamiliesPage({required this.clubId, required this.services});
  final String clubId;
  final ClubFeeServices services;

  @override
  State<_ClubFamiliesPage> createState() => _ClubFamiliesPageState();
}

class _ClubFamiliesPageState extends State<_ClubFamiliesPage> {
  late Future<List<ClubFamilyMember>> _members = _load();
  bool _busy = false;

  Future<List<ClubFamilyMember>> _load() =>
      widget.services.loadClubFamilies(widget.clubId);

  void _reload() => setState(() {
    _members = _load();
  });

  Future<void> _change(String change, List<String> personIds) async {
    final strings = AppStrings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await widget.services.changeClubFamily(
        clubId: widget.clubId,
        change: change,
        personIds: personIds,
        idempotencyKey: _newUuid(),
      );
    } catch (error) {
      AppErrors.caught('club_families._change', error);
      messenger.showSnackBar(
        SnackBar(content: Text(strings.feature('Det gick inte. Försök igen.'))),
      );
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _reload();
  }

  Future<void> _add(ClubFamily family, List<ClubFamilyMember> all) async {
    final picked = await showModalBottomSheet<ClubFamilyMember>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FamilyMemberPicker(
        members: [
          for (final member in all)
            if (member.familyKey != family.key) member,
        ],
      ),
    );
    if (picked == null || !mounted) return;
    await _change('merge', [family.members.first.personId, picked.personId]);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(strings.feature('Familjer'))),
      body: FutureBuilder<List<ClubFamilyMember>>(
        future: _members,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: _StateCard(
                icon: Icons.sync_problem,
                title: strings.couldNotLoad,
                message: strings.safeError,
                action: FilledButton(
                  onPressed: _reload,
                  child: Text(strings.retry),
                ),
              ),
            );
          }
          final members = snapshot.data;
          if (members == null) {
            return AppLoadingIndicator(label: strings.loading);
          }
          final families = clubFamiliesOf(members);
          return ListView(
            key: const ValueKey('club-families'),
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                strings.feature(
                  'Medlemmar med en gemensam vårdnadshavare blir en familj för familjerabatten. Ändra om det har blivit fel, till exempel när föräldrarna bor isär.',
                ),
              ),
              if (_busy) const LinearProgressIndicator(),
              const SizedBox(height: 12),
              if (families.isEmpty)
                Text(strings.feature('Inga familjer med fler än en medlem.')),
              for (final family in families)
                Card(
                  key: ValueKey('club-family-${family.key}'),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          family.members
                              .map((member) => member.name)
                              .join(', '),
                          style: theme.textTheme.titleMedium,
                        ),
                        if (family.guardians.isNotEmpty)
                          Text(
                            '${strings.feature('Vårdnadshavare')}: ${family.guardians.join(', ')}',
                          ),
                        if (family.manual)
                          Text(
                            strings.feature('Ändrad för hand'),
                            style: TextStyle(color: theme.colorScheme.primary),
                          ),
                        for (final member in family.members)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text(member.name),
                            subtitle: Text(
                              _memberCategoryLabel(strings, member.category),
                            ),
                            trailing: family.members.length > 1
                                ? TextButton(
                                    key: ValueKey(
                                      'club-family-split-${member.personId}',
                                    ),
                                    onPressed: _busy
                                        ? null
                                        : () => _change('split', [
                                            member.personId,
                                          ]),
                                    child: Text(strings.feature('Flytta ut')),
                                  )
                                : null,
                          ),
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton.icon(
                              key: ValueKey('club-family-add-${family.key}'),
                              onPressed: _busy
                                  ? null
                                  : () => _add(family, members),
                              icon: const Icon(Icons.person_add_alt_outlined),
                              label: Text(strings.feature('Lägg till')),
                            ),
                            if (family.manual)
                              TextButton.icon(
                                key: ValueKey(
                                  'club-family-reset-${family.key}',
                                ),
                                onPressed: _busy
                                    ? null
                                    : () => _change('reset', [
                                        for (final member in family.members)
                                          member.personId,
                                      ]),
                                icon: const Icon(Icons.undo),
                                label: Text(
                                  strings.feature('Följ vårdnadshavarna igen'),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Search the members to add to a family.
class _FamilyMemberPicker extends StatefulWidget {
  const _FamilyMemberPicker({required this.members});
  final List<ClubFamilyMember> members;

  @override
  State<_FamilyMemberPicker> createState() => _FamilyMemberPickerState();
}

class _FamilyMemberPickerState extends State<_FamilyMemberPicker> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final query = _search.text.trim().toLowerCase();
    final visible = [
      for (final member in widget.members)
        if (query.isEmpty || member.name.toLowerCase().contains(query)) member,
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            strings.feature('Lägg till i familjen'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('club-family-search'),
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: strings.feature('Sök på namn'),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final member in visible)
                  ListTile(
                    key: ValueKey('club-family-pick-${member.personId}'),
                    title: Text(member.name),
                    subtitle: member.guardians.isEmpty
                        ? null
                        : Text(
                            '${strings.feature('Vårdnadshavare')}: ${member.guardians.join(', ')}',
                          ),
                    onTap: () => Navigator.of(context).pop(member),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
