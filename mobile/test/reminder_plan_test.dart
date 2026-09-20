import 'package:careloop_mobile/services/reminder_service.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> appt(String id, String datetime, {String status = 'scheduled'}) => {
      'id': id,
      'status': status,
      'datetime': datetime,
      'member': {'name': 'Swathika Sharma'},
      'provider': {'name': 'Dr. Ananya Rao'},
    };

// A fixed "now" keeps every case independent of when the suite runs. Wall-clock strings without a
// zone (what a member's booking stores) parse as local, exactly as they do in the app.
final now = DateTime(2026, 9, 20, 10, 0);

void main() {
  test('a visit two days out gets both the day-before and the hour-before reminder', () {
    final plan = planAppointmentReminders([appt('a1', '2026-09-22T16:30:00.000')], now);
    expect(plan.map((r) => r.title), ['Appointment tomorrow', 'Appointment in 1 hour']);
    expect(plan[0].fireAt, DateTime(2026, 9, 21, 16, 30));
    expect(plan[1].fireAt, DateTime(2026, 9, 22, 15, 30));
    expect(plan[0].body, 'Swathika Sharma with Dr. Ananya Rao at 4:30 PM');
  });

  test('a visit less than a day out only gets the hour-before reminder (never a late "tomorrow")', () {
    final plan = planAppointmentReminders([appt('a1', '2026-09-20T18:00:00.000')], now);
    expect(plan.map((r) => r.title), ['Appointment in 1 hour']);
    expect(plan.single.fireAt, DateTime(2026, 9, 20, 17, 0));
  });

  test('a visit inside the last hour gets nothing rather than a reminder fired late', () {
    expect(planAppointmentReminders([appt('a1', '2026-09-20T10:40:00.000')], now), isEmpty);
  });

  test('past visits, and visits that are not still scheduled, get no reminders', () {
    final plan = planAppointmentReminders([
      appt('past', '2026-09-19T09:00:00.000'),
      appt('cancelled', '2026-09-25T09:00:00.000', status: 'cancelled'),
      appt('done', '2026-09-25T09:00:00.000', status: 'completed'),
      appt('consent', '2026-09-25T09:00:00.000', status: 'consent_requested'),
    ], now);
    expect(plan, isEmpty);
  });

  test('a malformed or missing datetime is skipped, not thrown', () {
    expect(planAppointmentReminders([appt('a1', 'not-a-date'), {'id': 'a2', 'status': 'scheduled'}], now), isEmpty);
  });

  test('a doctor-scheduled UTC follow-up resolves to the correct absolute moment', () {
    final plan = planAppointmentReminders([appt('f1', '2026-09-27T05:30:00.000Z')], now);
    final visit = DateTime.utc(2026, 9, 27, 5, 30);
    expect(plan.map((r) => r.fireAt.isAtSameMomentAs(visit.subtract(const Duration(hours: 24)))).first, isTrue);
    expect(plan.last.fireAt.isAtSameMomentAs(visit.subtract(const Duration(hours: 1))), isTrue);
  });

  test('ids are stable per visit, distinct per reminder, and distinct across visits', () {
    final a = planAppointmentReminders([appt('a1', '2026-09-22T16:30:00.000')], now);
    final again = planAppointmentReminders([appt('a1', '2026-09-22T16:30:00.000')], now);
    final other = planAppointmentReminders([appt('a2', '2026-09-22T16:30:00.000')], now);
    expect(a.map((r) => r.id), again.map((r) => r.id));
    expect(a[0].id, isNot(a[1].id));
    expect({...a.map((r) => r.id), ...other.map((r) => r.id)}.length, 4);
    for (final r in [...a, ...other]) {
      expect(r.id, inInclusiveRange(0, 0x7fffffff)); // Android notification ids are signed 32-bit
    }
  });

  test('rescheduling keeps the ids but changes the payload, so a sync moves the reminder', () {
    final before = planAppointmentReminders([appt('a1', '2026-09-22T16:30:00.000')], now);
    final after = planAppointmentReminders([appt('a1', '2026-09-23T11:00:00.000')], now);
    expect(after.map((r) => r.id), before.map((r) => r.id));
    expect(after[0].payload, isNot(before[0].payload));
    expect(after[0].fireAt, DateTime(2026, 9, 22, 11, 0));
  });

  test('every planned payload is recognisable as an appointment reminder (used to find/cancel them)', () {
    final plan = planAppointmentReminders([appt('a1', '2026-09-22T16:30:00.000')], now);
    expect(plan.every((r) => r.payload.startsWith('appt:a1:')), isTrue);
  });
}
