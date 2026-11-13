/// A Swedish genitive of a name: "Annas", "Lars", "A:s", "P2014:s", "IFK:s".
///
/// A name ending in s, x or z takes nothing; one ending in a digit or in
/// an abbreviation in capitals takes a colon before the s.
String swedishGenitive(String name) {
  final trimmed = name.trimRight();
  if (trimmed.isEmpty) return trimmed;
  final last = trimmed[trimmed.length - 1];
  if (RegExp(r'[0-9]').hasMatch(last)) return '$trimmed:s';
  final word = trimmed.split(RegExp(r'\s+')).last;
  if (word.length <= 4 &&
      word == word.toUpperCase() &&
      word != word.toLowerCase()) {
    return '$trimmed:s';
  }
  if ('sxzSXZ'.contains(last)) return trimmed;
  return '${trimmed}s';
}
