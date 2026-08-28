import 'package:flutter/material.dart';

class AppFormController extends ChangeNotifier {
  bool _isDirty = false;
  bool _isPending = false;
  bool _disposed = false;

  bool get isDirty => _isDirty;
  bool get isPending => _isPending;
  bool get canSubmit => !_isPending;

  void markDirty() {
    if (_isDirty || _disposed) return;
    _isDirty = true;
    notifyListeners();
  }

  void markClean() {
    if (!_isDirty || _disposed) return;
    _isDirty = false;
    notifyListeners();
  }

  Future<bool> run(Future<void> Function() action) async {
    if (_isPending || _disposed) return false;
    _isPending = true;
    notifyListeners();
    try {
      await action();
      markClean();
      return true;
    } finally {
      if (!_disposed) {
        _isPending = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class AppUnsavedChangesScope extends StatelessWidget {
  const AppUnsavedChangesScope({
    required this.controller,
    required this.title,
    required this.message,
    required this.discardLabel,
    required this.cancelLabel,
    required this.child,
    super.key,
  });

  final AppFormController controller;
  final String title;
  final String message;
  final String discardLabel;
  final String cancelLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => PopScope<void>(
      canPop: !controller.isDirty && !controller.isPending,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || controller.isPending) return;
        final discard = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(cancelLabel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(discardLabel),
              ),
            ],
          ),
        );
        if (discard == true && context.mounted) {
          controller.markClean();
          await WidgetsBinding.instance.endOfFrame;
          if (context.mounted) {
            await Navigator.maybePop(context);
          }
        }
      },
      child: child,
    ),
  );
}
