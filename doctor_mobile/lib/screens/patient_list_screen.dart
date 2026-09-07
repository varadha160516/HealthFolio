import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../auth_provider.dart';
import '../theme.dart';
import 'patient_detail_screen.dart';

class PatientListScreen extends StatefulWidget {
  const PatientListScreen({super.key});
  @override
  State<PatientListScreen> createState() => _PatientListScreenState();
}

class _PatientListScreenState extends State<PatientListScreen> {
  List<dynamic>? _patients;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().api;
    final list = await api.getMyPatients();
    if (mounted) setState(() => _patients = list);
  }

  @override
  Widget build(BuildContext context) {
    if (_patients == null) return const LoadingCenter();
    final q = _search.text.trim().toLowerCase();
    final filtered = _patients!.where((p) => q.isEmpty || (p['name'] as String).toLowerCase().contains(q)).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, docFabClearance),
        children: [
          Text('Patients', style: docSectionHeading().copyWith(fontSize: 21)),
          const SizedBox(height: 4),
          const Text('Everyone you\'ve had an appointment with', style: TextStyle(color: docMuted, fontSize: 11.5)),
          const SizedBox(height: 14),
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(hintText: 'Search patient…', prefixIcon: Icon(Icons.search_rounded, size: 20)),
          ),
          const SizedBox(height: 14),
          if (filtered.isEmpty) const EmptyState(icon: Icons.person_search_rounded, message: 'No patients found.'),
          for (final p in filtered.cast<Map<String, dynamic>>())
            _PatientRow(
              patient: p,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PatientDetailScreen(memberId: p['id'] as String))),
            ),
        ],
      ),
    );
  }
}

class _PatientRow extends StatelessWidget {
  final Map<String, dynamic> patient;
  final VoidCallback onTap;
  const _PatientRow({required this.patient, required this.onTap});

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final dob = patient['dob'] as String?;
    final age = dob != null ? (DateTime.now().difference(DateTime.tryParse(dob) ?? DateTime.now()).inDays / 365.25).floor() : null;
    final sex = (patient['sex'] as String?);
    final lastVisit = DateTime.tryParse(patient['last_visit_at'] as String? ?? '')?.toLocal();

    return InkWell(
      borderRadius: BorderRadius.circular(docRadiusMd),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(color: docSurface, borderRadius: BorderRadius.circular(docRadiusMd), border: docCardBorder, boxShadow: docCardShadow),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(gradient: LinearGradient(colors: docPrimaryGradient), shape: BoxShape.circle),
            child: Center(child: Text(_initials(patient['name'] ?? '?'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${patient['name']}${age != null ? ' · $age${sex != null && sex.isNotEmpty ? sex[0].toUpperCase() : ''}' : ''}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                'Last visit: ${lastVisit != null ? DateFormat('MMM d').format(lastVisit) : '—'}${patient['lastDiagnosis'] != null ? ' · ${patient['lastDiagnosis']}' : ''}',
                style: const TextStyle(fontSize: 11.5, color: docMuted),
              ),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: docMutedDim),
        ]),
      ),
    );
  }
}
