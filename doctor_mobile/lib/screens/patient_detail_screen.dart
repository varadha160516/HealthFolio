import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../auth_provider.dart';
import '../theme.dart';

class PatientDetailScreen extends StatefulWidget {
  final String memberId;
  const PatientDetailScreen({super.key, required this.memberId});
  @override
  State<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends State<PatientDetailScreen> {
  Map<String, dynamic>? _detail;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().api;
    final detail = await api.getMyPatient(widget.memberId);
    if (mounted) setState(() => _detail = detail);
  }

  @override
  Widget build(BuildContext context) {
    if (_detail == null) return const DocGradientScaffold(body: LoadingCenter());
    final member = _detail!['member'] as Map<String, dynamic>;
    final appts = (_detail!['appointments'] as List).cast<Map<String, dynamic>>();
    final dob = member['dob'] as String?;
    final age = dob != null ? (DateTime.now().difference(DateTime.tryParse(dob) ?? DateTime.now()).inDays / 365.25).floor() : null;

    return DocGradientScaffold(
      appBar: AppBar(title: const Text('Patient')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(gradient: LinearGradient(colors: docPrimaryGradient), shape: BoxShape.circle),
              child: Center(child: Text(_initials(member['name'] ?? '?'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(member['name'] ?? '', style: docPageTitle().copyWith(fontSize: 19)),
                Text('${age != null ? '$age years · ' : ''}${_cap(member['sex'])}', style: const TextStyle(color: docMuted, fontSize: 12.5)),
              ]),
            ),
          ]),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: docInfoBg, borderRadius: BorderRadius.circular(docRadiusMd)),
            child: const Row(children: [
              Icon(Icons.info_outline_rounded, color: docInfo, size: 18),
              SizedBox(width: 8),
              Expanded(child: Text('Open their appointment to view allergies, vitals and documents — those need an active, consented visit.', style: TextStyle(color: docInfo, fontSize: 11.5, fontWeight: FontWeight.w600))),
            ]),
          ),
          const SizedBox(height: 18),
          Text('Your visits with ${member['name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
          const SizedBox(height: 10),
          for (final a in appts)
            DocCard(
              padding: const EdgeInsets.all(13),
              child: Column(
                children: [
                  Row(children: [
                    Expanded(child: Text(DateFormat('MMM d, yyyy · h:mm a').format(DateTime.parse(a['datetime']).toLocal()), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700))),
                    StatusPill.forAppointment(a['status']),
                  ]),
                  if (a['diagnosisText'] != null) ...[
                    const SizedBox(height: 6),
                    Align(alignment: Alignment.centerLeft, child: Text('Diagnosis: ${a['diagnosisText']}', style: const TextStyle(fontSize: 12, color: docMuted))),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  String _cap(String? s) => s == null || s.isEmpty ? '' : s[0].toUpperCase() + s.substring(1);
}
