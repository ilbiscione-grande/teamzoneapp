import test from 'node:test';
import assert from 'node:assert/strict';
import {calendarPreferenceKey,parseCalendarPreference} from '../lib/calendar-preferences.ts';

test('view and selected physical resource are restored together',()=>{
  for(const view of ['day','week','list'])assert.deepEqual(parseCalendarPreference(JSON.stringify({view,resourceId:'pitch'}),['pitch']),{view,resourceId:'pitch'});
});
test('a removed or unauthorized resource falls back to all pitches without losing the chosen view',()=>{
  assert.deepEqual(parseCalendarPreference('{"view":"week","resourceId":"other-org"}',['pitch']),{view:'week',resourceId:'all-pitches'});
  assert.deepEqual(parseCalendarPreference('{"view":"week","resourceId":"all-pitches"}',['pitch']),{view:'week',resourceId:'all-pitches'});
});
test('missing, malformed and unsupported local data cannot break the calendar',()=>{
  for(const raw of [null,'','{','null','[]','true','{"view":12,"resourceId":{}}'])assert.deepEqual(parseCalendarPreference(raw,['pitch']),{view:'day',resourceId:'all-pitches'});
});
test('calendar preferences are stored under separate organization keys',()=>{
  assert.notEqual(calendarPreferenceKey('club-a'),calendarPreferenceKey('club-b'));
});
