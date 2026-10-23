part of '../../app/teamzone_app.dart';

class _MatchRow extends StatelessWidget {
  const _MatchRow({required this.match, required this.onTap});
  final ModuleMatch match;
  final VoidCallback onTap;

  static String _status(String value) => switch (value) {
    'published' => 'Publicerad',
    'draft' => 'Utkast',
    _ => 'Saknas',
  };

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final date = MaterialLocalizations.of(
      context,
    ).formatMediumDate(match.startsAt);
    final time = TimeOfDay.fromDateTime(match.startsAt).format(context);
    final place = switch (match.homeAway) {
      'home' => strings.feature('Hemma'),
      'away' => strings.feature('Borta'),
      _ => null,
    };
    return ListTile(
      key: Key('module-match-${match.eventId}'),
      leading: const Icon(Icons.sports_soccer_outlined),
      title: Text(
        match.opponentName?.isNotEmpty == true
            ? '${strings.feature('Mot')} ${match.opponentName}'
            : match.title,
      ),
      subtitle: Text(
        [
          '$date $time',
          ?place,
          if (match.state == 'cancelled') strings.feature('Inställd'),
          '${strings.feature('Matchplan')}: ${strings.feature(_status(match.plan))}',
          '${strings.feature('Uppställning')}: ${strings.feature(_status(match.lineup))}',
        ].join(' · '),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
