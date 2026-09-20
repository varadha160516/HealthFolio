import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

/// One OS-scheduled reminder, before it's handed to the plugin.
class PlannedReminder {
  final int id;
  final DateTime fireAt;
  final String title;
  final String body;
  final String payload;
  const PlannedReminder({required this.id, required this.fireAt, required this.title, required this.body, required this.payload});
}

// Two reminders per visit: the day before, and an hour before.
const _plan = <(int, Duration, String)>[
  (0, Duration(hours: 24), 'Appointment tomorrow'),
  (1, Duration(hours: 1), 'Appointment in 1 hour'),
];

// Notification ids are 32-bit ints; a visit's two reminders share a 29-bit base derived from its id.
int reminderId(String appointmentId, int kind) => (appointmentId.hashCode & 0x1fffffff) * 4 + kind;

/// Pure planning step (no plugin involved, so it's unit-tested): which reminders SHOULD exist for
/// this appointment list at [now]. Only visits still 'scheduled' and in the future get any, and a
/// reminder whose moment has already passed (or is about to) is skipped rather than fired late.
///
/// Appointment datetimes are stored either as the wall-clock string the member picked (no zone —
/// parses as local) or as a UTC instant (doctor-scheduled follow-ups); both resolve to the right
/// absolute moment.
List<PlannedReminder> planAppointmentReminders(List<Map<String, dynamic>> appointments, DateTime now) {
  final planned = <PlannedReminder>[];
  for (final a in appointments) {
    if (a['status'] != 'scheduled') continue;
    final raw = a['datetime'];
    final when = raw is String ? DateTime.tryParse(raw) : null;
    if (when == null || !when.isAfter(now)) continue;
    final id = a['id'] as String;
    final who = a['member']?['name'] as String? ?? 'Your visit';
    final doctor = a['provider']?['name'] as String? ?? 'your doctor';
    final time = DateFormat('h:mm a').format(when.toLocal());
    for (final (kind, lead, title) in _plan) {
      final fireAt = when.subtract(lead);
      if (!fireAt.isAfter(now.add(const Duration(seconds: 30)))) continue;
      planned.add(PlannedReminder(
        id: reminderId(id, kind),
        fireAt: fireAt,
        title: title,
        body: '$who with $doctor at $time',
        // The payload carries the visit time, so a reschedule (same id, new time) reads as a change.
        payload: 'appt:$id:${when.millisecondsSinceEpoch}:$kind',
      ));
    }
  }
  return planned;
}

/// Appointment reminders and time-sensitive alerts, as LOCAL notifications.
///
/// Reminders are scheduled with the OS alarm manager, so they fire even when the app is closed —
/// this is not server push. What it can't do: learn about an appointment the app has never
/// fetched (a doctor-created follow-up shows up on the next poll after the app is opened), or wake
/// a closed app for a consent request. Both need real push (FCM); see notifyProvider() on the
/// server for where that would hook in.
class ReminderService {
  ReminderService._();
  static final ReminderService instance = ReminderService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  String _lastSignature = '';
  bool _firstSync = true;

  static const _reminders = AndroidNotificationDetails(
    'appointment_reminders',
    'Appointment reminders',
    channelDescription: 'Reminders before your upcoming visits',
    importance: Importance.high,
    priority: Priority.high,
  );
  static const _alerts = AndroidNotificationDetails(
    'care_alerts',
    'Care alerts',
    channelDescription: 'Time-sensitive requests, such as a doctor asking for access to your records',
    importance: Importance.max,
    priority: Priority.high,
  );

  Future<void> init({bool askPermission = true}) async {
    if (!_ready) {
      await _plugin.initialize(settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
      _ready = true;
    }
    // Android 13+ needs an explicit runtime grant; a no-op on older versions.
    if (askPermission) await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
  }

  /// Brings the OS-scheduled reminders in line with [appointments] (the full list from
  /// GET /appointments). Idempotent and cheap to call on every poll: it skips entirely when nothing
  /// changed, and otherwise only touches reminders whose time/text changed — so a reschedule moves
  /// its reminders and a cancelled or completed visit loses them.
  Future<void> syncAppointmentReminders(List<Map<String, dynamic>> appointments) async {
    if (!_ready) return;
    final desired = {for (final r in planAppointmentReminders(appointments, DateTime.now())) r.id: r};

    final signature = (desired.values.map((r) => '${r.id}|${r.payload}|${r.body}').toList()..sort()).join(';');
    if (signature == _lastSignature) return;

    final pending = (await _plugin.pendingNotificationRequests()).where((p) => (p.payload ?? '').startsWith('appt:')).toList();
    final keep = <int>{};
    for (final p in pending) {
      final want = desired[p.id];
      // On the first sync of a launch, don't trust that a "pending" record still has a live OS
      // alarm behind it: a force-stop clears Android's alarms but not the plugin's own records.
      // Rescheduling everything once per launch is cheap and self-heals that.
      if (!_firstSync && want != null && want.payload == p.payload && want.body == p.body) {
        keep.add(p.id);
      } else {
        await _plugin.cancel(id: p.id);
      }
    }
    for (final r in desired.values) {
      if (keep.contains(r.id)) continue;
      await _plugin.zonedSchedule(
        id: r.id,
        title: r.title,
        body: r.body,
        scheduledDate: tz.TZDateTime.fromMillisecondsSinceEpoch(tz.UTC, r.fireAt.millisecondsSinceEpoch),
        notificationDetails: const NotificationDetails(android: _reminders),
        // Inexact: a reminder a few minutes late is fine, and it avoids the exact-alarm permission.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: r.payload,
      );
    }
    _lastSignature = signature;
    _firstSync = false;
  }

  /// A doctor is waiting on the member's answer and the request expires — worth an OS alert if the
  /// app isn't on screen.
  Future<void> showConsentRequest({required String appointmentId, required String providerName, required String patientName}) async {
    if (!_ready) return;
    await _plugin.show(
      id: 0x40000000 + (appointmentId.hashCode & 0x3fffffff),
      title: 'Access request from $providerName',
      body: 'Approve or deny access to $patientName\'s records for the visit happening now.',
      notificationDetails: const NotificationDetails(android: _alerts),
      payload: 'consent:$appointmentId',
    );
  }

  /// On logout: a shared device must not keep firing the previous account's reminders.
  Future<void> clearAll() async {
    await init(askPermission: false); // works from the logout path even if nothing initialised us yet
    _lastSignature = '';
    _firstSync = true;
    await _plugin.cancelAll();
  }
}
