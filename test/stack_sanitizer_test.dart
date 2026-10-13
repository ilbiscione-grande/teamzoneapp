import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/core/observability/stack_sanitizer.dart';

void main() {
  test('Dart frames keep only function, package file and line', () {
    final stack = StackTrace.fromString(
      '#0      _EventParticipantsState._correctCallup (package:teamzone_app/src/features/calendar/event_participants.dart:641:7)\n'
      '#1      _InkResponseState.handleTap (package:flutter/src/material/ink_well.dart:1176:21)\n'
      '#2      _rootRun (dart:async/zone.dart:1399:13)\n'
      '#3      main.<anonymous closure> (package:teamzone_app/main.dart:64:5)',
    );
    expect(
      StackSanitizer.sanitize(stack),
      '#0 _EventParticipantsState._correctCallup (package:teamzone_app/src/features/calendar/event_participants.dart:641:7)\n'
      '#1 _InkResponseState.handleTap (package:flutter/src/material/ink_well.dart:1176:21)\n'
      '#2 _rootRun (dart:async/zone.dart:1399:13)\n'
      '#3 main.<anonymous closure> (package:teamzone_app/main.dart:64:5)',
    );
  });

  test('absolute paths and URLs are cut to the file name', () {
    expect(
      StackSanitizer.sanitizeFrame(
        r'#0      helper (file:///C:/Users/anna.andersson/app/lib/x.dart:3:1)',
      ),
      'helper (x.dart:3:1)',
    );
    expect(
      StackSanitizer.sanitizeFrame(
        '    at Object.c (https://app.teamzoneapp.se/main.dart.js?v=2:9876:54)',
      ),
      'Object.c (main.dart.js:9876:54)',
    );
    expect(
      StackSanitizer.sanitizeFrame(
        '    at https://app.teamzoneapp.se/main.dart.js:10:2',
      ),
      '<anonymous> (main.dart.js:10:2)',
    );
  });

  test('anything that is not a code location is dropped', () {
    final stack = StackTrace.fromString(
      'Exception: Ogiltig e-post anna@example.se\n'
      '#0      ok (package:teamzone_app/a.dart:1:1)\n'
      '#1      weird member with spaces here (package:teamzone_app/b.dart:2:2)\n'
      '#2      evil (anna@example.se:3:3)\n'
      '#3      note (package:teamzone_app/notes/Anna Andersson.dart:4:4)\n'
      '#4      Anna Andersson (package:teamzone_app/c.dart:5:5)\n'
      '<asynchronous suspension>\n'
      'Svensson, Anna 0701234567',
    );
    final sanitized = StackSanitizer.sanitize(stack);
    expect(sanitized, '#0 ok (package:teamzone_app/a.dart:1:1)');
    expect(sanitized, isNot(contains('@')));
    expect(sanitized, isNot(contains('Anna')));
  });

  test('constructors and closures keep their only allowed space', () {
    expect(
      StackSanitizer.sanitizeFrame(
        '#0      new EventDetails.fromJson (package:teamzone_app/m.dart:8:3)',
      ),
      'new EventDetails.fromJson (package:teamzone_app/m.dart:8:3)',
    );
    expect(
      StackSanitizer.sanitizeFrame(
        '#0      _State.build.<anonymous closure> (package:teamzone_app/m.dart:9:1)',
      ),
      '_State.build.<anonymous closure> (package:teamzone_app/m.dart:9:1)',
    );
  });

  test('at most 30 frames and nothing for a missing stack', () {
    final many = StackTrace.fromString(
      List.generate(
        50,
        (i) => '#$i      f$i (package:teamzone_app/a.dart:$i:1)',
      ).join('\n'),
    );
    expect(
      StackSanitizer.sanitize(many).split('\n'),
      hasLength(StackSanitizer.maxFrames),
    );
    expect(StackSanitizer.sanitize(null), '');
  });
}
