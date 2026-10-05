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
    required this.profileServices,
    this.onOwnProfileChanged,
    this.messaging,
    this.embedded = false,
    this.openProfile = false,
    this.membership = const UnconfiguredMembershipServices(),
  });

  final List<TeamZoneContext> contexts;
  final RosterServices roster;

  /// Club verification for the club settings.
  final MembershipServices membership;
  final Future<void> Function() onContextsChanged;
  final LegalServices legal;
  final EditorialServices editorial;
  final CalendarPreferences calendarPreferences;
  final ProfileServices profileServices;
  final VoidCallback? onOwnProfileChanged;
  final MessagingServices? messaging;

  /// One list of all personal settings, for the profile page's tab.
  final bool embedded;
  final bool openProfile;

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
  bool _showWeekNumbers = true;
  bool _showQuarterHourMarks = false;
  late Future<bool?> _pushEnabled = _loadPush();

  Future<bool?> _loadPush() async {
    final messaging = widget.messaging;
    if (messaging == null) return null;
    try {
      return (await messaging.getPreferences()).pushEnabled;
    } catch (_) {
      return null;
    }
  }

  Future<void> _setPushEnabled(bool value) async {
    final messaging = widget.messaging;
    if (messaging == null) return;
    setState(() {
      _pushEnabled = Future.value(value);
    });
    try {
      await messaging.setPushEnabled(value, _newUuid());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pushEnabled = _loadPush();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppStrings.of(context).safeError)));
    }
  }

  // Shared with the calendar's own filter sheet (same stored keys).
  Future<void> _loadCalendarFlags() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _showWeekNumbers =
          preferences.getBool('calendar.showWeekNumbers') ?? true;
      _showQuarterHourMarks =
          preferences.getBool('calendar.showQuarterHourMarks') ?? false;
    });
  }

  Future<void> _setCalendarFlag(
    String key,
    bool value,
    void Function(bool value) apply,
  ) async {
    setState(() => apply(value));
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(key, value);
  }

  @override
  void initState() {
    super.initState();
    _load = widget.legal.getStatus().timeout(const Duration(seconds: 15));
    unawaited(_loadDefaultCalendarView());
    unawaited(_loadCalendarFlags());
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

  Widget _buildTeamTab(BuildContext context, AppStrings strings) => ListView(
    padding: const EdgeInsets.all(16),
    children: _teamItems(context, strings),
  );

  /// One entry per club the user administers.
  List<TeamZoneContext> get _adminClubs => {
    for (final item in widget.contexts)
      if (item.capabilities.contains('club.memberships.manage'))
        item.clubId: item,
  }.values.toList(growable: false);

  Widget _buildClubTab(BuildContext context, AppStrings strings) => ListView(
    key: const ValueKey('club-settings'),
    padding: const EdgeInsets.all(16),
    children: _clubItems(context, strings),
  );

  List<Widget> _clubItems(BuildContext context, AppStrings strings) {
    final clubs = _adminClubs;
    final theme = Theme.of(context);
    return [
      Text(
        strings.feature('Klubbinställningar'),
        style: theme.textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      Text(
        strings.feature(
          'För klubbens administratörer: klubbmärke, färger och verifiering.',
        ),
        style: theme.textTheme.bodyMedium,
      ),
      for (final club in clubs) ...[
        const SizedBox(height: 16),
        Card(
          key: ValueKey('club-settings-${club.clubId}'),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ClubSettingsHeader(
                key: ValueKey('club-header-${club.clubId}'),
                profile: widget.profileServices,
                clubId: club.clubId,
                clubName: club.clubName,
              ),
              const Divider(height: 1),
              ListTile(
                key: ValueKey('club-badge-${club.clubId}'),
                leading: const Icon(Icons.verified_user_outlined),
                title: Text(strings.feature('Klubbmärke')),
                subtitle: Text(
                  strings.feature('Visas på klubbens medlemskort.'),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => _ClubBadgeDialog(
                    profile: widget.profileServices,
                    clubId: club.clubId,
                    clubName: club.clubName,
                  ),
                ),
              ),
              ListTile(
                key: ValueKey('club-colors-${club.clubId}'),
                leading: const Icon(Icons.palette_outlined),
                title: Text(strings.feature('Klubbens färger')),
                subtitle: Text(
                  strings.feature('Färger på klubbens publika sidor.'),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showDialog<bool>(
                  context: context,
                  builder: (_) => _ClubColorsDialog(
                    profile: widget.profileServices,
                    clubId: club.clubId,
                    clubName: club.clubName,
                  ),
                ),
              ),
              ListTile(
                key: ValueKey('club-verification-${club.clubId}'),
                leading: const Icon(Icons.verified_outlined),
                title: Text(strings.feature('Klubbverifiering')),
                subtitle: Text(
                  strings.feature(
                    'Se officiell status eller skicka underlag till TeamZone.',
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (_) => _ClubVerificationSheet(
                    clubId: club.clubId,
                    membership: widget.membership,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final showTeam = widget.contexts.any((item) => item.teamId != null);
    final showClub = _adminClubs.isNotEmpty;
    final showPublic = _publicPageContexts.isNotEmpty;
    if (widget.embedded) {
      final sections = <(String, Widget)>[
        (
          strings.feature('Personligt'),
          ListView(
            key: const ValueKey('personal-settings'),
            padding: const EdgeInsets.all(16),
            children: [
              ..._generalItems(context, strings),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              ..._privacyItems(context, strings),
            ],
          ),
        ),
        if (showTeam)
          (
            strings.feature('Lag'),
            ListView(
              key: const ValueKey('team-settings'),
              padding: const EdgeInsets.all(16),
              children: _teamItems(context, strings),
            ),
          ),
        if (showClub)
          (strings.feature('Klubb'), _buildClubTab(context, strings)),
        if (showPublic)
          (
            strings.feature('Publika sidor'),
            _buildPublicPagesTab(context, strings),
          ),
      ];
      return DefaultTabController(
        length: sections.length,
        child: Column(
          children: [
            Material(
              color: Theme.of(context).colorScheme.surface,
              child: TabBar(
                isScrollable: true,
                tabs: [for (final section in sections) Tab(text: section.$1)],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [for (final section in sections) section.$2],
              ),
            ),
          ],
        ),
      );
    }
    return DefaultTabController(
      length:
          1 + (showTeam ? 1 : 0) + (showClub ? 1 : 0) + (showPublic ? 1 : 0),
      child: Scaffold(
        appBar: AppBar(
          title: Text(strings.feature('Inställningar')),
          bottom: TabBar(
            tabs: [
              Tab(text: strings.feature('Personligt')),
              if (showTeam) Tab(text: strings.feature('Lag')),
              if (showClub) Tab(text: strings.feature('Klubb')),
              if (showPublic) Tab(text: strings.feature('Publika sidor')),
            ],
          ),
        ),
        body: SafeArea(
          child: TabBarView(
            children: [
              ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  ..._generalItems(context, strings),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),
                  ..._privacyItems(context, strings),
                ],
              ),
              if (showTeam) _buildTeamTab(context, strings),
              if (showClub) _buildClubTab(context, strings),
              if (showPublic) _buildPublicPagesTab(context, strings),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _generalItems(BuildContext context, AppStrings strings) => [
    Text(
      strings.feature('Ljust eller mörkt'),
      style: Theme.of(context).textTheme.titleMedium,
    ),
    const SizedBox(height: 8),
    Builder(
      builder: (context) {
        final scope = AppColorThemeScope.of(context);
        return SegmentedButton<ThemeMode>(
          key: const ValueKey('setting-theme-mode'),
          segments: [
            ButtonSegment(
              value: ThemeMode.system,
              icon: const Icon(Icons.brightness_auto_outlined),
              label: Text(strings.feature('System')),
            ),
            ButtonSegment(
              value: ThemeMode.light,
              icon: const Icon(Icons.light_mode_outlined),
              label: Text(strings.feature('Ljust')),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              icon: const Icon(Icons.dark_mode_outlined),
              label: Text(strings.feature('Mörkt')),
            ),
          ],
          selected: {scope.themeMode},
          onSelectionChanged: (selection) =>
              scope.onThemeModeChanged?.call(selection.single),
        );
      },
    ),
    const SizedBox(height: 24),
    const Divider(),
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
    const SizedBox(height: 8),
    SwitchListTile(
      key: const ValueKey('setting-week-numbers'),
      contentPadding: EdgeInsets.zero,
      title: Text(strings.feature('Visa veckonummer')),
      value: _showWeekNumbers,
      onChanged: (value) =>
          _setCalendarFlag('calendar.showWeekNumbers', value, (v) {
            _showWeekNumbers = v;
          }),
    ),
    SwitchListTile(
      key: const ValueKey('setting-quarter-marks'),
      contentPadding: EdgeInsets.zero,
      title: Text(strings.feature('Visa kvartsmarkeringar')),
      subtitle: Text(
        strings.feature('Extra tunna linjer var 15:e minut i dagsvyn.'),
      ),
      value: _showQuarterHourMarks,
      onChanged: (value) =>
          _setCalendarFlag('calendar.showQuarterHourMarks', value, (v) {
            _showQuarterHourMarks = v;
          }),
    ),
    if (widget.messaging != null) ...[
      const SizedBox(height: 16),
      const Divider(),
      Text(
        strings.feature('Notiser'),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      FutureBuilder<bool?>(
        future: _pushEnabled,
        builder: (context, snapshot) => SwitchListTile(
          key: const ValueKey('setting-push'),
          contentPadding: EdgeInsets.zero,
          title: Text(strings.feature('Frivilliga pushnotiser')),
          subtitle: Text(
            strings.feature(
              'Av som standard. Låsskärmen visar bara att ett nytt meddelande finns.',
            ),
          ),
          value: snapshot.data ?? false,
          onChanged: snapshot.data == null ? null : _setPushEnabled,
        ),
      ),
    ],
  ];

  List<Widget> _teamItems(BuildContext context, AppStrings strings) => [
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
                  ? _contextRolesLabel(strings, item)
                  : '${item.clubName} · '
                        '${_contextRolesLabel(strings, item)}',
            ),
          ),
        ),
  ];

  /// Contexts that may work with public pages: publishers and the team
  /// leaders who apply for and follow their team page.
  List<TeamZoneContext> get _publicPageContexts => [
    for (final item in widget.contexts)
      if (item.capabilities.contains('publication.manage') ||
          item.capabilities.contains('team.roster.manage'))
        item,
  ];

  Widget _buildPublicPagesTab(BuildContext context, AppStrings strings) =>
      ListView(
        key: const ValueKey('public-pages-settings'),
        padding: const EdgeInsets.all(16),
        children: _publicPageItems(context, strings),
      );

  /// One card per club: the club and team pages, the teams' public
  /// activities and the newsroom.
  List<Widget> _publicPageItems(BuildContext context, AppStrings strings) {
    final byClub = <String, List<TeamZoneContext>>{};
    for (final item in _publicPageContexts) {
      byClub.putIfAbsent(item.clubId, () => []).add(item);
    }
    final theme = Theme.of(context);
    return [
      Text(
        strings.feature('Publika sidor'),
        style: theme.textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      Text(
        strings.feature(
          'Klubbens och lagens publika sidor, vad som visas och nyheter.',
        ),
        style: theme.textTheme.bodyMedium,
      ),
      for (final items in byClub.values) ...[
        const SizedBox(height: 16),
        Card(
          key: ValueKey('public-pages-${items.first.clubId}'),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                title: Text(
                  items.first.clubName,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              const Divider(height: 1),
              ListTile(
                key: ValueKey('club-public-${items.first.clubId}'),
                leading: const Icon(Icons.public),
                title: Text(strings.feature('Publik klubbsida och lagsidor')),
                subtitle: Text(
                  strings.feature(
                    'Synlighet, webbadress och vad som visas publikt.',
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _PublicationSelfServiceSurface(
                      clubId: items.first.clubId,
                      editorial: widget.editorial,
                    ),
                  ),
                ),
              ),
              for (final item in {
                for (final item in items)
                  if (item.teamId != null) item.teamId!: item,
              }.values)
                ListTile(
                  key: ValueKey('team-public-${item.teamId}'),
                  leading: const Icon(Icons.event_available_outlined),
                  title: Text(item.teamName ?? item.clubName),
                  subtitle: Text(
                    strings.feature(
                      'Publika matcher, resultat och träningstider',
                    ),
                  ),
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
              // One newsroom per club, opened from a publishing context.
              for (final item
                  in items
                      .where((item) => item.can('publication.manage'))
                      .take(1))
                ListTile(
                  key: ValueKey('club-news-${item.clubId}'),
                  leading: const Icon(Icons.newspaper_outlined),
                  title: Text(strings.feature('Nyheter')),
                  subtitle: Text(
                    strings.feature(
                      'Skriv och publicera nyheter på klubbens publika sida.',
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _EditorialSurface(
                        contextValue: item,
                        contexts: widget.contexts,
                        editorial: widget.editorial,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    ];
  }

  /// Terms, privacy choices and account deletion.
  List<Widget> _privacyItems(BuildContext context, AppStrings strings) => [
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
  ];
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

/// The club's name and current badge, with the badge upload one tap away.
class _ClubSettingsHeader extends StatefulWidget {
  const _ClubSettingsHeader({
    super.key,
    required this.profile,
    required this.clubId,
    required this.clubName,
  });
  final ProfileServices profile;
  final String clubId, clubName;
  @override
  State<_ClubSettingsHeader> createState() => _ClubSettingsHeaderState();
}

class _ClubSettingsHeaderState extends State<_ClubSettingsHeader> {
  late Future<String?> _badge = widget.profile.clubBadgeUrl(widget.clubId);

  Future<void> _editBadge() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ClubBadgeDialog(
        profile: widget.profile,
        clubId: widget.clubId,
        clubName: widget.clubName,
      ),
    );
    if (mounted) {
      setState(() => _badge = widget.profile.clubBadgeUrl(widget.clubId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: FutureBuilder<String?>(
        future: _badge,
        builder: (context, snapshot) {
          final url = snapshot.data;
          return Row(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _editBadge,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: _ClubBadge(name: widget.clubName, url: url, size: 64),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.clubName, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 6),
                    OutlinedButton.icon(
                      key: ValueKey('club-badge-upload-${widget.clubId}'),
                      onPressed: _editBadge,
                      icon: const Icon(Icons.upload_outlined, size: 18),
                      label: Text(
                        strings.feature(
                          url == null
                              ? 'Ladda upp klubbmärke'
                              : 'Byt klubbmärke',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
