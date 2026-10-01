part of '../../app/teamzone_app.dart';

class _TeamEventVisibilitySurface extends StatefulWidget {
  const _TeamEventVisibilitySurface({
    required this.teamId,
    required this.teamName,
    required this.editorial,
  });
  final String teamId, teamName;
  final EditorialServices editorial;
  @override
  State<_TeamEventVisibilitySurface> createState() =>
      _TeamEventVisibilitySurfaceState();
}

class _TeamEventVisibilitySurfaceState
    extends State<_TeamEventVisibilitySurface> {
  bool? _results, _training, _matches;
  int _revision = 0;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await widget.editorial.getTeamEventVisibility(widget.teamId);
      if (!mounted) return;
      setState(() {
        _results = data['show_results'] == true;
        _training = data['show_training'] == true;
        _matches = data['show_matches'] == true;
        _revision = (data['revision'] as num).toInt();
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Laginställningarna kunde inte laddas. Försök igen.',
        );
      }
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.editorial.setTeamEventVisibility(
        teamId: widget.teamId,
        showResults: _results!,
        showTraining: _training!,
        showMatches: _matches!,
        expectedRevision: _revision,
      );
      await _load();
      if (mounted && _error == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lagets publiceringsinställningar är sparade.'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Ändringen kunde inte bekräftas. Läs in inställningarna igen innan du försöker på nytt.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Laginställningar · ${widget.teamName}')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Lagets publika sida',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Text(
          'Gäller hela laget, både befintliga och nya händelser. Informationen kan läsas utan inloggning när klubbens och lagets sidor är publicerade.',
        ),
        if (_results != null) ...[
          SwitchListTile(
            title: const Text('Visa matcher'),
            subtitle: const Text(
              'Alla lagets matcher visas, både kommande och spelade, med motståndare och tid. Platsen visas bara om den publiceras för en enskild match. En match som görs privat i redaktionen döljs.',
            ),
            value: _matches!,
            onChanged: _busy ? null : (v) => setState(() => _matches = v),
          ),
          SwitchListTile(
            title: const Text('Visa matchresultat'),
            subtitle: const Text(
              'Slutresultat visas automatiskt efter avslutad match, även i följarnas flöde. Avstängt döljer lagets resultat.',
            ),
            value: _results!,
            onChanged: _busy ? null : (v) => setState(() => _results = v),
          ),
          SwitchListTile(
            title: const Text('Visa träningstider'),
            subtitle: const Text(
              'Lagets träningstider visas automatiskt. Avstängt döljer träningarna på den publika sidan.',
            ),
            value: _training!,
            onChanged: _busy ? null : (v) => setState(() => _training = v),
          ),
          FilledButton(
            onPressed: _busy || _error != null ? null : _save,
            child: Text(_busy ? 'Sparar…' : 'Spara laginställningar'),
          ),
        ] else if (_error == null)
          const Center(child: CircularProgressIndicator()),
        if (_error != null) ...[
          Text(_error!),
          TextButton(
            onPressed: _busy ? null : _load,
            child: const Text('Läs in igen'),
          ),
        ],
      ],
    ),
  );
}
