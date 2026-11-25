import 'package:flutter/material.dart';
import 'package:teamzone_app/src/core/localization/app_strings.dart';

/// Asks twice before survey answers are deleted, since they cannot be
/// restored: what is deleted, then whether it is certain. True only when
/// both were confirmed.
Future<bool> confirmSurveyAnswersDeletion(
  BuildContext context, {
  required String title,
  required String message,
}) {
  final swedish = AppStrings.of(context).isSwedish;
  return confirmDeletionTwice(
    context,
    title: title,
    message: message,
    warning: swedish
        ? 'Är du säker på att du vill ta bort svaren för gott? Det går inte att återställa.'
        : 'Are you sure you want to delete the answers for good? They cannot be restored.',
    keep: swedish ? 'Behåll svaren' : 'Keep the answers',
  );
}

/// Asks twice before something that cannot be restored is deleted.
Future<bool> confirmDeletionTwice(
  BuildContext context, {
  required String title,
  required String message,
  required String warning,
  required String keep,
}) async {
  final swedish = AppStrings.of(context).isSwedish;
  final first = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('survey-delete-first'),
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(swedish ? 'Avbryt' : 'Cancel'),
        ),
        FilledButton(
          key: const Key('survey-delete-continue'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(swedish ? 'Ta bort' : 'Delete'),
        ),
      ],
    ),
  );
  if (first != true || !context.mounted) return false;
  final second = await showDialog<bool>(
    context: context,
    builder: (context) {
      final colors = Theme.of(context).colorScheme;
      return AlertDialog(
        key: const Key('survey-delete-second'),
        icon: Icon(Icons.warning_amber_rounded, color: colors.error),
        title: Text(swedish ? 'Är du säker?' : 'Are you sure?'),
        content: Text(warning),
        // Keeping is the prominent choice, in the place where the first
        // dialog deleted: a quick second tap deletes nothing.
        actions: [
          TextButton(
            key: const Key('survey-delete-confirm'),
            style: TextButton.styleFrom(foregroundColor: colors.error),
            onPressed: () => Navigator.pop(context, true),
            child: Text(swedish ? 'Ta bort för gott' : 'Delete for good'),
          ),
          FilledButton(
            key: const Key('survey-delete-keep'),
            onPressed: () => Navigator.pop(context, false),
            child: Text(keep),
          ),
        ],
      );
    },
  );
  return second == true;
}
