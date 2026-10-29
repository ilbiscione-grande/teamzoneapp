part of '../../app/teamzone_app.dart';

/// The profile's own heading on both tabs: the picture on the left of a deep
/// green card with the name, number and role, the club and team, and the
/// main position or title.
class _PersonProfileHero extends StatelessWidget {
  const _PersonProfileHero({
    required this.person,
    required this.clubName,
    required this.roles,
    this.contact,
  });
  final RosterPersonDetails person;
  final String clubName;
  final Future<TeamRoles> roles;
  final Future<(PersonContact, String?)>? contact;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    // Deepened in the dark theme, whose accent is a light green, so the
    // white text keeps its contrast.
    final dark = theme.brightness == Brightness.dark;
    final top = Color.lerp(palette.accent, Colors.black, dark ? .55 : .25)!;
    final bottom = Color.lerp(palette.accent, Colors.black, dark ? .8 : .6)!;
    final name = person.isSelf
        ? '${person.displayName} (${strings.feature('du')})'
        : person.displayName;
    final white = Colors.white.withValues(alpha: .9);
    return Container(
      key: const ValueKey('person-profile-hero'),
      constraints: const BoxConstraints(minHeight: 168),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [top, bottom],
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 128,
              child: FutureBuilder<(PersonContact, String?)>(
                future: contact,
                builder: (context, snapshot) => _HeroPicture(
                  name: person.displayName,
                  url: snapshot.data?.$2,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 16, 16, 16),
                child: FutureBuilder<TeamRoles>(
                  future: roles,
                  builder: (context, snapshot) {
                    final data = snapshot.data;
                    final held = data?.rolesOf(person.id) ?? const <String>[];
                    final row = data?.roles
                        .where((role) => role.personId == person.id)
                        .firstOrNull;
                    final roleLine = [
                      if (held.contains('player') && row?.jerseyNumber != null)
                        '#${row!.jerseyNumber}',
                      ...held.map((role) => _roleLabel(strings, role)),
                    ].join(' · ');
                    final position = row == null
                        ? null
                        : held.contains('player')
                        ? _heroPosition(strings, row)
                        : _leadTitleLabel(strings, row);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                          ),
                        ),
                        if (roleLine.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              roleLine,
                              key: const ValueKey('person-profile-roles'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: white,
                              ),
                            ),
                          ),
                        const SizedBox(height: 10),
                        _HeroLine(
                          icon: Icons.shield_outlined,
                          text: [
                            if (clubName.isNotEmpty) clubName,
                            person.teamName,
                          ].join(' · '),
                        ),
                        if (position != null)
                          _HeroLine(icon: Icons.directions_run, text: position),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The main position, else the first one chosen.
String? _heroPosition(AppStrings strings, TeamRole role) {
  final key =
      role.mainPosition ??
      role.positions.firstOrNull ??
      role.customPositions.firstOrNull;
  return key == null ? null : _anyPositionLabel(strings, key);
}

/// The picture filling the card's left side and fading into it; initials
/// in a soft circle without one.
class _HeroPicture extends StatelessWidget {
  const _HeroPicture({required this.name, this.url});
  final String name;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final initials = Center(
      child: CircleAvatar(
        radius: 40,
        backgroundColor: Colors.white.withValues(alpha: .18),
        child: Text(
          _initialsOf(name.isEmpty ? '?' : name),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
    return KeyedSubtree(
      key: const ValueKey('person-profile-avatar'),
      child: url == null
          ? initials
          : ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) => const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                stops: [.6, 1],
                colors: [Colors.black, Colors.transparent],
              ).createShader(rect),
              child: Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => initials,
              ),
            ),
    );
  }
}

class _HeroLine extends StatelessWidget {
  const _HeroLine({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Colors.white.withValues(alpha: .85);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// A soft accent button under the heading, half the row wide.
class _ProfileActionButton extends StatelessWidget {
  const _ProfileActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        backgroundColor: palette.accentSoft,
        foregroundColor: palette.accent,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        textStyle: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      icon: Icon(icon, size: 20),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

/// A heading between the overview's sections, with an optional link.
class _ProfileSectionHeading extends StatelessWidget {
  const _ProfileSectionHeading({
    required this.title,
    this.action,
    this.onAction,
  });
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 0, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: AppPalette.of(context).muted,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(action!),
                const Icon(Icons.chevron_right, size: 18),
              ],
            ),
          ),
      ],
    ),
  );
}

/// A figure in the overview's grid: an icon and label over a large value.
class _ProfileStatCard extends StatelessWidget {
  const _ProfileStatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label, value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: palette.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: palette.muted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              maxLines: 1,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The overview's figures: matches, goals and assists in a row of three,
/// then training attendance and callup answers in a row of two.
class _ProfileStatGrid extends StatelessWidget {
  const _ProfileStatGrid({required this.stats});
  final PersonStatistics stats;

  static String _rate(int part, int total) =>
      total == 0 ? '–' : '${(part * 100 / total).round()} %';

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    Widget row(List<Widget> cards) => IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, card) in cards.indexed) ...[
            if (index > 0) const SizedBox(width: 8),
            Expanded(child: card),
          ],
        ],
      ),
    );
    return Column(
      key: const ValueKey('person-profile-stats'),
      children: [
        row([
          _ProfileStatCard(
            icon: Icons.sports_soccer_outlined,
            label: strings.feature('Matcher'),
            value: '${stats.matchesPlayed}',
          ),
          _ProfileStatCard(
            key: const ValueKey('profile-stat-goals'),
            icon: Icons.sports_score_outlined,
            label: strings.feature('Mål'),
            value: '${stats.goals}',
          ),
          _ProfileStatCard(
            icon: Icons.handshake_outlined,
            label: strings.feature('Assist'),
            value: '${stats.assists}',
          ),
        ]),
        const SizedBox(height: 8),
        row([
          _ProfileStatCard(
            icon: Icons.fitness_center_outlined,
            label: strings.feature('Träningsnärvaro'),
            value: _rate(stats.trainingsAttended, stats.trainingsTotal),
          ),
          _ProfileStatCard(
            icon: Icons.how_to_reg_outlined,
            label: strings.feature('Svar på kallelser'),
            value: _rate(stats.callupsAnswered, stats.callupsReceived),
          ),
        ]),
      ],
    );
  }
}
