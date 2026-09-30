part of '../../app/teamzone_app.dart';

/// Contact details on a member's profile, for the person and the team's
/// leaders. The person edits their own; leaders keep them for members
/// without an account.
class _PersonContactTiles extends StatelessWidget {
  const _PersonContactTiles({
    required this.contact,
    required this.isSelf,
    required this.onEditOwn,
    required this.onEditClub,
  });
  final PersonContact contact;
  final bool isSelf;
  final VoidCallback onEditOwn, onEditClub;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    if (!contact.canSeeContact) return const SizedBox.shrink();
    final email = contact.contactEmail;
    final phone = contact.phone;
    return Column(
      key: const ValueKey('person-contact'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: const Icon(Icons.mail_outline),
          title: Text(strings.feature('E-post')),
          subtitle: Text(email ?? strings.feature('Ingen angiven')),
          onTap: email == null
              ? null
              : () => launchUrl(Uri(scheme: 'mailto', path: email)),
        ),
        ListTile(
          leading: const Icon(Icons.phone_outlined),
          title: Text(strings.feature('Telefon')),
          subtitle: Text(phone ?? strings.feature('Inget angivet')),
          onTap: phone == null
              ? null
              : () => launchUrl(
                  Uri(scheme: 'tel', path: phone.replaceAll(' ', '')),
                ),
        ),
        if (contact.hasAddress)
          ListTile(
            leading: const Icon(Icons.home_outlined),
            title: Text(strings.feature('Adress')),
            subtitle: Text(
              [
                contact.streetAddress,
                [contact.postalCode, contact.city]
                    .whereType<String>()
                    .where((part) => part.trim().isNotEmpty)
                    .join(' '),
              ].whereType<String>().where((part) => part.isNotEmpty).join('\n'),
            ),
          ),
        if (contact.contactSource == 'club')
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 4),
            child: Text(
              strings.feature('Ifyllt av klubben.'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (isSelf)
          ListTile(
            key: const ValueKey('edit-own-profile'),
            leading: const Icon(Icons.edit_outlined),
            title: Text(strings.feature('Redigera mina uppgifter')),
            subtitle: Text(
              strings.feature('Namn, kontaktuppgifter och profilbild.'),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: onEditOwn,
          )
        else if (contact.canEditClubContact)
          ListTile(
            key: const ValueKey('edit-club-contact'),
            leading: const Icon(Icons.edit_outlined),
            title: Text(strings.feature('Ändra kontaktuppgifter')),
            subtitle: Text(
              strings.feature(
                'Personen har inget konto, så klubben fyller i uppgifterna.',
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: onEditClub,
          ),
      ],
    );
  }
}

/// Leaders keep contact details for a member without an account.
Future<bool> _editClubContact(
  BuildContext context, {
  required ProfileServices profile,
  required String clubId,
  required String teamId,
  required String personId,
  required PersonContact current,
}) async {
  final strings = AppStrings.of(context);
  final email = TextEditingController(text: current.contactEmail);
  final phone = TextEditingController(text: current.phone);
  final street = TextEditingController(text: current.streetAddress);
  final postal = TextEditingController(text: current.postalCode);
  final city = TextEditingController(text: current.city);
  String? text(TextEditingController controller) =>
      controller.text.trim().isEmpty ? null : controller.text.trim();
  String? error;
  final saved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: Text(strings.feature('Kontaktuppgifter')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const ValueKey('club-contact-email'),
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: strings.feature('E-post'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('club-contact-phone'),
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: strings.feature('Telefon'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('club-contact-street'),
                controller: street,
                decoration: InputDecoration(
                  labelText: strings.feature('Gatuadress'),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 110,
                    child: TextField(
                      key: const ValueKey('club-contact-postal'),
                      controller: postal,
                      decoration: InputDecoration(
                        labelText: strings.feature('Postnummer'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('club-contact-city'),
                      controller: city,
                      decoration: InputDecoration(
                        labelText: strings.feature('Ort'),
                      ),
                    ),
                  ),
                ],
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(dialogContext).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(strings.feature('Avbryt')),
          ),
          FilledButton(
            key: const ValueKey('save-club-contact'),
            onPressed: () async {
              try {
                await profile.setPersonContact(
                  clubId: clubId,
                  teamId: teamId,
                  personId: personId,
                  contactEmail: email.text.trim().isEmpty
                      ? null
                      : email.text.trim(),
                  phone: phone.text.trim().isEmpty ? null : phone.text.trim(),
                );
                await profile.setPersonAddress(
                  clubId: clubId,
                  teamId: teamId,
                  personId: personId,
                  street: text(street),
                  postalCode: text(postal),
                  city: text(city),
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext, true);
              } catch (e) {
                setDialogState(() => error = _profileErrorMessage(strings, e));
              }
            },
            child: Text(strings.feature('Spara')),
          ),
        ],
      ),
    ),
  );
  // The dialog may still animate out; dispose after that.
  Future<void>.delayed(const Duration(seconds: 1), () {
    email.dispose();
    phone.dispose();
    street.dispose();
    postal.dispose();
    city.dispose();
  });
  return saved ?? false;
}

/// Support's queue of login email changes.
class _LoginEmailChangeQueue extends StatefulWidget {
  const _LoginEmailChangeQueue({required this.profile});
  final ProfileServices profile;
  @override
  State<_LoginEmailChangeQueue> createState() => _LoginEmailChangeQueueState();
}

class _LoginEmailChangeQueueState extends State<_LoginEmailChangeQueue> {
  late Future<List<LoginEmailChange>> _load = _reload();

  Future<List<LoginEmailChange>> _reload() => widget.profile
      .listLoginEmailChanges(state: 'pending')
      .timeout(const Duration(seconds: 15));

  Future<void> _decide(LoginEmailChange change, bool approve) async {
    final strings = AppStrings.of(context);
    final note = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.feature(approve ? 'Godkänn byte' : 'Avslå byte')),
        content: TextField(
          key: const ValueKey('email-change-note'),
          controller: note,
          maxLength: 500,
          decoration: InputDecoration(
            labelText: strings.feature('Beslutsanteckning'),
            helperText: strings.feature(
              'T.ex. hur identiteten kontrollerades.',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(strings.feature('Avbryt')),
          ),
          FilledButton(
            onPressed: () {
              if (note.text.trim().length >= 2) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: Text(strings.feature(approve ? 'Godkänn' : 'Avslå')),
          ),
        ],
      ),
    );
    final text = note.text.trim();
    Future<void>.delayed(const Duration(seconds: 1), note.dispose);
    if (confirmed != true || !mounted) return;
    try {
      await widget.profile.decideLoginEmailChange(
        requestId: change.id,
        approve: approve,
        note: text,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              strings.feature('Beslutet kunde inte sparas. Ladda om.'),
            ),
          ),
        );
      }
    }
    if (mounted) {
      setState(() {
        _load = _reload();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return FutureBuilder<List<LoginEmailChange>>(
      future: _load,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final items = snapshot.data ?? const <LoginEmailChange>[];
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text(
              strings.feature('Byte av inloggningsadress'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (snapshot.hasError)
              Text(strings.feature('Kön kunde inte laddas.'))
            else if (items.isEmpty)
              Text(strings.feature('Inga väntande begäranden.')),
            for (final change in items)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        change.displayName ?? '',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${change.currentEmail ?? '–'} → ${change.requestedEmail}',
                      ),
                      if (change.reason != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            change.reason!,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          FilledButton(
                            onPressed: () => _decide(change, true),
                            child: Text(strings.feature('Godkänn')),
                          ),
                          OutlinedButton(
                            onPressed: () => _decide(change, false),
                            child: Text(strings.feature('Avslå')),
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
    );
  }
}
