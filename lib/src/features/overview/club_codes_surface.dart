part of '../../app/teamzone_app.dart';

// Klubbkod (2026-11-11): a code to apply to the club itself, as a member
// without a team or as board/functionary. Like a team code, it sends an
// application the club admin approves; offices and rights are still given
// under Klubbens behörigheter.

class _ClubCodesPage extends StatefulWidget {
  const _ClubCodesPage({required this.clubId, required this.services});
  final String clubId;
  final ClubJoinServices services;

  @override
  State<_ClubCodesPage> createState() => _ClubCodesPageState();
}

class _ClubCodesPageState extends State<_ClubCodesPage> {
  late Future<List<ClubJoinCode>> _codes = _load();
  bool _busy = false;

  Future<List<ClubJoinCode>> _load() =>
      widget.services.listClubCodes(widget.clubId);

  void _reload() => setState(() {
    _codes = _load();
  });

  Future<void> _create(MembershipRole role) async {
    final strings = AppStrings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    final token = '${_newUuid()}${_newUuid()}';
    try {
      await widget.services.issueClubCode(
        clubId: widget.clubId,
        role: role,
        token: token,
        expiresAt: DateTime.now().toUtc().add(const Duration(days: 90)),
        idempotencyKey: _newUuid(),
      );
      if (!mounted) return;
      setState(() => _busy = false);
      _reload();
      await _show(token, role);
    } catch (error) {
      AppErrors.caught('club_codes._create', error);
      messenger.showSnackBar(
        SnackBar(content: Text(strings.feature('Koden kunde inte skapas.'))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reveal(ClubJoinCode code) async {
    final strings = AppStrings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final token = await widget.services.revealClubCode(code.codeId);
      if (mounted) await _show(token, code.role);
    } catch (error) {
      AppErrors.caught('club_codes._reveal', error);
      messenger.showSnackBar(
        SnackBar(content: Text(strings.feature('Koden kunde inte visas.'))),
      );
    }
  }

  Future<void> _show(String token, MembershipRole role) => showDialog<void>(
    context: context,
    builder: (context) {
      final strings = AppStrings.of(context);
      return AlertDialog(
        title: Text(strings.feature('Klubbkod')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(membershipRoleLabel(strings, role)),
            const SizedBox(height: 8),
            SelectableText(key: const ValueKey('club-code-token'), token),
            const SizedBox(height: 8),
            Text(
              strings.feature(
                'Den som får koden klistrar in den under "Har du fått en inbjudan?" eller Profil → Använd inbjudan eller lagkod. Du godkänner ansökan under Medlemsansökningar.',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: token));
              if (context.mounted) Navigator.of(context).pop();
            },
            child: Text(strings.feature('Kopiera')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(strings.feature('Klar')),
          ),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(strings.feature('Klubbkod'))),
      body: FutureBuilder<List<ClubJoinCode>>(
        future: _codes,
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
          final codes = snapshot.data;
          if (codes == null) {
            return AppLoadingIndicator(label: strings.loading);
          }
          return ListView(
            key: const ValueKey('club-codes'),
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                strings.feature(
                  'En klubbkod låter någon ansöka till klubben utan att välja lag: som medlem i klubben (stödmedlem, förälder, ideell) eller som styrelse eller funktionär. Ansökan godkänns av klubbadmin. Styrelseroll och behörigheter ger du sedan under Klubbens behörigheter.',
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final role in clubApplicationRoles)
                    FilledButton.tonal(
                      key: ValueKey('club-code-new-${role.wireName}'),
                      onPressed: _busy ? null : () => _create(role),
                      child: Text(
                        '${strings.feature('Ny kod')}: ${membershipRoleLabel(strings, role)}',
                      ),
                    ),
                ],
              ),
              if (_busy) const LinearProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                strings.feature('Aktiva koder'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (codes.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(strings.feature('Inga aktiva klubbkoder.')),
                ),
              for (final code in codes)
                ListTile(
                  key: ValueKey('club-code-${code.codeId}'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.key_outlined),
                  title: Text(membershipRoleLabel(strings, code.role)),
                  subtitle: Text(
                    '${strings.feature('Gäller till')} ${_feeDay(code.expiresAt.toLocal())} · '
                    '${code.useCount} ${strings.feature('använd')}',
                  ),
                  trailing: code.recoverable
                      ? TextButton(
                          onPressed: () => _reveal(code),
                          child: Text(strings.feature('Visa')),
                        )
                      : null,
                ),
            ],
          );
        },
      ),
    );
  }
}
