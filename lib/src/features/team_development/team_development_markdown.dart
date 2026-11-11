part of '../../app/teamzone_app.dart';

/// A free text of the plan (focus, vision, descriptions, notes) shown as
/// Markdown (2026-11-11): **fet**, *kursiv*, ~~struken~~, lists, headings
/// and links. Plain text shows as before. Links open outside the app.
class _TdpRichText extends StatelessWidget {
  const _TdpRichText(this.text, {super.key, this.style});
  final String text;

  /// The base style, as a [Text] would take it.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = style ?? DefaultTextStyle.of(context).style;
    return MarkdownBody(
      data: text,
      softLineBreak: true,
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: base,
        listBullet: base,
        h1: theme.textTheme.titleMedium,
        h2: theme.textTheme.titleSmall,
        h3: theme.textTheme.labelLarge,
        a: base.copyWith(
          color: theme.colorScheme.primary,
          decoration: TextDecoration.underline,
        ),
      ),
      onTapLink: (_, href, _) {
        final uri = href == null ? null : Uri.tryParse(href);
        if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
          unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
        }
      },
    );
  }
}

/// [text] without its Markdown marks, for a short preview on few lines.
String _tdpPlain(String text) => text
    .replaceAll(
      RegExp(r'^\s{0,3}(#{1,6}\s+|[-*+]\s+|\d+\.\s+|>\s?)', multiLine: true),
      '',
    )
    .replaceAllMapped(
      RegExp(r'(\*\*|__|~~|\*|_)(?=\S)(.+?)(?<=\S)\1'),
      (match) => match[2]!,
    )
    .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (match) => match[1]!);

/// Buttons above a text field for Markdown: bold, italic, a list item and
/// a heading, around the selection or at the cursor.
class _TdpFormatBar extends StatelessWidget {
  const _TdpFormatBar({required this.controller});
  final TextEditingController controller;

  /// Wraps the selection in [mark] (or puts an empty pair at the cursor).
  void _wrap(String mark) {
    final value = controller.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    final picked = selection.textInside(value.text);
    final text = value.text.replaceRange(
      selection.start,
      selection.end,
      '$mark$picked$mark',
    );
    controller.value = TextEditingValue(
      text: text,
      selection: picked.isEmpty
          ? TextSelection.collapsed(offset: selection.start + mark.length)
          : TextSelection(
              baseOffset: selection.start + mark.length,
              extentOffset: selection.end + mark.length,
            ),
    );
  }

  /// Starts the selection's line with [prefix], or takes it away.
  void _line(String prefix) {
    final value = controller.value;
    final at = value.selection.isValid
        ? value.selection.start
        : value.text.length;
    final start = value.text.lastIndexOf('\n', at - 1) + 1;
    final has = value.text.startsWith(prefix, start);
    final text = has
        ? value.text.replaceRange(start, start + prefix.length, '')
        : value.text.replaceRange(start, start, prefix);
    final moved = (at + (has ? -prefix.length : prefix.length)).clamp(
      0,
      text.length,
    );
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: moved),
    );
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 2,
    children: [
      IconButton(
        key: const Key('tdp-format-bold'),
        tooltip: _tdpText(context, 'Fet', 'Bold'),
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.format_bold),
        onPressed: () => _wrap('**'),
      ),
      IconButton(
        key: const Key('tdp-format-italic'),
        tooltip: _tdpText(context, 'Kursiv', 'Italic'),
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.format_italic),
        onPressed: () => _wrap('*'),
      ),
      IconButton(
        key: const Key('tdp-format-list'),
        tooltip: _tdpText(context, 'Punktlista', 'Bulleted list'),
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.format_list_bulleted),
        onPressed: () => _line('- '),
      ),
      IconButton(
        key: const Key('tdp-format-heading'),
        tooltip: _tdpText(context, 'Rubrik', 'Heading'),
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.title),
        onPressed: () => _line('### '),
      ),
    ],
  );
}
