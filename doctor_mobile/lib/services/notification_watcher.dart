import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api_client.dart';
import 'local_notifier.dart';

/// Polls the doctor's notification feed while the app is running and turns NEW events into
/// (a) an unread badge, (b) an OS notification if the app is in the background, or (c) an in-app
/// callback if the doctor is actively using it. The server-side feed (notifyProvider) is the source
/// of truth; this only decides how a fresh item reaches the doctor's eyes.
///
/// Polling is the honest limit here: it works while the process is alive but cannot wake a fully
/// closed app — that needs real push (FCM).
class NotificationWatcher extends ChangeNotifier {
  final ApiClient api;
  final String storageKey;
  NotificationWatcher({required this.api, required this.storageKey});

  /// Called (instead of an OS notification) when new items arrive while the app is on screen.
  void Function(List<Map<String, dynamic>> items)? onForegroundNew;

  Timer? _timer;
  bool _polling = false;
  int unreadCount = 0;

  Future<void> start() async {
    await LocalNotifier.instance.init();
    await poll();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => poll());
  }

  Future<void> poll() async {
    if (_polling) return;
    _polling = true;
    try {
      final items = (await api.getNotifications()).cast<Map<String, dynamic>>();
      final unread = items.where((n) => n['read_at'] == null).toList();

      final prefs = await SharedPreferences.getInstance();
      final firstRun = !prefs.containsKey(storageKey);
      final seen = (prefs.getStringList(storageKey) ?? const <String>[]).toSet();
      final fresh = firstRun ? <Map<String, dynamic>>[] : unread.where((n) => !seen.contains(n['id'])).toList();

      // First ever poll for this account just records what already exists — otherwise installing the
      // app (or switching accounts) would fire a notification for the whole backlog.
      seen.addAll(unread.map((n) => n['id'] as String));
      await prefs.setStringList(storageKey, seen.toList().reversed.take(300).toList());

      // Derived "follow-up due today" items can never be marked read, so they don't count as unread.
      final count = unread.where((n) => !(n['id'] as String).startsWith('followup-')).length;
      if (count != unreadCount) {
        unreadCount = count;
        notifyListeners();
      }

      if (fresh.isNotEmpty) {
        final foreground = WidgetsBinding.instance.lifecycleState == null || WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
        if (foreground) {
          onForegroundNew?.call(fresh);
        } else {
          for (final n in fresh.take(3)) {
            await LocalNotifier.instance.show(
              id: (n['id'] as String).hashCode & 0x7fffffff,
              title: n['title'] as String? ?? 'ClinDesk',
              body: n['body'] as String? ?? '',
              payload: n['related_appointment_id'] as String?,
            );
          }
        }
      }
    } catch (_) {
      // A transient network failure just means this poll saw nothing — the next one retries.
    } finally {
      _polling = false;
    }
  }

  /// Called after the notifications screen has marked items read, so the badge clears immediately.
  Future<void> refresh() => poll();

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
