import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:teamzone_app/src/features/calendar/booking_management_services.dart';

void main() {
  test(
    'RPC adapter uses api schema, authoritative organization, exact review and stable retry key',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final calls = <({String path, String? schema, BookingData body})>[];
      var failSave = true;
      server.listen((request) async {
        final body = bookingMap(jsonDecode(await utf8.decodeStream(request)));
        calls.add((
          path: request.uri.path,
          schema: request.headers.value('content-profile'),
          body: body,
        ));
        request.response.headers.contentType = ContentType.json;
        Object? result;
        if (request.uri.path.endsWith('get_booking_series_plan')) {
          result = {
            'plan': {'id': 'plan', 'revision': 7},
            'slots': [],
          };
        } else if (request.uri.path.endsWith('preview_booking_change')) {
          result = {
            'target_booking_id': 'anchor',
            'timing': {
              'bookings': [
                {'id': 'other', 'organization_id': 'wrong'},
                {
                  'id': 'anchor',
                  'organization_id': 'org',
                  'starts_at': '2027-03-01T18:00:00Z',
                  'ends_at': '2027-03-01T19:00:00Z',
                },
              ],
            },
            'conflicts': [],
            'change_count': 1,
          };
        } else if (request.uri.path.endsWith('list_booking_availability')) {
          result = [
            {
              'resource_id': 'camera',
              'name': 'Kamera',
              'category': 'equipment',
              'requires_approval': true,
              'busy': false,
            },
          ];
        } else if (body['command_type'] == 'update_booking' && failSave) {
          failSave = false;
          request.response.statusCode = 503;
          result = {'message': 'uncertain_response'};
        } else {
          result = {'ok': true};
        }
        request.response.write(jsonEncode(result));
        await request.response.close();
      });
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'publishable-test',
      );
      addTearDown(() async {
        await client.dispose();
        await server.close(force: true);
      });
      final services = SupabaseBookingManagement(client);
      final data = await services.getSeriesPlan('anchor');
      final parameters = <String, dynamic>{
        'target_booking_id': 'anchor',
        'change_scope': 'event_forward',
        'new_starts_at': '2027-03-01T18:00:00Z',
        'new_ends_at': '2027-03-01T19:00:00Z',
        'add_resource_ids': ['camera'],
        'remove_resource_ids': ['bus'],
      };
      final preview = await services.previewBookingChange(parameters);
      final resources = await services.changeResources(preview);
      expect(resources.single.requiresApproval, isTrue);
      await services.controlSeriesPlan(bookingMap(data['plan']), 'pause');
      await expectLater(
        services.saveBookingChange(parameters, preview),
        throwsA(isA<PostgrestException>()),
      );
      await services.saveBookingChange(parameters, preview);
      expect(calls.every((c) => c.schema == 'api'), isTrue);
      expect(calls[0].body, {'target_booking_id': 'anchor'});
      expect(calls[1].body, parameters);
      expect(calls[2].body['target_organization_id'], 'org');
      expect(calls[3].body['payload'], {
        'plan_id': 'plan',
        'action': 'pause',
        'expected_revision': 7,
      });
      expect(calls[4].body['command_id'], calls[5].body['command_id']);
      expect(calls[5].body['command_type'], 'update_booking');
      expect(calls[5].body['payload'], {
        ...parameters,
        'expected_plan': preview,
      });
    },
  );
}
