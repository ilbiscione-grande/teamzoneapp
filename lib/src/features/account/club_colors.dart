part of '../../app/teamzone_app.dart';

/// PUB-08: the club's colours on its public club and team pages. Club
/// administrators pick a primary colour (header, hero, dark surfaces) and an
/// accent (buttons and highlights); the page keeps text readable itself.
class _ClubColorsDialog extends StatefulWidget {
  const _ClubColorsDialog({
    required this.profile,
    required this.clubId,
    required this.clubName,
  });
  final ProfileServices profile;
  final String clubId, clubName;
  @override
  State<_ClubColorsDialog> createState() => _ClubColorsDialogState();
}

class _ClubColorsDialogState extends State<_ClubColorsDialog> {
  static const _primaryPresets = [
    '#111111',
    '#0b1f3a',
    '#1d4ed8',
    '#6cb4ee',
    '#00843d',
    '#0a3d2a',
    '#c8102e',
    '#7a1f2b',
    '#5b2a86',
    '#e35205',
  ];
  static const _accentPresets = [
    '#ffd100',
    '#ffffff',
    '#c6f04d',
    '#c9a227',
    '#e4002b',
    '#6cb4ee',
    '#ff7a00',
    '#2bd47d',
  ];
  static final _hex = RegExp(r'^#?[0-9a-fA-F]{6}$');

  final _primary = TextEditingController();
  final _accent = TextEditingController();
  late final Future<void> _load = _loadColors();
  bool _busy = false;
  String? _error;

  Future<void> _loadColors() async {
    final colors = await widget.profile.getClubColors(widget.clubId);
    _primary.text = colors.primary ?? '';
    _accent.text = colors.accent ?? '';
  }

  @override
  void initState() {
    super.initState();
    _primary.addListener(_changed);
    _accent.addListener(_changed);
  }

  void _changed() => setState(() => _error = null);

  @override
  void dispose() {
    _primary.dispose();
    _accent.dispose();
    super.dispose();
  }

  /// '#rrggbb' from the field, or null when empty or not a colour.
  String? _value(TextEditingController field) {
    final text = field.text.trim();
    if (!_hex.hasMatch(text)) return null;
    return '#${text.replaceFirst('#', '').toLowerCase()}';
  }

  bool _invalid(TextEditingController field) =>
      field.text.trim().isNotEmpty && _value(field) == null;

  static Color _color(String hex) =>
      Color(int.parse('ff${hex.substring(1)}', radix: 16));

  Future<void> _save({bool reset = false}) async {
    final strings = AppStrings.of(context);
    if (!reset && (_invalid(_primary) || _invalid(_accent))) {
      setState(
        () => _error = strings.feature('Ange färgerna som #rrggbb, t.ex. #00843d.'),
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.profile.setClubColors(
        clubId: widget.clubId,
        primary: reset ? null : _value(_primary),
        accent: reset ? null : _value(_accent),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = strings.feature('Färgerna kunde inte sparas. Försök igen.');
        });
      }
    }
  }

  Widget _swatches(
    TextEditingController field,
    List<String> presets,
    String keyPrefix,
  ) {
    final selected = _value(field);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final hex in presets)
          Tooltip(
            message: hex,
            child: InkWell(
              key: ValueKey('$keyPrefix-$hex'),
              customBorder: const CircleBorder(),
              onTap: _busy ? null : () => field.text = hex,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _color(hex),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected == hex
                        ? Theme.of(context).colorScheme.primary
                        : Colors.black26,
                    width: selected == hex ? 3 : 1,
                  ),
                ),
                child: selected == hex
                    ? Icon(
                        Icons.check,
                        size: 18,
                        color: _color(hex).computeLuminance() > .5
                            ? Colors.black
                            : Colors.white,
                      )
                    : null,
              ),
            ),
          ),
      ],
    );
  }

  Widget _field(TextEditingController field, String label, String key) {
    final value = _value(field);
    return TextField(
      key: ValueKey(key),
      controller: field,
      enabled: !_busy,
      decoration: InputDecoration(
        labelText: label,
        hintText: '#rrggbb',
        errorText: _invalid(field)
            ? AppStrings.of(context).feature('Ogiltig färg')
            : null,
        prefixIcon: Padding(
          padding: const EdgeInsets.all(12),
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: value == null ? Colors.transparent : _color(value),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black26),
            ),
          ),
        ),
      ),
    );
  }

  Widget _preview() {
    final strings = AppStrings.of(context);
    var primary = _color(_value(_primary) ?? '#0b111c');
    // The page darkens light primaries; the preview does the same.
    while (primary.computeLuminance() > .06) {
      primary = Color.lerp(primary, Colors.black, .1)!;
    }
    final accent = _color(_value(_accent) ?? '#c6f04d');
    final accentText = accent.computeLuminance() < .18 ? Colors.white : accent;
    return ClipRRect(
      key: const ValueKey('club-colors-preview'),
      borderRadius: BorderRadius.circular(8),
      child: ColoredBox(
        color: primary,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.feature('Klubbsida').toUpperCase(),
                style: TextStyle(
                  color: accentText,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.6,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.clubName.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: Text(
                    strings.feature('Följ klubben').toUpperCase(),
                    style: TextStyle(
                      color: accent.computeLuminance() > .4
                          ? const Color(0xff0b111c)
                          : Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(strings.feature('Klubbens färger')),
      content: SizedBox(
        width: 420,
        child: FutureBuilder<void>(
          future: _load,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return Text(
                strings.feature(
                  'Färgerna kunde inte hämtas. Bara klubbens administratörer kan ändra dem.',
                ),
              );
            }
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    strings.feature(
                      'Används på klubbens publika klubb- och lagsidor. Ljusa huvudfärger mörkas automatiskt så att texten går att läsa.',
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  _preview(),
                  const SizedBox(height: 20),
                  Text(
                    strings.feature('Huvudfärg'),
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  _swatches(_primary, _primaryPresets, 'club-primary'),
                  const SizedBox(height: 10),
                  _field(
                    _primary,
                    strings.feature('Huvudfärg'),
                    'club-primary-hex',
                  ),
                  const SizedBox(height: 20),
                  Text(
                    strings.feature('Accentfärg'),
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  _swatches(_accent, _accentPresets, 'club-accent'),
                  const SizedBox(height: 10),
                  _field(
                    _accent,
                    strings.feature('Accentfärg'),
                    'club-accent-hex',
                  ),
                  if (_busy) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                  ],
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('club-colors-reset'),
          onPressed: _busy ? null : () => _save(reset: true),
          child: Text(strings.feature('Återställ')),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: Text(strings.feature('Avbryt')),
        ),
        FilledButton(
          key: const ValueKey('club-colors-save'),
          onPressed: _busy ? null : _save,
          child: Text(strings.save),
        ),
      ],
    );
  }
}
