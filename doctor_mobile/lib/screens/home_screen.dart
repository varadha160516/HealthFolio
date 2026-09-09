import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../auth_provider.dart';
import '../theme.dart';
import '../widgets/appointment_card.dart';
import 'appointment_detail_screen.dart';
import 'home_shell.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<dynamic>? _appointments;
  DateTime _date = DateTime.now();
  String _filter = 'all';

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

  List<dynamic> get _filtered {
    if (_appointments == null) return [];
    var list = _appointments!.where((a) {
      final dt = DateTime.tryParse(a['datetime'] as String? ?? '')?.toLocal();
      return dt != null && _sameDay(dt, _date);
    }).toList();
    switch (_filter) {
      case 'upcoming':
        list = list.where((a) => a['status'] == 'scheduled').toList();
        break;
      case 'waiting':
        list = list.where((a) => a['status'] == 'checked_in' || a['status'] == 'consent_requested').toList();
        break;
      case 'completed':
        list = list.where((a) => a['status'] == 'completed').toList();
        break;
      case 'followups':
        list = list.where((a) => a['is_follow_up'] == 1).toList();
        break;
    }
    list.sort((a, b) => (a['datetime'] as String).compareTo(b['datetime'] as String));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AuthProvider>().session!;
    if (_appointments == null) return const LoadingCenter();
    final filtered = _filtered;

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
                const Text('Good day', style: TextStyle(fontSize: 12, color: docMuted, fontWeight: FontWeight.w600)),
                Text(session.displayName, style: docSectionHeading().copyWith(fontSize: 19)),
              ]),
            ),
          ]),
          const SizedBox(height: 18),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(
              onPressed: () => setState(() => _date = _date.subtract(const Duration(days: 1))),
              icon: const Icon(Icons.chevron_left_rounded),
              style: IconButton.styleFrom(backgroundColor: docSurface, side: const BorderSide(color: docBorder)),
            ),
            const SizedBox(width: 14),
            Text(DateFormat('EEE, MMM d').format(_date).toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: 0.3)),
            const SizedBox(width: 14),
            IconButton(
              onPressed: () => setState(() => _date = _date.add(const Duration(days: 1))),
              icon: const Icon(Icons.chevron_right_rounded),
              style: IconButton.styleFrom(backgroundColor: docSurface, side: const BorderSide(color: docBorder)),
            ),
          ]),
          const SizedBox(height: 18),
          Row(children: [
            Text(_sameDay(_date, DateTime.now()) ? "Today's appointments" : 'Appointments', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('${_filtered.length}', style: const TextStyle(fontSize: 13, color: docMuted, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            height: 34,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              _FilterChip(label: 'All', selected: _filter == 'all', onTap: () => setState(() => _filter = 'all')),
              _FilterChip(label: 'Upcoming', selected: _filter == 'upcoming', onTap: () => setState(() => _filter = 'upcoming')),
              _FilterChip(label: 'Completed', selected: _filter == 'completed', onTap: () => setState(() => _filter = 'completed')),
              _FilterChip(label: 'Follow-ups', selected: _filter == 'followups', onTap: () => setState(() => _filter = 'followups')),
            ]),
          ),
          const SizedBox(height: 14),
          if (filtered.isEmpty)
            const EmptyState(icon: Icons.event_available_rounded, message: 'No appointments here.')
          else
            for (final a in filtered.cast<Map<String, dynamic>>())
              AppointmentCard(
                appt: a,
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => AppointmentDetailScreen(appointmentId: a['id'] as String)));
                  _load();
                },
              ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(docRadiusPill),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(color: selected ? docPrimary : docSurface, borderRadius: BorderRadius.circular(docRadiusPill), border: selected ? null : Border.all(color: docBorder)),
          child: Text(label, style: TextStyle(color: selected ? Colors.white : docTextPrimary, fontWeight: FontWeight.w600, fontSize: 12.5)),
        ),
      ),
    );
  }
}
