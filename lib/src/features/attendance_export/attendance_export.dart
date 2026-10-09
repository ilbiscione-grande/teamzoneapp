// TEMPORARY FEATURE: attendance export to laget.se.
//
// The only library the rest of the app imports. Every place that uses it is
// marked `attendance-export:hook`; removal is described in
// docs/implementation/attendance_export_laget_se.md.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/features/attendance_export/export_basis.dart';
import 'package:teamzone_app/src/features/attendance_export/export_services.dart';
import 'package:teamzone_app/src/features/attendance_export/ui/attendance_export_page.dart';
import 'package:teamzone_app/src/features/attendance_export/ui/laget_se_settings_page.dart';
import 'package:teamzone_app/src/features/calendar/calendar_models.dart';
import 'package:teamzone_app/src/features/calendar/calendar_services.dart';

abstract final class AttendanceExportFeature {
  /// Build-time switch: `--dart-define=TEAMZONE_ATTENDANCE_EXPORT=false`
  /// hides every entry point without removing code.
  static const enabledByBuild = bool.fromEnvironment(
    'TEAMZONE_ATTENDANCE_EXPORT',
    defaultValue: true,
  );

  static AttendanceExportServices services =
      const UnconfiguredAttendanceExportServices();

  static void configure(SupabaseClient client) =>
      services = SupabaseAttendanceExportServices(client);

  static bool get isAvailable => enabledByBuild && services.isConfigured;

  /// Whether the event's ⋮ menu should offer "Exportera närvaro → laget.se".
  /// The server re-checks the permission and that the integration is on.
  static bool canOfferEventExport({
    required EventDetails event,
    required TeamZoneContext contextValue,

    /// SquadDetails.can('record_attendance') for the event.
    required bool canManageAttendance,
    DateTime? now,
  }) =>
      isAvailable &&
      contextValue.teamId != null &&
      canManageAttendance &&
      isEventEndedForExport(event, now ?? DateTime.now());

  static Future<void> openEventExport(
    BuildContext context, {
    required CalendarServices calendar,
    required String eventId,
    required String teamId,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => AttendanceExportPage(
        eventId: eventId,
        teamId: teamId,
        calendar: calendar,
        services: services,
      ),
    ),
  );

  /// "Integrationer → laget.se" entries for the settings' team tab, one per
  /// team the user administers.
  static List<Widget> teamSettingsEntries(
    BuildContext context,
    List<TeamZoneContext> contexts,
  ) {
    if (!isAvailable) return const [];
    final teams = {
      for (final item in contexts)
        if (item.teamId != null &&
            item.capabilities.contains('team.roster.manage'))
          item.teamId!: item,
    }.values.toList();
    if (teams.isEmpty) return const [];
    return [
      const SizedBox(height: 24),
      Text('Integrationer', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      for (final team in teams)
        Card(
          child: ListTile(
            key: ValueKey('attendance-export-settings-${team.teamId}'),
            leading: const Icon(Icons.sync_alt),
            title: Text('laget.se · ${team.teamName ?? team.clubName}'),
            subtitle: const Text('Närvaroexport och medlemskopplingar'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => LagetSeSettingsPage(
                  teamId: team.teamId!,
                  teamName: team.teamName ?? team.clubName,
                  services: services,
                ),
              ),
            ),
          ),
        ),
    ];
  }
}
