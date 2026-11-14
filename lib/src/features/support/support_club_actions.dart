import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:teamzone_app/src/core/localization/support_strings.dart';
import 'package:teamzone_app/src/features/support/support_club_services.dart';

/// TeamZone support only: helping a club that is stuck (support admin
/// page, part 3). Every action needs a reason and is logged on the server.
abstract interface class SupportClubActionServices {
  Future<void> grantClubAdmin({
    required String clubId,
    required String personId,
    required String reason,
  });

  /// Returns whether the club was left without an admin with an account
  /// (the logged emergency exception).
  Future<bool> removeClubAdmin({
    required String clubId,
    required String personId,
    required String reason,
  });

  Future<void> resolveBoardChange({
    required String changeId,
    required bool apply,
    required String reason,
  });
}

/// The Supabase calls, used by SupabaseMembershipServices.
Future<void> sendSupportGrantClubAdmin(
  SupabaseClient client,
  String clubId,
  String personId,
  String reason,
) => client
    .schema('api')
    .rpc<Object?>(
      'support_grant_club_admin',
      params: {
        'target_club_id': clubId,
        'target_person_id': personId,
        'reason': reason.trim(),
      },
    );

Future<bool> sendSupportRemoveClubAdmin(
  SupabaseClient client,
  String clubId,
  String personId,
  String reason,
) async {
  final value = await client
      .schema('api')
      .rpc<Object?>(
        'support_remove_club_admin',
        params: {
          'target_club_id': clubId,
          'target_person_id': personId,
          'reason': reason.trim(),
        },
      );
  return value is Map && value['left_without_admin'] == true;
}

Future<void> sendSupportResolveBoardChange(
  SupabaseClient client,
  String changeId,
  bool apply,
  String reason,
) => client
    .schema('api')
    .rpc<Object?>(
      'support_resolve_board_change',
      params: {
        'target_change_id': changeId,
        'decision': apply ? 'apply' : 'cancel',
        'reason': reason.trim(),
      },
    );

/// The server's refusal codes, so the page can explain them.
String? supportClubActionRefusal(Object error) {
  final text = error is PostgrestException ? error.message : '$error';
  for (final code in const [
    'invalid_reason',
    'person_without_account',
    'already_club_admin',
    'not_club_admin',
    'board_change_not_pending',
    'mandate_target_inactive',
    'mandate_overlap',
    'invalid_state',
  ]) {
    if (text.contains(code)) return code;
  }
  return null;
}

/// Asks for a reason (5–500 characters), with an optional choice above it.
/// Returns the reason, or null when cancelled.
Future<String?> askSupportReason(
  BuildContext context, {
  required String title,
  required String body,
  required String confirm,
  String? warning,
}) {
  final strings = SupportStrings.of(context);
  final formKey = GlobalKey<FormState>();
  var reason = '';
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(body),
            if (warning != null) ...[
              const SizedBox(height: 8),
              Text(
                warning,
                key: const ValueKey('support-club-action-warning'),
                style: TextStyle(
                  color: Theme.of(dialogContext).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 12),
            _ReasonField(onChanged: (value) => reason = value),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(strings.cancel),
        ),
        FilledButton(
          key: const ValueKey('support-club-action-confirm'),
          onPressed: () {
            if (formKey.currentState?.validate() != true) return;
            Navigator.pop(dialogContext, reason);
          },
          child: Text(confirm),
        ),
      ],
    ),
  );
}

/// Choosing a new club admin among those with an account, and a reason.
Future<({String personId, String reason})?> askNewClubAdmin(
  BuildContext context,
  List<SupportClubAccount> candidates,
) {
  final strings = SupportStrings.of(context);
  final formKey = GlobalKey<FormState>();
  String? personId;
  var reason = '';
  return showDialog<({String personId, String reason})>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(strings.grantClubAdmin),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(strings.grantClubAdminBody),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const ValueKey('support-club-admin-person'),
              isExpanded: true,
              decoration: InputDecoration(labelText: strings.personLabel),
              items: [
                for (final person in candidates)
                  DropdownMenuItem(
                    value: person.personId,
                    child: Text(person.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) => personId = value,
              validator: (value) => value == null ? strings.choosePerson : null,
            ),
            const SizedBox(height: 12),
            _ReasonField(onChanged: (value) => reason = value),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(strings.cancel),
        ),
        FilledButton(
          key: const ValueKey('support-club-action-confirm'),
          onPressed: () {
            if (formKey.currentState?.validate() != true) return;
            Navigator.pop(dialogContext, (personId: personId!, reason: reason));
          },
          child: Text(strings.grantClubAdminConfirm),
        ),
      ],
    ),
  );
}

class _ReasonField extends StatelessWidget {
  const _ReasonField({required this.onChanged});
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = SupportStrings.of(context);
    return TextFormField(
      key: const ValueKey('support-club-action-reason'),
      minLines: 2,
      maxLines: 4,
      maxLength: 500,
      decoration: InputDecoration(labelText: strings.reasonLabel),
      onChanged: onChanged,
      validator: (value) =>
          (value?.trim().length ?? 0) < 5 ? strings.reasonTooShort : null,
    );
  }
}
