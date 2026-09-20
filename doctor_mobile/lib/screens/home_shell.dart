import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth_provider.dart';
import '../services/notification_watcher.dart';
import '../theme.dart';
import 'home_screen.dart';
import 'appointments_list_screen.dart';
import 'patient_list_screen.dart';
import 'more_screen.dart';
import 'notifications_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  late final NotificationWatcher _watcher;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    _watcher = NotificationWatcher(api: auth.api, storageKey: 'notif_seen_${auth.session?.providerId ?? 'me'}')
      ..onForegroundNew = _showInApp;
    _watcher.start();
  }

  @override
  void dispose() {
    _watcher.dispose();
    super.dispose();
  }

  // The doctor is looking at the app right now, so an OS notification would be redundant — a
  // snackbar with a way into the feed is the right cue.
  void _showInApp(List<Map<String, dynamic>> items) {
    if (!mounted) return;
    final first = items.first;
    final more = items.length > 1 ? ' (+${items.length - 1} more)' : '';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('${first['title']} — ${first['body']}$more'),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(label: 'View', onPressed: _openNotifications),
      ));
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
    _watcher.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const HomeScreen(),
      const AppointmentsListScreen(),
      const PatientListScreen(),
      const MoreScreen(),
    ];

    return DocGradientScaffold(
      appBar: AppBar(
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(gradient: const LinearGradient(colors: docPrimaryGradient), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.medical_services_rounded, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 9),
          Text('ClinDesk', style: docSectionHeading().copyWith(fontSize: 18)),
        ]),
        actions: [
          ListenableBuilder(
            listenable: _watcher,
            builder: (context, _) => IconButton(
              icon: Badge(
                isLabelVisible: _watcher.unreadCount > 0,
                label: Text('${_watcher.unreadCount}'),
                child: const Icon(Icons.notifications_rounded),
              ),
              onPressed: _openNotifications,
            ),
          ),
        ],
      ),
      body: pages[_tab],
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Color(0x1FA396DC), blurRadius: 20, offset: Offset(0, -6))]),
        child: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          backgroundColor: docSurface,
          indicatorColor: docAccentLight,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.calendar_month_rounded), label: 'Appointments'),
            NavigationDestination(icon: Icon(Icons.people_alt_rounded), label: 'Patients'),
            NavigationDestination(icon: Icon(Icons.more_horiz_rounded), label: 'More'),
          ],
        ),
      ),
    );
  }
}

class DoctorAvatar extends StatelessWidget {
  final String name;
  final double size;
  const DoctorAvatar({super.key, required this.name, this.size = 38});

  String get _initials {
    final parts = name.replaceFirst('Dr. ', '').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(gradient: LinearGradient(colors: docPrimaryGradient), shape: BoxShape.circle, boxShadow: docRaisedShadow),
      child: Center(child: Text(_initials, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: size * 0.36))),
    );
  }
}
