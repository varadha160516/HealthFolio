import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Thin wrapper over flutter_local_notifications for ClinDesk — shows an OS notification for an
/// event the app already knows about. This is NOT server push: a notification can only appear
/// while the app's process is alive (foreground, or shortly after backgrounding). Reaching a doctor
/// whose app has been fully closed needs a push transport (FCM) — see notifyProvider() on the
/// server, which is where that would hook in.
class LocalNotifier {
  LocalNotifier._();
  static final LocalNotifier instance = LocalNotifier._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _channel = AndroidNotificationDetails(
    'clindesk_events',
    'Clinic activity',
    channelDescription: 'Patient consent, bookings, cancellations and lab reports',
    importance: Importance.high,
    priority: Priority.high,
  );

  Future<void> init() async {
    if (_ready) return;
    await _plugin.initialize(settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
    // Android 13+ needs an explicit runtime grant; a no-op on older versions.
    await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
    _ready = true;
  }

  Future<void> show({required int id, required String title, required String body, String? payload}) async {
    if (!_ready) return;
    await _plugin.show(id: id, title: title, body: body, notificationDetails: const NotificationDetails(android: _channel), payload: payload);
  }
}
