import 'package:supabase_flutter/supabase_flutter.dart';

class MeasuredCommandException implements Exception {
  const MeasuredCommandException(this.code);
  final String code;

  @override
  String toString() => 'MeasuredCommandException($code)';
}

Future<Object?> measuredRpc(
  SupabaseClient client, {
  required String operation,
  required Map<String, Object?> params,
}) async {
  final response = await client.functions.invoke(
    'critical-flow-command',
    body: {'operation': operation, 'params': params},
  );
  final payload = response.data;
  if (response.status != 200 ||
      payload is! Map ||
      !payload.containsKey('data')) {
    final code = payload is Map && payload['error'] is String
        ? payload['error']! as String
        : 'command_failed';
    throw MeasuredCommandException(code);
  }
  return payload['data'];
}
