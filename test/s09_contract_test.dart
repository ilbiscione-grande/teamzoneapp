import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final boundarySql = File(
    '${Directory.current.path}/supabase/migrations/20260815105232_s09_closed_public_api_boundary.sql',
  ).readAsStringSync();
  final dataSql = File(
    '${Directory.current.path}/supabase/migrations/20260815164018_s09_publication_consent_projection.sql',
  ).readAsStringSync();
  final commandSql = File(
    '${Directory.current.path}/supabase/migrations/20260815164950_s09_consent_commands.sql',
  ).readAsStringSync();
  final workerSql = File(
    '${Directory.current.path}/supabase/migrations/20260815165738_s09_publication_settings_worker.sql',
  ).readAsStringSync();
  final publicApiSql = File(
    '${Directory.current.path}/supabase/migrations/20260815170442_s09_public_api_contact_boundary.sql',
  ).readAsStringSync();

  test('S09 public boundary remains structurally disabled', () {
    expect(boundarySql, contains('create schema if not exists public_api'));
    expect(boundarySql, contains('revoke all on schema public_api'));
    expect(boundarySql, contains('check(enabled = false)'));
    expect(
      boundarySql,
      isNot(contains('grant usage on schema public_api to anon')),
    );
    expect(
      dataSql,
      isNot(contains('grant usage on schema public_api to anon')),
    );
  });

  test('S09 separates age assertion and field-specific consent', () {
    expect(dataSql, contains('create table core.person_age_assertions'));
    expect(dataSql, contains("age_band in ('through_15', '16_plus')"));
    expect(dataSql, contains('create table core.publication_consents'));
    for (final field in [
      'name',
      'profile_media',
      'position',
      'individual_statistics',
    ]) {
      expect(dataSql, contains("'$field'"));
    }
    expect(
      dataSql,
      contains("expires_at <= subject_approved_at + interval '366 days'"),
    );
  });

  test('S09 projections and jobs remain private', () {
    expect(dataSql, contains('create table public_api.club_projections'));
    expect(dataSql, contains('create table public_api.team_projections'));
    expect(
      dataSql,
      contains('create table internal.publication_projection_jobs'),
    );
    expect(dataSql, contains('club_projections_no_client_access'));
    expect(dataSql, contains('team_projections_no_client_access'));
    expect(dataSql, isNot(contains('submit_contact')));
  });

  test('S09 consent commands separate subject and guardian actors', () {
    expect(commandSql, contains("then 'pending_guardian' else 'active'"));
    expect(commandSql, contains('internal.actor_owns_club_person'));
    expect(commandSql, contains('core.guardian_relations'));
    expect(commandSql, contains("'publication.consent.withdrawn.v1'"));
    expect(commandSql, contains("'remove',array[]::text[],actor_id"));
    expect(
      commandSql,
      isNot(contains('grant execute on function api.give_publication_consent')),
    );
    expect(commandSql, isNot(contains('to anon')));
  });

  test('S09 projection worker requires cache acknowledgement', () {
    expect(workerSql, contains("'awaiting_invalidation'"));
    expect(workerSql, contains('for update skip locked'));
    expect(workerSql, contains('to service_role'));
    expect(workerSql, contains("new_mode not in ('private','draft')"));
    expect(workerSql, contains("state='failed'"));
    expect(workerSql, isNot(contains("new_mode='published'")));
    expect(workerSql, isNot(contains('to anon')));
  });

  test('S09 public API is server-only, bounded and fail closed', () {
    for (final endpoint in [
      'public_search_clubs',
      'public_get_club',
      'public_get_team',
      'public_list_team_events',
      'public_list_publications',
      'public_submit_contact',
    ]) {
      expect(publicApiSql, contains(endpoint));
    }
    expect(publicApiSql, contains("max_requests:=60"));
    expect(publicApiSql, contains("max_requests:=20"));
    expect(publicApiSql, contains("max_requests:=5"));
    expect(publicApiSql, contains("captcha_verified is not true"));
    expect(publicApiSql, contains("interval '30 days'"));
    expect(publicApiSql, contains("interval '90 days'"));
    expect(publicApiSql, contains('to service_role'));
    expect(publicApiSql, isNot(contains('to anon')));
  });
}
