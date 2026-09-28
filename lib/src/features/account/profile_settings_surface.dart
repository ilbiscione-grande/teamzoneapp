part of '../../app/teamzone_app.dart';

/// Prompts for and claims an invite or team-code token, shared by every
/// place in the app that lets someone add a new team connection. Both a
/// guardian invite and a general team code are issued as the same opaque
/// two-UUID token shape, so rather than making the user pick a type up
/// front (an easy way to trigger the same generic "invalid" error a valid
/// code would give if claimed as the wrong kind), team code is tried first
/// and guardian invite second; the neutral failure only shows if neither
/// server command claims the token.
Future<void> _showUseCodeDialog(
  BuildContext context, {
  required RosterServices roster,
  required Future<void> Function()? onClaimed,
}) async {
  final strings = AppStrings.of(context);
  final controller = TextEditingController();
  final token = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(strings.feature('Använd inbjudan eller lagkod')),
      content: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: strings.feature('Säker inbjudningskod'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(strings.feature('Avbryt')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
          child: Text(strings.feature('Acceptera')),
        ),
      ],
    ),
  );
  // Not disposed here: the dialog's pop transition can still be finishing
  // (especially once onClaimed below triggers a wider context-reload
  // rebuild) when this returns, and disposing synchronously raced that
  // transition into a "TextEditingController used after being disposed"
  // crash. The controller and its TextField are torn down together once
  // the transition completes; nothing else holds a reference to it.
  if (token == null || token.isEmpty || !context.mounted) return;
  var claimedAsTeamCode = false;
  try {
    try {
      await roster.claimTeamCode(token: token, idempotencyKey: _newUuid());
      claimedAsTeamCode = true;
    } catch (_) {
      await roster.acceptGuardianInvite(
        token: token,
        idempotencyKey: _newUuid(),
      );
    }
    if (context.mounted) {
      await onClaimed?.call();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            strings.feature(
              claimedAsTeamCode
                  ? 'Medlemsansökan har skapats.'
                  : 'Guardianrelationen är aktiverad.',
            ),
          ),
        ),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            strings.feature(
              'Inbjudan eller lagkoden är ogiltig eller har gått ut.',
            ),
          ),
        ),
      );
    }
  }
}

/// The personal settings page reachable from the navigation drawer/sidebar's
/// "Inställningar" row: which teams/roles the signed-in person is connected
/// to (with the ability to add a new one via an invite or team code, the
/// former per-screen "Använd kod" action now consolidated here) and their
/// privacy preference, previously a standalone bottom sheet.
class _ProfileSettingsSurface extends StatefulWidget {
  const _ProfileSettingsSurface({
    required this.contexts,
    required this.roster,
    required this.onContextsChanged,
    required this.legal,
    required this.editorial,
    required this.calendarPreferences,
  });

  final List<TeamZoneContext> contexts;
  final RosterServices roster;
  final Future<void> Function() onContextsChanged;
  final LegalServices legal;
  final EditorialServices editorial;
  final CalendarPreferences calendarPreferences;

  @override
  State<_ProfileSettingsSurface> createState() =>
      _ProfileSettingsSurfaceState();
}

class _ProfileSettingsSurfaceState extends State<_ProfileSettingsSurface> {
  late final Future<LegalStatus> _load;
  bool _pending = false;
  bool _erasurePending = false;
  bool? _marketingOptIn;
  String? _error;
  // Falls back to month (matching the calendar's own unset-preference
  // default) until the stored value (if any) loads.
  CalendarViewMode _defaultCalendarView = CalendarViewMode.month;

  @override
  void initState() {
    super.initState();
    _load = widget.legal.getStatus().timeout(const Duration(seconds: 15));
    unawaited(_loadDefaultCalendarView());
  }

  Future<void> _loadDefaultCalendarView() async {
    final stored = await widget.calendarPreferences.readDefaultViewMode();
    if (stored == null || !mounted) return;
    for (final value in CalendarViewMode.values) {
      if (value.name == stored) {
        setState(() => _defaultCalendarView = value);
        return;
      }
    }
  }

  Future<void> _setDefaultCalendarView(CalendarViewMode value) async {
    setState(() => _defaultCalendarView = value);
    await widget.calendarPreferences.writeDefaultViewMode(value.name);
  }

  Future<void> _saveMarketingPreference() async {
    if (_pending || _marketingOptIn == null) return;
    setState(() {
      _pending = true;
      _error = null;
    });
    final strings = AppStrings.of(context);
    try {
      await widget.legal
          .setMarketingPreference(
            marketingOptIn: _marketingOptIn!,
            idempotencyKey: _newUuid(),
          )
          .timeout(const Duration(seconds: 15));
      if (mounted) {
        setState(() => _pending = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(strings.feature('Sparat.'))));
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _pending = false;
          _error = strings.feature(
            'Inställningen kunde inte sparas. Försök igen.',
          );
        });
      }
    }
  }

  Future<void> _openLegalDocument(String value) async {
    final uri = Uri.tryParse(value);
    if (uri != null &&
        await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppStrings.of(
            context,
          ).feature('Dokumentet kunde inte öppnas. Försök igen.'),
        ),
      ),
    );
  }

  Future<void> _requestGlobalErasure() async {
    final strings = AppStrings.of(context);
    var reason = '';
    var acknowledged = false;
    final formKey = GlobalKey<FormState>();
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(strings.feature('Begär radering av mitt konto')),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.feature(
                      'TeamZone granskar begäran innan kontot tas bort. Verksamhetshistorik bevaras i anonymiserad form så att lagets event, närvaro och statistik fortsätter fungera.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    autofocus: true,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: 500,
                    decoration: InputDecoration(
                      labelText: strings.feature('Anledning'),
                    ),
                    onChanged: (value) => reason = value,
                    validator: (value) => (value?.trim().length ?? 0) < 2
                        ? strings.feature('Ange minst 2 tecken.')
                        : null,
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: acknowledged,
                    title: Text(
                      strings.feature(
                        'Jag förstår att kontot inte kan återställas efter godkänd radering.',
                      ),
                    ),
                    onChanged: (value) =>
                        setDialogState(() => acknowledged = value ?? false),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(strings.cancel),
            ),
            FilledButton(
              onPressed: !acknowledged
                  ? null
                  : () {
                      if (formKey.currentState?.validate() ?? false) {
                        Navigator.pop(dialogContext, true);
                      }
                    },
              child: Text(strings.feature('Skicka begäran')),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _erasurePending = true);
    try {
      await widget.roster
          .requestGlobalPersonErasure(
            reason: reason.trim(),
            idempotencyKey: _newUuid(),
          )
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        useRootNavigator: true,
        builder: (dialogContext) => AlertDialog(
          title: Text(strings.feature('Begäran är skickad')),
          content: Text(
            strings.feature(
              'TeamZone granskar ärendet. Kontot fungerar tills begäran har godkänts och slutförts.',
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(strings.feature('Stäng')),
            ),
          ],
        ),
      );
    } catch (_) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        useRootNavigator: true,
        builder: (dialogContext) => AlertDialog(
          title: Text(strings.feature('Begäran kunde inte skickas')),
          content: Text(
            strings.feature(
              'Det kan redan finnas ett öppet ärende. Försök igen senare eller kontakta TeamZone.',
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(strings.feature('Stäng')),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _erasurePending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(strings.feature('Inställningar')),
          bottom: TabBar(
            tabs: [
              Tab(text: strings.feature('Allmänt')),
              Tab(text: strings.feature('Lag')),
              Tab(text: strings.feature('Profil')),
            ],
          ),
        ),
        body: SafeArea(
          child: TabBarView(
            children: [
              _buildGeneralTab(context, strings),
              _buildTeamTab(context, strings),
              _buildProfileTab(context, strings),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGeneralTab(BuildContext context, AppStrings strings) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text(
        strings.feature('Färgtema'),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      Text(
        strings.feature(
          'Färgen är själva temat — resten av utseendet är samma '
          'oavsett vilken du väljer.',
        ),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 16),
      Builder(
        builder: (context) {
          final scope = AppColorThemeScope.of(context);
          return Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              for (final colorTheme in AppColorTheme.values)
                _ColorThemeSwatch(
                  colorTheme: colorTheme,
                  selected: scope.colorTheme == colorTheme,
                  onTap: () => scope.onColorThemeChanged(colorTheme),
                ),
            ],
          );
        },
      ),
      const SizedBox(height: 24),
      const Divider(),
      Text(
        strings.feature('Standardvy för kalendern'),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      Text(
        strings.feature(
          'Vilken vy kalendern öppnas i. Utan ett val visas månadsvyn.',
        ),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 16),
      SegmentedButton<CalendarViewMode>(
        segments: [
          for (final value in CalendarViewMode.values)
            ButtonSegment(
              value: value,
              label: Text(strings.feature(_calendarViewModeLabel(value))),
            ),
        ],
        selected: {_defaultCalendarView},
        onSelectionChanged: (selection) =>
            _setDefaultCalendarView(selection.single),
      ),
    ],
  );

  Widget _buildTeamTab(BuildContext context, AppStrings strings) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text(
        strings.feature('Mina lagkopplingar'),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      Text(
        strings.feature(
          'Här ser du vilka lag och roller du är kopplad till, och '
          'kan lägga till en ny koppling med en inbjudan eller '
          'lagkod.',
        ),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: () => _showUseCodeDialog(
          context,
          roster: widget.roster,
          onClaimed: widget.onContextsChanged,
        ),
        icon: const Icon(Icons.vpn_key_outlined),
        label: Text(strings.feature('Använd kod')),
      ),
      const SizedBox(height: 16),
      if (widget.contexts.isEmpty)
        Text(strings.feature('Du har inga lagkopplingar ännu.'))
      else
        for (final item in widget.contexts)
          Card(
            child: ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: Text(item.teamName ?? item.clubName),
              subtitle: Text(
                item.teamName == null
                    ? strings.domainValue(item.rolePackage)
                    : '${item.clubName} · '
                          '${strings.domainValue(item.rolePackage)}',
              ),
            ),
          ),
      const SizedBox(height: 24),
      const Divider(),
      Text('Laginställningar', style: Theme.of(context).textTheme.titleMedium),
      for (final item in {
        for (final item in widget.contexts)
          if (item.teamId != null &&
              (item.capabilities.contains('publication.manage') ||
                  item.capabilities.contains('team.roster.manage')))
            item.teamId!: item,
      }.values)
        ListTile(
          leading: const Icon(Icons.public),
          title: Text(item.teamName ?? item.clubName),
          subtitle: const Text('Publika matchresultat och träningstider'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => _TeamEventVisibilitySurface(
                teamId: item.teamId!,
                teamName: item.teamName ?? item.clubName,
                editorial: widget.editorial,
              ),
            ),
          ),
        ),
    ],
  );

  Widget _buildProfileTab(BuildContext context, AppStrings strings) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text(
        strings.feature('Villkor och integritet'),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      FutureBuilder<LegalStatus>(
        future: _load,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: AppLoadingIndicator(label: strings.loading),
            );
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return _StateCard(
              icon: Icons.sync_problem,
              title: strings.feature('Inställningen kunde inte laddas'),
              message: strings.feature('Försök igen om en stund.'),
            );
          }
          _marketingOptIn ??= snapshot.data!.marketingOptIn;
          final status = snapshot.data!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.description_outlined),
                title: Text(strings.feature('Användarvillkor')),
                subtitle: Text(
                  strings
                      .feature('Version {version}')
                      .replaceFirst('{version}', status.termsVersion),
                ),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => _openLegalDocument(status.termsUrl),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.privacy_tip_outlined),
                title: Text(strings.feature('Integritetspolicy')),
                subtitle: Text(
                  strings
                      .feature('Version {version}')
                      .replaceFirst('{version}', status.privacyVersion),
                ),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => _openLegalDocument(status.privacyUrl),
              ),
              const Divider(height: 32),
              Text(
                strings.feature('Integritetsinställningar'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _marketingOptIn!,
                onChanged: _pending
                    ? null
                    : (value) => setState(() => _marketingOptIn = value),
                title: Text(strings.feature('Marknadsföring från TeamZone')),
                subtitle: Text(
                  strings.feature(
                    'Frivilligt. Avstängt påverkar inte appens '
                    'funktioner.',
                  ),
                ),
              ),
              if (_error != null)
                Semantics(liveRegion: true, child: Text(_error!)),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _pending ? null : _saveMarketingPreference,
                child: Text(strings.feature('Spara')),
              ),
            ],
          );
        },
      ),
      const SizedBox(height: 24),
      const Divider(),
      const SizedBox(height: 24),
      Text(
        strings.feature('Radera konto'),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      Text(
        strings.feature(
          'Du kan begära global radering av din identitet. TeamZone granskar alltid begäran innan kontot tas bort.',
        ),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _erasurePending ? null : _requestGlobalErasure,
        icon: _erasurePending
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.person_remove_outlined),
        label: Text(strings.feature('Begär radering av mitt konto')),
      ),
    ],
  );
}

/// One selectable color swatch in the theme picker: a filled circle in that
/// theme's seed color, with a check mark overlaid when it's the active
/// theme.
class _ColorThemeSwatch extends StatelessWidget {
  const _ColorThemeSwatch({
    required this.colorTheme,
    required this.selected,
    required this.onTap,
  });

  final AppColorTheme colorTheme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Tooltip(
      message: strings.feature(colorTheme.label),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colorTheme.seed,
            shape: BoxShape.circle,
            border: selected
                ? Border.all(
                    color: Theme.of(context).colorScheme.onSurface,
                    width: 2,
                  )
                : null,
          ),
          child: selected
              ? Icon(
                  Icons.check,
                  color:
                      ThemeData.estimateBrightnessForColor(colorTheme.seed) ==
                          Brightness.dark
                      ? Colors.white
                      : Colors.black,
                )
              : null,
        ),
      ),
    );
  }
}
