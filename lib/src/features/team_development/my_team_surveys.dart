part of '../../app/teamzone_app.dart';

/// The home page's invitation: the signed-in person's own surveys that are
/// open and not answered yet, each opening its page on Webtools. Nothing
/// shows when there is none. Read again when the app comes back to the
/// front, so an answered survey goes away.
class _MySurveysCard extends StatefulWidget {
  const _MySurveysCard();

  @override
  State<_MySurveysCard> createState() => _MySurveysCardState();
}

class _MySurveysCardState extends State<_MySurveysCard>
    with WidgetsBindingObserver {
  late Future<List<MySurvey>> _load = _read();

  Future<List<MySurvey>> _read() async {
    try {
      return await TeamSurveysFeature.services.mine();
    } catch (error) {
      AppErrors.caught('my_team_surveys.list', error);
      return const [];
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() => _load = _read());
    }
  }

  Future<void> _open(MySurvey survey) async {
    try {
      await launchUrl(
        Uri.parse(survey.url),
        mode: LaunchMode.externalApplication,
      );
    } catch (error) {
      AppErrors.caught('my_team_surveys.open', error);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<MySurvey>>(
    future: _load,
    builder: (context, snapshot) {
      final waiting = [
        for (final survey in snapshot.data ?? const <MySurvey>[])
          if (survey.answeredAt == null) survey,
      ];
      if (waiting.isEmpty) return const SizedBox.shrink();
      final theme = Theme.of(context);
      return Card(
        key: const Key('home-my-surveys'),
        color: theme.colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final survey in waiting)
                ListTile(
                  key: Key('home-survey-${survey.surveyId}'),
                  leading: const Icon(Icons.quiz_outlined),
                  title: Text(survey.title),
                  subtitle: Text(
                    _tdpText(
                      context,
                      'Ledarna i ${survey.teamName} vill att du svarar på en enkät',
                      'Your coaches in ${survey.teamName} ask you to answer a survey',
                    ),
                  ),
                  trailing: FilledButton(
                    onPressed: () => _open(survey),
                    child: Text(_tdpText(context, 'Svara', 'Answer')),
                  ),
                  onTap: () => _open(survey),
                ),
            ],
          ),
        ),
      );
    },
  );
}
