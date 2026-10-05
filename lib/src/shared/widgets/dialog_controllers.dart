import 'dart:async';

import 'package:flutter/foundation.dart';

/// Disposes controllers owned by a dialog once its closing animation is done.
///
/// `showDialog` returns as soon as the route is popped, while the dialog's
/// fields stay mounted for the exit transition. Disposing a field's
/// controller at that point tears down a listenable the field still depends
/// on and fails with `_dependents.isEmpty` (seen when archiving an event on a
/// phone). The delay outlasts the Material dialog transition.
void disposeAfterDialog(Iterable<ChangeNotifier> controllers) {
  final pending = List<ChangeNotifier>.of(controllers);
  unawaited(
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      for (final controller in pending) {
        controller.dispose();
      }
    }),
  );
}
