part of '../../app/teamzone_app.dart';

const _clubAreaLabels = {
  'publication.manage': (
    'Publicering',
    'Klubbsidan, lagsidor och ansökningar om lagsida.',
  ),
  'club.memberships.manage': (
    'Medlemmar och lag',
    'Medlemsansökningar, nya lag, klubbens personer och klubbens behörigheter.',
  ),
  'club.messaging.manage': (
    'Anslag',
    'Skicka anslag till ledare, spelare eller hela klubben.',
  ),
  'club.referees.manage': ('Domartillsättning', 'Klubbens matcher och domare.'),
};

/// Klubbens behörigheter: the club's areas given to its functionaries, by
/// those who hold members and teams. Each switch saves at once; an area the
/// viewer does not hold cannot be given or taken back, and the club always
/// keeps someone with members and teams.
class _ClubPermissionsSurface extends StatefulWidget {
  const _ClubPermissionsSurface({required this.clubId, required this.roster});
  final String clubId;
  final RosterServices roster;

  @override
  State<_ClubPermissionsSurface> createState() =>
      _ClubPermissionsSurfaceState();
}

class _ClubPermissionsSurfaceState extends State<_ClubPermissionsSurface> {
  late Future<ClubPermissions> _permissions = _load();
  String? _busyPerson;

  Future<ClubPermissions> _load() =>
      widget.roster.getClubPermissions(widget.clubId);

  Future<void> _toggle(
    ClubPermissionPerson person,
    String area,
    bool on,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final wanted = {...person.capabilities};
    on ? wanted.add(area) : wanted.remove(area);
    setState(() => _busyPerson = person.personId);
    try {
      await widget.roster.setClubPermissions(
        clubId: widget.clubId,
        personId: person.personId,
        capabilities: wanted.toList(),
        expected: person.capabilities.toList(),
        idempotencyKey: _newUuid(),
      );
      final label = _clubAreaLabels[area]?.$1 ?? area;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            on
                ? '${person.name} har nu $label.'
                : '${person.name} har inte längre $label.',
          ),
        ),
      );
    } on TeamRoleException catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(switch (error.code) {
            'last_memberships_manager' =>
              'Klubben måste ha minst en person med Medlemmar och lag.',
            'not_grantable' =>
              'Du kan bara dela ut och ta tillbaka områden du själv har.',
            _ =>
              'Behörigheterna har ändrats av någon annan. De senaste visas nu.',
          }),
        ),
      );
    } catch (error) {
      AppErrors.caught('club_permissions_surface._toggle', error);
      messenger.showSnackBar(
        const SnackBar(content: Text('Behörigheten kunde inte sparas.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busyPerson = null;
          _permissions = _load();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Klubbens behörigheter')),
    body: FutureBuilder<ClubPermissions>(
      future: _permissions,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: () => setState(() => _permissions = _load()),
              child: const Text(
                'Behörigheterna kunde inte hämtas. Försök igen.',
              ),
            ),
          );
        }
        final permissions = snapshot.data;
        if (permissions == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Ge klubbens funktionärer de områden de ska sköta, till exempel '
              'Publicering till ordföranden. Du kan dela ut och ta tillbaka '
              'områden du själv har. Styrelse och ekonomi följer '
              'styrelseuppdragen.',
            ),
            const SizedBox(height: 12),
            if (permissions.people.isEmpty)
              const Text('Klubben har inga funktionärer än.'),
            for (final person in permissions.people)
              Card(
                key: ValueKey('club-permissions-${person.personId}'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ListTile(
                        title: Text(
                          person.isSelf ? '${person.name} (du)' : person.name,
                        ),
                        subtitle: Text(
                          person.capabilities.isEmpty
                              ? 'Inga klubbområden'
                              : [
                                  for (final area in ClubPermissions.areas)
                                    if (person.capabilities.contains(area))
                                      _clubAreaLabels[area]!.$1,
                                ].join(' · '),
                        ),
                      ),
                      for (final area in ClubPermissions.areas)
                        SwitchListTile(
                          key: ValueKey(
                            'club-permission-${person.personId}-$area',
                          ),
                          dense: true,
                          title: Text(_clubAreaLabels[area]!.$1),
                          subtitle: Text(_clubAreaLabels[area]!.$2),
                          value: person.capabilities.contains(area),
                          onChanged:
                              _busyPerson != null ||
                                  !permissions.grantable.contains(area)
                              ? null
                              : (on) => _toggle(person, area, on),
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
