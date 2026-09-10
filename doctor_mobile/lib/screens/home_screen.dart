import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../auth_provider.dart';
import '../theme.dart';
import '../widgets/appointment_card.dart';
import 'analytics_screen.dart';
import 'appointment_detail_screen.dart';
import 'billing_screen.dart';
import 'home_shell.dart';
import 'practice_settings_screen.dart';
import 'templates_screen.dart';

/// Home — a daily briefing, not a second appointments list: a greeting, today's counts at a
/// glance, the next patient to see, a few quick actions, and a compact rest-of-day queue.
/// Browsing/searching/filtering the full appointment history lives on the Appointments tab now —
/// the two screens used to be near-duplicates (both a date-paged, filter-chipped list), which is
/// exactly what this redesign was asked to fix.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<dynamic>? _appointments;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().api;
    final list = await api.getAppointments();
    if (mounted) setState(() => _appointments = list);
  }

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _openAppointment(String id) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => AppointmentDetailScreen(appointmentId: id)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AuthProvider>().session!;
    if (_appointments == null) return const LoadingCenter();

    final now = DateTime.now();
    final today = _appointments!.cast<Map<String, dynamic>>().where((a) {
      final dt = DateTime.tryParse(a['datetime'] as String? ?? '')?.toLocal();
      return dt != null && _sameDay(dt, now);
    }).toList()
      ..sort((a, b) => (a['datetime'] as String).compareTo(b['datetime'] as String));

    final completedToday = today.where((a) => a['status'] == 'completed').length;
    final cancelledToday = today.where((a) => a['status'] == 'cancelled' || a['status'] == 'consent_denied' || a['status'] == 'consent_expired').length;
    final pendingToday = today.length - completedToday - cancelledToday;

    Map<String, dynamic>? nextUp;
    for (final a in today) {
      final dt = DateTime.tryParse(a['datetime'] as String? ?? '')?.toLocal();
      final done = a['status'] == 'completed' || a['status'] == 'cancelled' || a['status'] == 'consent_denied' || a['status'] == 'consent_expired';
      if (dt != null && !done) {
        nextUp = a;
        break;
      }
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, docFabClearance),
        children: [
          Row(children: [
            DoctorAvatar(name: session.displayName),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_greeting(now), style: const TextStyle(fontSize: 12, color: docMuted, fontWeight: FontWeight.w600)),
                Text(session.displayName, style: docSectionHeading().copyWith(fontSize: 19)),
              ]),
            ),
          ]),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: _StatCard(value: '${today.length}', label: 'Patients today', color: docAccentLight, fg: docAccentDark)),
            const SizedBox(width: 10),
            Expanded(child: _StatCard(value: '$completedToday', label: 'Completed', color: docSuccessBg, fg: docSuccess)),
            const SizedBox(width: 10),
            Expanded(child: _StatCard(value: '$pendingToday', label: 'Pending', color: docWarningBg, fg: docWarning)),
          ]),
          const SizedBox(height: 20),
          const Text('Next up', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          if (nextUp == null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: docSurface, borderRadius: BorderRadius.circular(docRadiusMd), border: docCardBorder, boxShadow: docCardShadow),
              child: const Text('Nothing else scheduled for today.', style: TextStyle(color: docMuted, fontSize: 13)),
            )
          else
            _NextUpCard(appt: nextUp, onTap: () => _openAppointment(nextUp!['id'] as String)),
          const SizedBox(height: 20),
          const Text('Quick actions', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _QuickAction(icon: Icons.description_rounded, label: 'Templates', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TemplatesScreen())))),
            const SizedBox(width: 8),
            Expanded(child: _QuickAction(icon: Icons.payments_rounded, label: 'Billing', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BillingScreen())))),
            const SizedBox(width: 8),
            Expanded(child: _QuickAction(icon: Icons.schedule_rounded, label: 'Hours', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PracticeSettingsScreen())))),
            const SizedBox(width: 8),
            Expanded(child: _QuickAction(icon: Icons.bar_chart_rounded, label: 'Reports', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AnalyticsScreen())))),
          ]),
          const SizedBox(height: 20),
          Row(children: [
            const Text('Rest of today', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('${today.length}', style: const TextStyle(fontSize: 13, color: docMuted, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 10),
          if (today.isEmpty)
            const EmptyState(icon: Icons.event_available_rounded, message: 'No appointments today.')
          else
            for (final a in today) AppointmentCard(appt: a, onTap: () => _openAppointment(a['id'] as String)),
        ],
      ),
    );
  }

  static String _greeting(DateTime now) {
    if (now.hour < 12) return 'Good morning';
    if (now.hour < 17) return 'Good afternoon';
    return 'Good evening';
  }
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  final Color fg;
  const _StatCard({required this.value, required this.label, required this.color, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(docRadiusMd)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: fg)),
        const SizedBox(height: 3),
        Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: fg.withValues(alpha: 0.85))),
      ]),
    );
  }
}

class _NextUpCard extends StatelessWidget {
  final Map<String, dynamic> appt;
  final VoidCallback onTap;
  const _NextUpCard({required this.appt, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final member = appt['member'] as Map<String, dynamic>?;
    final datetime = DateTime.tryParse(appt['datetime'] as String? ?? '')?.toLocal();
    final dob = member?['dob'] as String?;
    final age = dob != null ? (DateTime.now().difference(DateTime.tryParse(dob) ?? DateTime.now()).inDays / 365.25).floor() : null;
    final sex = member?['sex'] as String?;
    final reason = appt['reason_for_visit'] as String?;
    final minutesAway = datetime?.difference(DateTime.now()).inMinutes;

    return InkWell(
      borderRadius: BorderRadius.circular(docRadiusLg),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(gradient: const LinearGradient(colors: docPrimaryGradient), borderRadius: BorderRadius.circular(docRadiusLg), boxShadow: docRaisedShadow),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            minutesAway == null ? 'Up next' : (minutesAway <= 0 ? 'Now' : 'In $minutesAway minute${minutesAway == 1 ? '' : 's'}'),
            style: const TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.4),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), shape: BoxShape.circle),
              child: Center(child: Text(_initials(member?['name'] as String? ?? '?'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(member?['name'] ?? 'Unknown patient', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                Text(
                  [if (age != null) '$age yrs', if (sex != null && sex.isNotEmpty) sex[0].toUpperCase() + sex.substring(1), if (reason != null && reason.isNotEmpty) reason].join(' · '),
                  style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                ),
              ]),
            ),
            if (datetime != null)
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(DateFormat('h:mm').format(datetime), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
                Text(DateFormat('a').format(datetime), style: const TextStyle(color: Colors.white70, fontSize: 10)),
              ]),
          ]),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(docRadiusPill)),
            child: const Center(child: Text('Open visit', style: TextStyle(color: docPrimaryDark, fontWeight: FontWeight.w700, fontSize: 12.5))),
          ),
        ]),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(docRadiusMd),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 4),
        decoration: BoxDecoration(color: docSurface, borderRadius: BorderRadius.circular(docRadiusMd), border: docCardBorder, boxShadow: docCardShadow),
        child: Column(children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: docAccentLight, borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, size: 15, color: docAccentDark),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}
