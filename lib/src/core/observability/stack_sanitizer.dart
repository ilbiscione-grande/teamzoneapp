/// Crash stack traces reduced to code locations only (PAR-OPS-05, decided
/// 2026-10-13): function name, file and line. Messages and values are never
/// part of a frame here, absolute paths are cut to the file name, and a line
/// that is not recognisably a code location is dropped.
///
/// Used only for fatal (unhandled) errors; handled failures send no stack.
abstract final class StackSanitizer {
  /// Off with --dart-define=TEAMZONE_CRASH_STACKS=false: reports then fall
  /// back to the error type alone.
  static const enabled = bool.fromEnvironment(
    'TEAMZONE_CRASH_STACKS',
    defaultValue: true,
  );

  static const maxFrames = 30;
  static const _maxMember = 120;

  // Dart VM / Flutter: "#3      _State._save (package:app/x.dart:12:5)"
  static final _dartFrame = RegExp(
    r'^#\d+\s+(.+?)\s+\((.+?):(\d+)(?::(\d+))?\)$',
  );
  // Chrome/V8 (web): "    at Object.c (https://host/main.dart.js:9:7)"
  static final _jsFrame = RegExp(
    r'^\s*at\s+(?:(.+?)\s+\()?(.+?):(\d+):(\d+)\)?$',
  );
  // Identifiers only; the one space allowed is in Dart's own
  // "<anonymous closure>" and after "new " for constructors.
  static final _member = RegExp(r'^(?:new )?[A-Za-z0-9_$.<>\-]+$');
  static final _fileName = RegExp(r'^[A-Za-z0-9_.\-]+\.(?:dart|js|mjs)$');
  static final _packageUri = RegExp(
    r'^(?:package:[a-z0-9_]+(?:/[A-Za-z0-9_.\-]+)+\.dart|dart:[a-z_]+(?:/[A-Za-z0-9_.\-]+)*(?:\.dart)?)$',
  );

  /// The sanitized frames, one per line, or an empty string when nothing
  /// passes (or stacks are disabled).
  static String sanitize(StackTrace? stack) {
    if (!enabled || stack == null) return '';
    final frames = <String>[];
    for (final line in stack.toString().split('\n')) {
      final frame = sanitizeFrame(line.trimRight());
      if (frame == null) continue;
      frames.add('#${frames.length} $frame');
      if (frames.length == maxFrames) break;
    }
    return frames.join('\n');
  }

  /// "member (location:line:column)" for a recognised frame, else null.
  static String? sanitizeFrame(String line) {
    final dart = _dartFrame.firstMatch(line);
    final js = dart == null ? _jsFrame.firstMatch(line) : null;
    final match = dart ?? js;
    if (match == null) return null;
    final member = (match.group(1) ?? '<anonymous>').trim();
    final identifier = member.replaceAll('<anonymous closure>', '<closure>');
    if (member.length > _maxMember || !_member.hasMatch(identifier)) {
      return null;
    }
    final location = _location(match.group(2)!);
    if (location == null) return null;
    final lineNo = match.group(3)!;
    final column = match.group(4);
    return '$member ($location:$lineNo${column == null ? '' : ':$column'})';
  }

  /// package:/dart: URIs as they are; anything else (file paths, URLs) cut
  /// to a plain .dart/.js file name.
  static String? _location(String raw) {
    final value = raw.trim();
    if (_packageUri.hasMatch(value)) return value;
    final name = value.split(RegExp(r'[/\\]')).last.split('?').first;
    return _fileName.hasMatch(name) ? name : null;
  }
}
