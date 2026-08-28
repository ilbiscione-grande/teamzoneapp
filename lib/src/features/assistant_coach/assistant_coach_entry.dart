part of '../../app/teamzone_app.dart';

const _assistantHoldingTitle = 'Assistant Coach';
const _assistantHoldingMessage =
    'Assistant Coach förbereds. Förslag visas först när lagets data och '
    'behörigheter har verifierats.';
const _assistantTransparencyPoints = <String>[
  'Visar alltid vilken källa och tidpunkt ett förslag bygger på.',
  'Öppnar rätt TeamZone-vy; ändringar kräver att du själv bekräftar dem.',
  'Använder inga dolda riskpoäng, medicinska slutsatser eller personjämförelser.',
  'Avfärdade förslag kan visas och återställas utan att Inbox-historik ändras.',
];

class _AssistantCoachMobileFab extends StatelessWidget {
  const _AssistantCoachMobileFab({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Öppna Assistant Coach',
    child: FloatingActionButton(
      key: const Key('assistant-coach-mobile-fab'),
      tooltip: 'Assistant Coach',
      onPressed: onPressed,
      child: const Icon(Icons.assistant_outlined),
    ),
  );
}

class _AssistantCoachSidePanel extends StatelessWidget {
  const _AssistantCoachSidePanel({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const Key('assistant-coach-side-panel'),
    width: 288,
    child: DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        minimum: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.assistant_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _assistantHoldingTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _assistantHoldingMessage,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                key: const Key('assistant-coach-panel-open'),
                onPressed: onOpen,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Öppna information'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _AssistantCoachHoldingSurface extends StatelessWidget {
  const _AssistantCoachHoldingSurface();

  @override
  Widget build(BuildContext context) => FocusTraversalGroup(
    child: Scaffold(
      key: const Key('assistant-coach-holding-surface'),
      appBar: AppBar(
        leading: BackButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(ProductRouteContract.home);
            }
          },
        ),
        title: const Text(_assistantHoldingTitle),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Semantics(
            liveRegion: true,
            child: const Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.assistant_outlined, size: 48),
                  SizedBox(height: 16),
                  Text(
                    _assistantHoldingTitle,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 12),
                  Text(_assistantHoldingMessage, textAlign: TextAlign.center),
                  SizedBox(height: 12),
                  Text(
                    'Ingen analys körs och inga automatiska åtgärder utförs.',
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 20),
                  _AssistantTransparencyList(),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _AssistantTransparencyList extends StatelessWidget {
  const _AssistantTransparencyList();

  @override
  Widget build(BuildContext context) => Column(
    key: const Key('assistant-coach-transparency-contract'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final point in _assistantTransparencyPoints)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.check_circle_outline, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(point)),
            ],
          ),
        ),
    ],
  );
}
