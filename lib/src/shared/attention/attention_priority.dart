int attentionPriority(String kind) => switch (kind) {
  'missing_attendance' || 'callup_cancelled' => 10,
  'pending_callups' || 'pending_callup' || 'callup_reminder' || 'callup' => 20,
  'event_today' || 'next_event' || 'event' => 30,
  'unread_message' || 'message' => 40,
  _ => 50,
};
