import 'dart:io';

void main() {
  final path = 'lib/src/app/teamzone_app.dart';
  final file = File(path);
  var source = file.readAsStringSync();
  final stringsSource = File(
    'lib/src/core/localization/app_strings.dart',
  ).readAsStringSync();
  final matches = RegExp(
    r"^    '([^']+)':",
    multiLine: true,
  ).allMatches(stringsSource).map((match) => match.group(1)!).toSet();

  for (final value in matches) {
    final escaped = RegExp.escape(value);
    source = source.replaceAllMapped(
      RegExp("const Text\\('$escaped'\\)"),
      (_) => "Text(AppStrings.of(context).feature('$value'))",
    );
    source = source.replaceAllMapped(
      RegExp("(?<!const )Text\\('$escaped'\\)"),
      (_) => "Text(AppStrings.of(context).feature('$value'))",
    );
    for (final field in ['title', 'message', 'tooltip', 'labelText']) {
      source = source.replaceAll(
        "$field: '$value'",
        "$field: AppStrings.of(context).feature('$value')",
      );
    }
  }

  source = source
      .replaceAll('const InputDecoration(', 'InputDecoration(')
      .replaceAll('const SnackBar(', 'SnackBar(')
      .replaceAll('const ListTile(', 'ListTile(');
  file.writeAsStringSync(source);
}
