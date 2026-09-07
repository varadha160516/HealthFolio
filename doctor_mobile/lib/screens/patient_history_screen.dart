import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../auth_provider.dart';
import '../theme.dart';

class PatientHistoryScreen extends StatefulWidget {
  final String appointmentId;
  const PatientHistoryScreen({super.key, required this.appointmentId});
  @override
  State<PatientHistoryScreen> createState() => _PatientHistoryScreenState();
}

class _PatientHistoryScreenState extends State<PatientHistoryScreen> {
  Map<String, dynamic>? _appt;
  List<dynamic>? _history;
  Map<String, dynamic>? _today;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().api;
    final appt = await api.getAppointment(widget.appointmentId);
    final history = await api.getPatientVisitHistory(widget.appointmentId);
    Map<String, dynamic>? today;
    try {
      today = await api.getVisitSummary(widget.appointmentId);
    } catch (_) {}
    if (mounted) {
      setState(() {
        _appt = appt;
        _history = history;
        _today = today;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_history == null) return const DocGradientScaffold(body: LoadingCenter());
    final member = _appt?['member'] as Map<String, dynamic>?;
    final entries = <Map<String, dynamic>>[
      if (_today != null) {'datetime': _appt?['datetime'], 'isToday': true, ..._today!},
      for (final h in _history!.cast<Map<String, dynamic>>()) h,
    ];

    return DocGradientScaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(member?['name'] ?? 'Patient history', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const Text('Visit timeline', style: TextStyle(fontSize: 11, color: docMuted)),
        ]),
      ),
      body: entries.isEmpty
          ? const EmptyState(icon: Icons.history_toggle_off_rounded, message: 'No past visits with this patient yet.')
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: entries.length,
              itemBuilder: (context, i) => _TimelineEntry(entry: entries[i], isLast: i == entries.length - 1),
            ),
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  final Map<String, dynamic> entry;
  final bool isLast;
  const _TimelineEntry({required this.entry, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final dt = DateTime.tryParse(entry['datetime'] as String? ?? '')?.toLocal();
    final isToday = entry['isToday'] == true;
    final notes = entry['consultationNotes'] as Map<String, dynamic>?;
    final prescription = entry['prescription'] as Map<String, dynamic>?;
    final labOrders = (entry['labOrders'] as List?) ?? [];
    final symptoms = (notes?['symptoms'] as List?)?.cast<String>() ?? [];
    final lineItems = (prescription?['lineItems'] as List?) ?? [];

    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 16,
          child: Column(children: [
            Container(width: 11, height: 11, margin: const EdgeInsets.only(top: 4), decoration: BoxDecoration(color: isToday ? docGreen : docPrimary, shape: BoxShape.circle)),
            if (!isLast) Expanded(child: Container(width: 2, margin: const EdgeInsets.only(top: 4), color: docAccentLight)),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(dt != null ? (isToday ? 'TODAY' : DateFormat('MMM d, yyyy').format(dt).toUpperCase()) : '', style: const TextStyle(fontSize: 10.5, color: docMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
              const SizedBox(height: 7),
              DocCard(
                padding: const EdgeInsets.all(13),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (symptoms.isNotEmpty) _kv('Symptoms', symptoms.join(' · ')),
                  if (prescription?['diagnosis_text'] != null) _kv('Diagnosis', prescription!['diagnosis_text']),
                  if (lineItems.isNotEmpty) _kv('Medication', lineItems.map((li) => li['medicine_name']).join(' · ')),
                  if (labOrders.isNotEmpty) _kv('Lab', labOrders.expand((o) => (o['test_names'] as List)).join(' · ')),
                  if (symptoms.isEmpty && prescription?['diagnosis_text'] == null && lineItems.isEmpty && labOrders.isEmpty)
                    const Text('No details recorded for this visit.', style: TextStyle(fontSize: 12, color: docMuted)),
                ]),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: RichText(text: TextSpan(children: [
          TextSpan(text: '$k: ', style: const TextStyle(color: docMuted, fontSize: 12, fontWeight: FontWeight.w600)),
          TextSpan(text: v, style: const TextStyle(color: docTextPrimary, fontSize: 12)),
        ])),
      );
}
