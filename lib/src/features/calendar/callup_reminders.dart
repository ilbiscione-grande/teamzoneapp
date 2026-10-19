import 'package:flutter/material.dart';
import 'package:teamzone_app/src/core/observability/app_errors.dart';
import 'package:teamzone_app/src/features/calendar/calendar_models.dart';
import 'package:teamzone_app/src/features/calendar/calendar_services.dart';

/// A callup that can be reminded now, for the shared review dialog used by
/// the participants tab and by Min assistent's "Påminn…".
class ReminderCandidate {
  const ReminderCandidate({
    required this.callupId,
    required this.name,
    required this.revision,
    this.lastRemindedAt,
  });
  final String callupId, name;
  final int revision;
  final DateTime? lastRemindedAt;
}

/// Mirrors the server's remind gate: pending, not expired and at least six
/// hours since the last reminder.
bool canRemindCallup(CallupView callup, DateTime now) {
  if (callup.state != 'pending') return false;
  if (callup.expiresAt != null && !callup.expiresAt!.isAfter(now)) {
    return false;
  }
  final last = callup.lastRemindedAt;
  return last == null || now.difference(last) >= const Duration(hours: 6);
}

/// Every callup on the event that can be reminded now.
List<ReminderCandidate> remindableCallups(SquadDetails squad, DateTime now) => [
  for (final callup in squad.callups)
    if (canRemindCallup(callup, now))
      ReminderCandidate(
        callupId: callup.id,
        name: callup.name,
        revision: callup.revision,
        lastRemindedAt: callup.lastRemindedAt,
      ),
];

/// The review before anything is sent: every eligible person is ticked and
/// can be unticked. Returns the chosen callups, or null when cancelled.
Future<Set<String>?> showCallupReminderReview(
  BuildContext context,
  List<ReminderCandidate> eligible,
) async {
  if (eligible.isEmpty) return null;
  final selected = eligible.map((candidate) => candidate.callupId).toSet();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: const Text('Granska påminnelser'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Endast obesvarade, giltiga kallelser visas. '
                  'Minst sex timmar måste ha gått sedan senaste påminnelsen.',
                ),
                for (final candidate in eligible)
                  CheckboxListTile(
                    value: selected.contains(candidate.callupId),
                    title: Text(candidate.name),
                    subtitle: Text(
                      candidate.lastRemindedAt == null
                          ? 'Ingen tidigare påminnelse'
                          : 'Senast: ${MaterialLocalizations.of(context).formatShortDate(candidate.lastRemindedAt!.toLocal())} '
                                '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(candidate.lastRemindedAt!.toLocal()))}',
                    ),
                    onChanged: (value) => update(() {
                      if (value == true) {
                        selected.add(candidate.callupId);
                      } else {
                        selected.remove(candidate.callupId);
                      }
                    }),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: selected.isEmpty
                ? null
                : () => Navigator.pop(dialogContext, true),
            child: Text('Skicka ${selected.length} påminnelser'),
          ),
        ],
      ),
    ),
  );
  return confirmed == true ? selected : null;
}

/// Sends the chosen reminders one by one through the ordinary remind command.
/// [keys] keeps one idempotency key per callup revision, so a retry after a
/// lost reply never sends twice.
///
/// A list read a while ago (an open page, another device) carries old
/// revisions, and the server refuses every one of them. With [eventId] the
/// event's callups are read again and those still due are sent once more
/// with their current revision.
Future<({int sent, int failed})> sendCallupReminders({
  required CalendarServices calendar,
  required List<ReminderCandidate> chosen,
  required Map<String, String> keys,
  required String Function() newKey,
  String? eventId,
}) async {
  var sent = 0, failed = 0;
  final stale = <String>{};
  Future<bool> send(String callupId, int revision) async {
    try {
      await calendar.manageCallup(
        callupId: callupId,
        action: 'remind',
        expectedRevision: revision,
        idempotencyKey: keys.putIfAbsent('$callupId:$revision', newKey),
      );
      return true;
    } catch (error) {
      if (error.toString().contains('stale_revision')) {
        stale.add(callupId);
      } else {
        AppErrors.caught('callup_reminders.send', error);
      }
      return false;
    }
  }

  for (final candidate in chosen) {
    if (await send(candidate.callupId, candidate.revision)) sent++;
  }
  if (stale.isNotEmpty && eventId != null) {
    final retry = Set<String>.of(stale);
    stale.clear();
    try {
      final squad = await calendar.getEventSquad(eventId);
      for (final current in remindableCallups(squad, DateTime.now())) {
        if (!retry.remove(current.callupId)) continue;
        if (await send(current.callupId, current.revision)) sent++;
      }
    } catch (error) {
      AppErrors.caught('callup_reminders.refresh', error);
    }
    // Answered, expired or reminded elsewhere meanwhile: not sent.
    stale.addAll(retry);
  }
  failed = chosen.length - sent;
  if (stale.isNotEmpty) {
    AppErrors.caught(
      'callup_reminders.send',
      StateError('stale_revision x${stale.length}'),
    );
  }
  return (sent: sent, failed: failed);
}

/// The snackbar text after sending.
String reminderResultText(({int sent, int failed}) result) => result.failed > 0
    ? '${result.sent} påminnelser skickade. ${result.failed} kunde inte skickas. Granska de uppdaterade kallelserna innan du försöker igen.'
    : result.sent == 1
    ? 'Påminnelsen är skickad.'
    : '${result.sent} påminnelser är skickade.';
