import 'package:teamzone_app/src/features/attendance_export/export_models.dart';
import 'package:teamzone_app/src/features/calendar/calendar_models.dart';
import 'package:teamzone_app/src/features/calendar/calendar_services.dart';

/// Builds the provider-neutral export basis from Teamzone's existing event
/// and attendance projections (api.get_event_details / api.get_event_squad).
/// Reads only; Teamzone's attendance logic is not involved.
AttendanceExportBasis buildAttendanceExportBasis({
  required EventDetails event,
  required SquadDetails squad,
  required String teamId,
  required Map<String, Set<String>> teamRoster,
  required DateTime now,
}) {
  // Everyone on any of the event's team rosters (deduplicated per person by
  // SquadDetails); used to tell members of other sharing teams from guests.
  final onAnyEventRoster = {
    for (final person in squad.roster)
      if (!person.isGuest) person.personId,
  };
  final rosterByPerson = {
    for (final person in squad.roster) person.personId: person,
  };
  // api.get_event_squad's attendance lists everyone with a recorded status
  // or an active callup — the people who took part in this event.
  final candidates = <ExportCandidate>[];
  final seen = <String>{};
  for (final item in squad.attendance) {
    if (!seen.add(item.personId)) continue;
    final roles = teamRoster[item.personId] ?? const <String>{};
    final status = item.status == 'unknown'
        ? rosterByPerson[item.personId]?.attendanceStatus ?? item.status
        : item.status;
    candidates.add(
      ExportCandidate(
        personId: item.personId,
        name: item.name,
        membership: roles.isNotEmpty
            ? ExportMembership.team
            : onAnyEventRoster.contains(item.personId)
            ? ExportMembership.otherTeam
            : ExportMembership.guest,
        teamRoles: roles,
        attendance: explicitAttendanceFromStatus(status),
        recordedStatus: status,
      ),
    );
  }
  return AttendanceExportBasis(
    eventId: event.id,
    teamId: teamId,
    eventTitle: event.title,
    eventType: event.type,
    eventState: event.state,
    startsAt: event.startsAt,
    endsAt: event.endsAt,
    eventTeamIds: {
      for (final team in event.teams)
        if (team['team_id'] is String) team['team_id'] as String,
    },
    ended: isEventEndedForExport(event, now),
    candidates: candidates,
  );
}

/// Ended = the end time has passed and the event took place (not a draft,
/// not cancelled).
bool isEventEndedForExport(EventDetails event, DateTime now) =>
    ['scheduled', 'completed'].contains(event.state) &&
    !now.toUtc().isBefore(event.endsAt.toUtc());

/// Loads the basis through the existing calendar services.
Future<AttendanceExportBasis> loadAttendanceExportBasis({
  required CalendarServices calendar,
  required String eventId,
  required String teamId,
  required Map<String, Set<String>> teamRoster,
  DateTime? now,
}) async {
  final event = await calendar.getEventDetails(eventId);
  final squad = await calendar.getEventSquad(eventId);
  return buildAttendanceExportBasis(
    event: event,
    squad: squad,
    teamId: teamId,
    teamRoster: teamRoster,
    now: now ?? DateTime.now(),
  );
}
