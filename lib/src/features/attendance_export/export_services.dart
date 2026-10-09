import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:teamzone_app/src/features/attendance_export/export_models.dart';

/// Storage for integration settings, member/activity links and the export
/// log (schema attendance_export via api.attendance_export_* RPCs).
abstract interface class AttendanceExportServices {
  bool get isConfigured;
  Future<TeamIntegrationSettings> getTeamIntegration({
    required String teamId,
    required String provider,
  });
  Future<TeamIntegrationSettings> setTeamIntegration({
    required String teamId,
    required String provider,
    required bool enabled,
    String? externalTeamRef,
    required int expectedRevision,
  });
  Future<TeamIntegrationSettings> saveMemberLink({
    required String teamId,
    required String provider,
    required String personId,
    required String externalId,
    required String externalName,
    required String externalRole,
    required int expectedRevision,
  });
  Future<TeamIntegrationSettings> deleteMemberLink({
    required String teamId,
    required String provider,
    required String personId,
    required int expectedRevision,
  });
  Future<ExportContext> getExportContext({
    required String eventId,
    required String teamId,
    required String provider,
  });

  /// [externalActivityId] null removes the link.
  Future<ExportContext> setActivityLink({
    required String eventId,
    required String teamId,
    required String provider,
    required String? externalActivityId,
    required int expectedRevision,
  });
  Future<String> recordExport({
    required String eventId,
    required String teamId,
    required String provider,
    required ExportState state,
    String? externalActivityId,
    Map<String, dynamic> summary = const {},
    bool confirmedComplete = false,
    String? payloadSha256,
    String? errorCode,
  });

  /// Queues a sync for the local sync agent ([payload] is the receiver's
  /// file contract). The agent first reports a preview for approval.
  Future<SyncJob> requestSync({
    required String eventId,
    required String teamId,
    required String provider,
    required Map<String, Object> payload,
    Map<String, dynamic> summary = const {},
    required bool confirmedComplete,
  });

  /// Approves exactly the preview identified by [previewSha256].
  Future<SyncJob> approveSync({
    required String jobId,
    required String previewSha256,
  });
  Future<SyncJob> cancelSync(String jobId);
}

class UnconfiguredAttendanceExportServices implements AttendanceExportServices {
  const UnconfiguredAttendanceExportServices();
  static final _error = StateError('Backend är inte ansluten.');
  @override
  bool get isConfigured => false;
  @override
  Future<TeamIntegrationSettings> getTeamIntegration({
    required String teamId,
    required String provider,
  }) => Future.error(_error);
  @override
  Future<TeamIntegrationSettings> setTeamIntegration({
    required String teamId,
    required String provider,
    required bool enabled,
    String? externalTeamRef,
    required int expectedRevision,
  }) => Future.error(_error);
  @override
  Future<TeamIntegrationSettings> saveMemberLink({
    required String teamId,
    required String provider,
    required String personId,
    required String externalId,
    required String externalName,
    required String externalRole,
    required int expectedRevision,
  }) => Future.error(_error);
  @override
  Future<TeamIntegrationSettings> deleteMemberLink({
    required String teamId,
    required String provider,
    required String personId,
    required int expectedRevision,
  }) => Future.error(_error);
  @override
  Future<ExportContext> getExportContext({
    required String eventId,
    required String teamId,
    required String provider,
  }) => Future.error(_error);
  @override
  Future<ExportContext> setActivityLink({
    required String eventId,
    required String teamId,
    required String provider,
    required String? externalActivityId,
    required int expectedRevision,
  }) => Future.error(_error);
  @override
  Future<String> recordExport({
    required String eventId,
    required String teamId,
    required String provider,
    required ExportState state,
    String? externalActivityId,
    Map<String, dynamic> summary = const {},
    bool confirmedComplete = false,
    String? payloadSha256,
    String? errorCode,
  }) => Future.error(_error);
  @override
  Future<SyncJob> requestSync({
    required String eventId,
    required String teamId,
    required String provider,
    required Map<String, Object> payload,
    Map<String, dynamic> summary = const {},
    required bool confirmedComplete,
  }) => Future.error(_error);
  @override
  Future<SyncJob> approveSync({
    required String jobId,
    required String previewSha256,
  }) => Future.error(_error);
  @override
  Future<SyncJob> cancelSync(String jobId) => Future.error(_error);
}

class SupabaseAttendanceExportServices implements AttendanceExportServices {
  const SupabaseAttendanceExportServices(this._client);
  final SupabaseClient _client;

  @override
  bool get isConfigured => true;

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> params,
  ) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(name, params: params);
    if (value is! Map) {
      throw const FormatException('Invalid attendance export response.');
    }
    return Map<String, dynamic>.from(value);
  }

  @override
  Future<TeamIntegrationSettings> getTeamIntegration({
    required String teamId,
    required String provider,
  }) async => TeamIntegrationSettings.fromJson(
    await _call('attendance_export_get_team_integration', {
      'team_id': teamId,
      'provider': provider,
    }),
  );

  @override
  Future<TeamIntegrationSettings> setTeamIntegration({
    required String teamId,
    required String provider,
    required bool enabled,
    String? externalTeamRef,
    required int expectedRevision,
  }) async => TeamIntegrationSettings.fromJson(
    await _call('attendance_export_set_team_integration', {
      'team_id': teamId,
      'provider': provider,
      'enabled': enabled,
      'external_team_ref': externalTeamRef,
      'expected_revision': expectedRevision,
    }),
  );

  @override
  Future<TeamIntegrationSettings> saveMemberLink({
    required String teamId,
    required String provider,
    required String personId,
    required String externalId,
    required String externalName,
    required String externalRole,
    required int expectedRevision,
  }) async => TeamIntegrationSettings.fromJson(
    await _call('attendance_export_save_member_link', {
      'team_id': teamId,
      'provider': provider,
      'person_id': personId,
      'external_id': externalId,
      'external_name': externalName,
      'external_role': externalRole,
      'expected_revision': expectedRevision,
    }),
  );

  @override
  Future<TeamIntegrationSettings> deleteMemberLink({
    required String teamId,
    required String provider,
    required String personId,
    required int expectedRevision,
  }) async => TeamIntegrationSettings.fromJson(
    await _call('attendance_export_delete_member_link', {
      'team_id': teamId,
      'provider': provider,
      'person_id': personId,
      'expected_revision': expectedRevision,
    }),
  );

  @override
  Future<ExportContext> getExportContext({
    required String eventId,
    required String teamId,
    required String provider,
  }) async => ExportContext.fromJson(
    await _call('attendance_export_get_context', {
      'event_id': eventId,
      'team_id': teamId,
      'provider': provider,
    }),
  );

  @override
  Future<ExportContext> setActivityLink({
    required String eventId,
    required String teamId,
    required String provider,
    required String? externalActivityId,
    required int expectedRevision,
  }) async => ExportContext.fromJson(
    await _call('attendance_export_set_activity_link', {
      'event_id': eventId,
      'team_id': teamId,
      'provider': provider,
      'external_activity_id': externalActivityId,
      'expected_revision': expectedRevision,
    }),
  );

  @override
  Future<String> recordExport({
    required String eventId,
    required String teamId,
    required String provider,
    required ExportState state,
    String? externalActivityId,
    Map<String, dynamic> summary = const {},
    bool confirmedComplete = false,
    String? payloadSha256,
    String? errorCode,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'attendance_export_record',
          params: {
            'event_id': eventId,
            'team_id': teamId,
            'provider': provider,
            'state': switch (state) {
              ExportState.fileCreated => 'file_created',
              ExportState.failed => 'failed',
              _ => throw ArgumentError.value(state, 'state'),
            },
            'external_activity_id': externalActivityId,
            'summary': summary,
            'confirmed_complete': confirmedComplete,
            'payload_sha256': payloadSha256,
            'error_code': errorCode,
          },
        );
    if (value is! String) {
      throw const FormatException('Invalid export record response.');
    }
    return value;
  }

  @override
  Future<SyncJob> requestSync({
    required String eventId,
    required String teamId,
    required String provider,
    required Map<String, Object> payload,
    Map<String, dynamic> summary = const {},
    required bool confirmedComplete,
  }) async => SyncJob.fromJson(
    await _call('attendance_export_request_sync', {
      'event_id': eventId,
      'team_id': teamId,
      'provider': provider,
      'payload': payload,
      'summary': summary,
      'confirmed_complete': confirmedComplete,
    }),
  );

  @override
  Future<SyncJob> approveSync({
    required String jobId,
    required String previewSha256,
  }) async => SyncJob.fromJson(
    await _call('attendance_export_approve_sync', {
      'job_id': jobId,
      'preview_sha256': previewSha256,
    }),
  );

  @override
  Future<SyncJob> cancelSync(String jobId) async => SyncJob.fromJson(
    await _call('attendance_export_cancel_sync', {'job_id': jobId}),
  );
}

/// Server error message (e.g. 'external_id_taken') from a failed RPC.
String? attendanceExportErrorCode(Object error) =>
    error is PostgrestException ? error.message : null;
