import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../auth_provider.dart';
import '../theme.dart';
import '../widgets/appointment_card.dart';
import 'appointment_detail_screen.dart';

class AppointmentsListScreen extends StatefulWidget {
  const AppointmentsListScreen({super.key});
  @override
  State<AppointmentsListScreen> createState() => _AppointmentsListScreenState();
}

class _AppointmentsListScreenState extends State<AppointmentsListScreen> {
  List<dynamic>? _appointments;
  String _filter = 'all';
  final _search = TextEditingController();

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

  List<dynamic> get _filtered {
    if (_appointments == null) return [];
    var list = List.of(_appointments!);
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
    final query = _search.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      list = list.where((a) {
        final name = ((a['member'] as Map<String, dynamic>?)?['name'] as String? ?? '').toLowerCase();
        final reason = (a['reason_for_visit'] as String? ?? '').toLowerCase();
        return name.contains(query) || reason.contains(query);
      }).toList();
    }
    list.sort((a, b) => (b['datetime'] as String).compareTo(a['datetime'] as String));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    if (_appointments == null) return const LoadingCenter();
    final filtered = _filtered.cast<Map<String, dynamic>>();
    String? lastDateLabel;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, docFabClearance),
        children: [
          Text('Appointments', style: docSectionHeading().copyWith(fontSize: 21)),
          const SizedBox(height: 2),
          Text('${_appointments!.length} total', style: const TextStyle(color: docMuted, fontSize: 11.5)),
          const SizedBox(height: 12),
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search patient or reason…',
              prefixIcon: const Icon(Icons.search_rounded, size: 19),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: () => setState(() => _search.clear())),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 34,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              _Chip(label: 'All', selected: _filter == 'all', onTap: () => setState(() => _filter = 'all')),
              _Chip(label: 'Upcoming', selected: _filter == 'upcoming', onTap: () => setState(() => _filter = 'upcoming')),
              _Chip(label: 'Completed', selected: _filter == 'completed', onTap: () => setState(() => _filter = 'completed')),
              _Chip(label: 'Follow-ups', selected: _filter == 'followups', onTap: () => setState(() => _filter = 'followups')),
            ]),
          ),
          const SizedBox(height: 14),
          if (filtered.isEmpty) const EmptyState(icon: Icons.event_busy_rounded, message: 'No appointments here.'),
          for (final a in filtered)
            Builder(builder: (context) {
              final dt = DateTime.tryParse(a['datetime'] as String? ?? '')?.toLocal();
              final label = dt == null ? '' : DateFormat('EEEE, MMM d').format(dt);
              final header = label != lastDateLabel;
              lastDateLabel = label;
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (header) Padding(padding: const EdgeInsets.only(top: 6, bottom: 8), child: Text(label.toUpperCase(), style: const TextStyle(fontSize: 10.5, color: docMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.4))),
                AppointmentCard(
                  appt: a,
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => AppointmentDetailScreen(appointmentId: a['id'] as String)));
                    _load();
                  },
                ),
              ]);
            }),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.selected, required this.onTap});

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
