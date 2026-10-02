import 'package:flutter/material.dart';
import '../calendar/calendar_models.dart';
import '../calendar/preparation_models.dart';
import '../calendar/preparation_services.dart';

/// Loaded only for the expanded card, through the ordinary event permissions.
class AssistantPreparationChecklist extends StatefulWidget {
  const AssistantPreparationChecklist({
    super.key,
    required this.eventId,
    required this.services,
    required this.loadEvent,
    required this.allowEdit,
    required this.onChanged,
  });

  final String eventId;
  final EventPreparationServices services;
  final Future<EventDetails> Function(String) loadEvent;
  final bool allowEdit;
  final VoidCallback onChanged;

  @override
  State<AssistantPreparationChecklist> createState() =>
      _AssistantPreparationChecklistState();
}

class _AssistantPreparationChecklistState
    extends State<AssistantPreparationChecklist> {
  late Future<(EventDetails, EventPreparation)> _data;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<(EventDetails, EventPreparation)> _load() async {
    final event = await widget.loadEvent(widget.eventId);
    final preparation = await widget.services.getPreparation(widget.eventId);
    if (preparation.eventId != widget.eventId) {
      throw const FormatException('Unexpected preparation event');
    }
    return (event, preparation);
  }

  Future<void> _complete(PreparationItem item) async {
    if (_saving || !widget.allowEdit) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // Explicit desired state makes a retry safe after a lost response.
      await widget.services.setItemDone(item.id, true);
      if (!mounted) return;
      widget.onChanged();
      if (mounted) setState(() => _data = _load());
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Punkten kunde inte sparas. Uppdatera och försök igen.';
          _data = _load();
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<(EventDetails, EventPreparation)>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.all(12),
              child: LinearProgressIndicator(),
            );
          }
          if (snapshot.hasError) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Förberedelserna kunde inte hämtas.'),
                TextButton(
                  onPressed: () => setState(() => _data = _load()),
                  child: const Text('Försök igen'),
                ),
              ],
            );
          }
          final (event, preparation) = snapshot.requireData;
          final editable =
              widget.allowEdit &&
              preparation.permissions.logistics &&
              event.state == 'scheduled' &&
              event.archivedAt == null;
          final items = [
            if (event.type == 'match' || event.type == 'training')
              ...preparation.itemsOf(PreparationKind.material),
            ...preparation.itemsOf(PreparationKind.task),
          ].where((item) => !item.done).toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Återstående punkter',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (_error != null) Text(_error!),
              if (!editable) const Text('Förberedelserna är skrivskyddade.'),
              if (items.isEmpty)
                const Text('Inga återstående punkter i checklistan.'),
              for (final item in items)
                CheckboxListTile(
                  key: ValueKey('assistant-preparation-${item.id}'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(item.label),
                  subtitle: Text(
                    [
                      item.kind == PreparationKind.material
                          ? 'Material'
                          : 'Uppgift',
                      if (item.assigneeName != null) item.assigneeName!,
                    ].join(' · '),
                  ),
                  value: false,
                  onChanged: editable && !_saving
                      ? (_) => _complete(item)
                      : null,
                ),
              if (_saving) const LinearProgressIndicator(),
              const SizedBox(height: 8),
            ],
          );
        },
      );
}
