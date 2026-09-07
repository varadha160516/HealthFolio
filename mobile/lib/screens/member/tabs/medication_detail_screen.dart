import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../auth_provider.dart';
import '../../../theme.dart';
import '../../../utils/medication_schedule_infer.dart';
import '../../../utils/motion.dart';
import '../../../widgets/section_card.dart';
import 'add_medication_sheet.dart';
import 'document_viewer_screen.dart';

class MedicationDetailScreen extends StatefulWidget {
  final String medicationId;
  final String memberId;
  const MedicationDetailScreen({super.key, required this.medicationId, required this.memberId});

  @override
  State<MedicationDetailScreen> createState() => _MedicationDetailScreenState();
}

class _MedicationDetailScreenState extends State<MedicationDetailScreen> {
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().api;
    final data = await api.getMedication(widget.medicationId);
    if (mounted) setState(() => _data = data);
  }

  Future<void> _logDose(String? time, String status) async {
    final api = context.read<AuthProvider>().api;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    await api.logMedicationDose(widget.medicationId, {'date': today, 'time': time, 'status': status});
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_data == null) return const Scaffold(backgroundColor: careloopBg, body: LoadingCenter());
    final schedule = _data!['schedule'] as Map<String, dynamic>;
    final source = _data!['source'] as Map<String, dynamic>?;
    final today = (_data!['today'] as List<dynamic>).cast<Map<String, dynamic>>();
    final frequency = schedule['frequency'] as String;
    final times = (schedule['times'] as List).cast<String>();
    final status = schedule['status'] as String;

    return Scaffold(
      backgroundColor: careloopBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(width: 34, height: 34, decoration: BoxDecoration(color: careloopSurface, shape: BoxShape.circle, border: careloopCardBorder), child: const Icon(Icons.arrow_back_ios_new_rounded, size: 15)),
                ),
                const SizedBox(width: 10),
                const Text('Medication', style: TextStyle(color: careloopMuted, fontWeight: FontWeight.w600, fontSize: 13)),
              ]),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: careloopSurface, borderRadius: BorderRadius.circular(careloopRadiusMd), border: careloopCardBorder, boxShadow: careloopCardShadow),
                      child: Row(children: [
                        Container(width: 46, height: 46, decoration: BoxDecoration(color: careloopAbnormalBg, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.medication_rounded, color: careloopDanger, size: 22)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(schedule['medicine_name'], style: careloopSectionHeading().copyWith(fontSize: 17)),
                            if ((schedule['strength'] as String?)?.isNotEmpty == true) Text(schedule['strength'], style: const TextStyle(color: careloopMuted, fontSize: 11.5)),
                          ]),
                        ),
                        StatusPill(status[0].toUpperCase() + status.substring(1), tone: status == 'active' ? PillTone.success : (status == 'stopped' ? PillTone.danger : PillTone.neutral)),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _FieldLabel('Dosage'),
                          Text(schedule['dose_amount'] ?? '—', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                          Text(frequencyLabel(frequency, times, schedule['day_of_week'] as int?), style: const TextStyle(color: careloopMuted, fontSize: 11.5)),
                          const _FieldLabel('Schedule'),
                          Text(
                            frequency == 'as_needed' ? 'Take when needed' : (times.isEmpty ? '—' : times.map(formatTime).join(', ')),
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          const _FieldLabel('Duration'),
                          Text(
                            '${schedule['start_date']}${schedule['end_date'] != null ? ' – ${schedule['end_date']}' : ' – ongoing'}',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    if (today.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      SectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _FieldLabel('Today'),
                            for (final t in today)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(children: [
                                  Text(formatTime(t['time']), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                  const Spacer(),
                                  _DoseStatusPill(status: t['status']),
                                  if (t['status'] == 'due') ...[
                                    const SizedBox(width: 6),
                                    TextButton(onPressed: () => _logDose(t['time'], 'taken'), child: const Text('Mark taken')),
                                  ],
                                ]),
                              ),
                          ],
                        ),
                      ),
                    ],
                    if ((schedule['prescribed_by'] as String?)?.isNotEmpty == true || (schedule['purpose'] as String?)?.isNotEmpty == true) ...[
                      const SizedBox(height: 10),
                      SectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if ((schedule['prescribed_by'] as String?)?.isNotEmpty == true) ...[
                              const _FieldLabel('Prescribed by'),
                              Text(schedule['prescribed_by'], style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            ],
                            if ((schedule['purpose'] as String?)?.isNotEmpty == true) ...[
                              const _FieldLabel('Purpose'),
                              Text(schedule['purpose'], style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            ],
                          ],
                        ),
                      ),
                    ],
                    if (source != null) ...[
                      const SizedBox(height: 10),
                      SectionCard(
                        child: InkWell(
                          onTap: () => Navigator.of(context).push(pushRoute(DocumentViewerScreen(documentId: source['document_id']))),
                          child: Row(children: [
                            Container(width: 34, height: 34, decoration: BoxDecoration(color: careloopAccentLight, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.description_rounded, color: careloopAccent, size: 16)),
                            const SizedBox(width: 10),
                            const Expanded(child: Text('View original prescription', style: TextStyle(color: careloopAccent, fontWeight: FontWeight.w600, fontSize: 13))),
                            const Icon(Icons.chevron_right_rounded, color: careloopAccent),
                          ]),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: () async {
                        final navigator = Navigator.of(context);
                        final result = await showModalBottomSheet<dynamic>(
                          context: context,
                          isScrollControlled: true,
                          builder: (_) => AddMedicationSheet(memberId: widget.memberId, scheduleId: widget.medicationId, initial: schedule),
                        );
                        if (!mounted) return;
                        if (result == 'deleted') {
                          navigator.pop(true);
                        } else if (result == true) {
                          _load();
                        }
                      },
                      child: const Text('Edit medication'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 3),
        child: Text(text.toUpperCase(), style: const TextStyle(color: careloopMutedDim, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
      );
}

class _DoseStatusPill extends StatelessWidget {
  final String status;
  const _DoseStatusPill({required this.status});
  @override
  Widget build(BuildContext context) {
    return switch (status) {
      'taken' => const StatusPill('Taken', tone: PillTone.success),
      'skipped' => const StatusPill('Skipped', tone: PillTone.danger),
      'due' => const StatusPill('Due', tone: PillTone.warning),
      _ => const StatusPill('Upcoming', tone: PillTone.info),
    };
  }
}
