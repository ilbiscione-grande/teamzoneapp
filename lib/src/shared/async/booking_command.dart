import 'dart:convert';
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

final _bookingCommands = Expando<Map<String, String>>();

/// Retain the key on an uncertain response so an explicit retry is safe.
Future<Object?> executeBookingCommand(
  SupabaseClient client,
  String command,
  Map<String, dynamic> payload, {
  Map<String, int>? revisions,
}) async {
  final pending = _bookingCommands[client] ??= <String, String>{};
  final fingerprint = jsonEncode([
    client.auth.currentUser?.id,
    command,
    payload,
    revisions,
  ]);
  final key = pending.putIfAbsent(fingerprint, _newBookingCommandId);
  final result = await client
      .schema('api')
      .rpc<Object?>(
        'execute_booking_command',
        params: {
          'command_id': key,
          'command_type': command,
          'payload': payload,
          'expected_revisions': revisions,
        },
      )
      .timeout(const Duration(seconds: 15));
  pending.remove(fingerprint);
  return result;
}

String _newBookingCommandId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
