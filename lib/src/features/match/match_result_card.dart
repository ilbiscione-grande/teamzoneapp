part of '../../app/teamzone_app.dart';

class _RegisterResultDialog extends StatefulWidget {
  const _RegisterResultDialog({
    required this.event,
    required this.match,
    required this.snapshot,
    this.contextLabel,
  });
  final EventDetails event;
  final MatchServices match;
  final MatchSnapshot? snapshot;
  final String? contextLabel;
  @override
  State<_RegisterResultDialog> createState() => _RegisterResultDialogState();
}

class _RegisterResultDialogState extends State<_RegisterResultDialog> {
  final _form = GlobalKey<FormState>();
  late String _us = '${widget.snapshot?.scoreUs ?? 0}';
  late String _opponent = '${widget.snapshot?.scoreOpponent ?? 0}';
  String _reason = '';
  bool _busy = false;
  String? _error;
  String? _commandId;
  String? _submittedPayload;
  bool get _correction =>
      widget.snapshot?.state == 'completed' ||
      widget.event.state == 'completed';

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    final us = int.parse(_us.trim()), opponent = int.parse(_opponent.trim());
    final payload = '$us/$opponent/${_reason.trim()}';
    // Reuse the same key after an uncertain response; changed input is a new command.
    if (_submittedPayload != payload) {
      _commandId = _newUuid();
      _submittedPayload = payload;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.match.registerResult(
        _commandId!,
        widget.event.id,
        expectedRevision: widget.snapshot?.revision ?? 0,
        expectedEventRevision: widget.event.revision,
        scoreUs: us,
        scoreOpponent: opponent,
        reason: _reason.trim().isEmpty ? null : _reason.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error =
              'Kunde inte bekräfta sparandet. Försök igen med samma resultat. '
              'Om matchen har ändrats, stäng dialogen och öppna matchen igen.';
        });
      }
    }
  }

  String? _validateScore(String? value) {
    final number = int.tryParse(value?.trim() ?? '');
    return number == null || number < 0 || number > 999
        ? 'Ange ett heltal mellan 0 och 999'
        : null;
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(
        _correction ? 'Ändra slutresultat' : 'Registrera slutresultat',
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.contextLabel != null) ...[
                  Text(widget.contextLabel!),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  initialValue: _us,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Vårt lag'),
                  validator: _validateScore,
                  onChanged: (v) => _us = v,
                ),
                TextFormField(
                  initialValue: _opponent,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: widget.event.opponentName ?? 'Motståndare',
                  ),
                  validator: _validateScore,
                  onChanged: (v) => _opponent = v,
                ),
                if (_correction)
                  TextFormField(
                    enabled: !_busy,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      labelText: 'Anledning till rättelsen',
                    ),
                    onChanged: (v) => _reason = v,
                    validator: (v) => (v?.trim().length ?? 0) < 3
                        ? 'Ange en kort anledning'
                        : null,
                  ),
                const SizedBox(height: 12),
                const Text(
                  'Matchen markeras som avslutad. Tidigare matchhändelser behålls.',
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Avbryt'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(
            _busy
                ? 'Sparar…'
                : _correction
                ? 'Spara rättelse'
                : 'Spara och avsluta match',
          ),
        ),
      ],
    ),
  );
}
