import 'package:flutter/material.dart';

const assistantTaskTypes = <String, String>{
  'personal_calendar_conflict': 'Mina personliga kalenderkrockar',
  'calendar_conflict': 'Kalenderkrockar inom laget',
  'pending_callups': 'Obesvarade kallelser och påminnelser',
  'missing_callups': 'Kallelser som behöver skickas',
  'missing_attendance': 'Närvaro som behöver registreras',
  'missing_match_result': 'Matchresultat som saknas',
  'missing_match_report': 'Matchrapporter som saknas',
  'unfinished_preparation': 'Återstående förberedelser',
};

class AssistantTaskPreferences {
  const AssistantTaskPreferences({
    this.hiddenKinds = const {},
    this.revision = 0,
    this.currentTeamOnly = false,
  });
  factory AssistantTaskPreferences.fromJson(Map<String, dynamic> json) =>
      AssistantTaskPreferences(
        hiddenKinds: (json['hidden_kinds'] as List).cast<String>().toSet(),
        revision: (json['revision'] as num).toInt(),
        currentTeamOnly: json['current_team_only'] == true,
      );
  final Set<String> hiddenKinds;
  final int revision;
  final bool currentTeamOnly;
  bool shows(String kind) => !hiddenKinds.contains(kind);
}

abstract interface class AssistantTaskPreferencesServices {
  Future<AssistantTaskPreferences> loadAssistantTaskPreferences();
  Future<AssistantTaskPreferences> saveAssistantTaskPreferences(
    Set<String> hiddenKinds,
    int expectedRevision, {
    bool currentTeamOnly = false,
  });
}

class AssistantTaskVisibilitySettings extends StatefulWidget {
  const AssistantTaskVisibilitySettings({super.key, required this.services});
  final AssistantTaskPreferencesServices services;
  @override
  State<AssistantTaskVisibilitySettings> createState() =>
      _AssistantTaskVisibilitySettingsState();
}

class _AssistantTaskVisibilitySettingsState
    extends State<AssistantTaskVisibilitySettings> {
  AssistantTaskPreferences? _saved;
  Set<String> _hidden = {};
  bool _loading = true, _saving = false;
  bool _currentTeamOnly = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final value = await widget.services.loadAssistantTaskPreferences();
      if (mounted) {
        setState(() {
          _saved = value;
          _hidden = {...value.hiddenKinds};
          _currentTeamOnly = value.currentTeamOnly;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Inställningarna kunde inte hämtas. Försök igen.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving || _saved == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final value = await widget.services.saveAssistantTaskPreferences(
        {..._hidden},
        _saved!.revision,
        currentTeamOnly: _currentTeamOnly,
      );
      if (!mounted) return;
      setState(() {
        _saved = value;
        _hidden = {...value.hiddenKinds};
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dina visningsinställningar är sparade.')),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Kunde inte spara. Försök igen, eller hämta aktuella inställningar om de har ändrats på en annan enhet.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: LinearProgressIndicator(),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Visa i min assistent',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Dina val följer kontot mellan enheter och gäller även räknaren på assistentknappen. Du ser bara uppgifter du har behörighet till.',
        ),
        if (_saved != null) ...[
          const SizedBox(height: 24),
          Text(
            'Visa uppgifter från',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Alla mina lag')),
              ButtonSegment(value: true, label: Text('Aktuellt lag')),
            ],
            selected: {_currentTeamOnly},
            onSelectionChanged: _saving
                ? null
                : (selection) =>
                      setState(() => _currentTeamOnly = selection.single),
          ),
          const SizedBox(height: 12),
          const Text(
            'Aktuellt lag följer ditt lagval i appen. Personliga kalenderkrockar visas när det valda laget ingår.',
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Divider(),
          ),
          Text(
            'Typer av uppgifter',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (final entry in assistantTaskTypes.entries)
            SwitchListTile(
              key: ValueKey('assistant-visible-${entry.key}'),
              contentPadding: EdgeInsets.zero,
              title: Text(entry.value),
              value: !_hidden.contains(entry.key),
              onChanged: _saving
                  ? null
                  : (visible) => setState(() {
                      if (visible) {
                        _hidden.remove(entry.key);
                      } else {
                        _hidden.add(entry.key);
                      }
                    }),
            ),
          if (_hidden.length == assistantTaskTypes.length)
            const Text(
              'Alla uppgiftstyper är avstängda. Assistentknappen finns kvar så att du kan aktivera dem igen.',
            ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Sparar…' : 'Spara visningsinställningar'),
          ),
        ],
        if (_error != null) ...[
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          TextButton(
            onPressed: _saving ? null : _load,
            child: const Text('Hämta inställningarna igen'),
          ),
        ],
      ],
    );
  }
}
