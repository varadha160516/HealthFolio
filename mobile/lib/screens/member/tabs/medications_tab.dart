import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../auth_provider.dart';
import '../../../theme.dart';
import '../../../utils/medication_schedule_infer.dart';
import '../../../utils/motion.dart';
import '../../../widgets/section_card.dart';
import 'add_medication_sheet.dart';
import 'import_prescription_sheet.dart';
import 'medication_detail_screen.dart';
import 'prescription_review_screen.dart';

enum _Segment { active, history, cabinet }

class MedicationsTab extends StatefulWidget {
  final String memberId;
  const MedicationsTab({super.key, required this.memberId});
  @override
  State<MedicationsTab> createState() => _MedicationsTabState();
}

class _MedicationsTabState extends State<MedicationsTab> {
  List<dynamic>? _schedules;
  Map<String, dynamic>? _today;
  _Segment _segment = _Segment.active;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().api;
    final results = await Future.wait([api.getMedications(widget.memberId), api.getMedicationsToday(widget.memberId)]);
    if (mounted) {
      setState(() {
        _schedules = results[0] as List<dynamic>;
        _today = results[1] as Map<String, dynamic>;
      });
    }
  }

  Future<void> _openAdd() async {
    final result = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (_) => AddMedicationSheet(memberId: widget.memberId));
    if (result == true) _load();
  }

  Future<void> _openImport() async {
    final uploadResult = await showModalBottomSheet<dynamic>(context: context, isScrollControlled: true, builder: (_) => ImportPrescriptionSheet(memberId: widget.memberId));
    if (uploadResult is! Map || !mounted) return;
    final documentId = uploadResult['documentId'] as String?;
    if (documentId == null) return;
    if (uploadResult['prescriptionId'] == null) {
      // Extraction failed (manual_entry_required) — the document is still saved, just nothing to review yet.
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Saved, but couldn't read it automatically — add the medicines manually.")));
      return;
    }
    final added = await Navigator.of(context).push<int>(pushRoute(PrescriptionReviewScreen(memberId: widget.memberId, documentId: documentId)));
    if (added != null && added > 0) _load();
  }

  Future<void> _openDetail(String id) async {
    await Navigator.of(context).push(pushRoute(MedicationDetailScreen(medicationId: id, memberId: widget.memberId)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_schedules == null || _today == null) return const LoadingCenter();

    final schedules = _schedules!.cast<Map<String, dynamic>>();
    final active = schedules.where((s) => s['status'] == 'active').toList();
    final history = schedules.where((s) => s['status'] != 'active').toList();
    final asNeededActive = active.where((s) => s['frequency'] == 'as_needed').length;
    final scheduledToday = (_today!['scheduled'] as List).cast<Map<String, dynamic>>();
    final dueCount = scheduledToday.where((d) => d['status'] == 'due').length;
    final nextDue = scheduledToday.where((d) => d['status'] == 'due' || d['status'] == 'upcoming').toList();

    final byScheduleToday = <String, Map<String, dynamic>>{};
    for (final d in scheduledToday) {
      byScheduleToday.putIfAbsent(d['schedule_id'], () => d); // earliest wins — list is time-sorted
    }
    final prnLastTaken = <String, String?>{for (final p in (_today!['prn'] as List).cast<Map<String, dynamic>>()) p['schedule_id']: p['last_taken_at']};

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, careloopFabClearance),
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Medications', style: careloopPageTitle().copyWith(fontSize: 21)),
                const SizedBox(height: 2),
                const Text('Manage your medicines', style: TextStyle(color: careloopMuted, fontSize: 11.5)),
              ]),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: _openAdd,
              child: Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(gradient: LinearGradient(colors: careloopPrimaryGradient), shape: BoxShape.circle),
                child: const Icon(Icons.add_rounded, color: Colors.white, size: 18),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          if (dueCount > 0)
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(color: careloopAbnormalBg, borderRadius: BorderRadius.circular(18), border: Border.all(color: careloopDanger.withValues(alpha: 0.25))),
              child: Row(children: [
                Container(width: 10, height: 10, decoration: const BoxDecoration(color: careloopDanger, shape: BoxShape.circle)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('$dueCount dose${dueCount == 1 ? '' : 's'} due today', style: const TextStyle(color: careloopDanger, fontWeight: FontWeight.w700, fontSize: 13.5)),
                    if (nextDue.isNotEmpty)
                      Text('Next: ${nextDue.first['medicine_name']} · ${formatTime(nextDue.first['time'])}', style: TextStyle(color: careloopDanger.withValues(alpha: 0.75), fontSize: 11)),
                  ]),
                ),
              ]),
            ),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: careloopSurface, border: careloopCardBorder, borderRadius: BorderRadius.circular(999)),
            child: Row(children: [
              for (final s in _Segment.values)
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => setState(() => _segment = s),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(color: _segment == s ? careloopAccentLight : Colors.transparent, borderRadius: BorderRadius.circular(999)),
                      child: Text(
                        switch (s) { _Segment.active => 'Active', _Segment.history => 'History', _Segment.cabinet => 'Cabinet' },
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _segment == s ? careloopAccent : careloopMuted),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 14),
          if (_segment == _Segment.cabinet)
            _Cabinet(active: active.length - asNeededActive, asNeeded: asNeededActive, completed: history.where((s) => s['status'] == 'completed').length, stopped: history.where((s) => s['status'] == 'stopped').length)
          else ...[
            for (final s in (_segment == _Segment.active ? active : history))
              _MedicationCard(
                schedule: s,
                todayStatus: s['frequency'] == 'as_needed' ? null : byScheduleToday[s['id']]?['status'],
                lastTakenAt: s['frequency'] == 'as_needed' ? prnLastTaken[s['id']] : null,
                onTap: () => _openDetail(s['id']),
              ),
            if ((_segment == _Segment.active ? active : history).isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(_segment == _Segment.active ? 'No active medications yet.' : 'No past medications yet.', textAlign: TextAlign.center, style: const TextStyle(color: careloopMuted)),
              ),
          ],
          const SizedBox(height: 8),
          InkWell(
            onTap: _openAdd,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Row(children: [
                Icon(Icons.add_rounded, size: 16, color: careloopAccent),
                SizedBox(width: 6),
                Text('Add medication', style: TextStyle(color: careloopAccent, fontWeight: FontWeight.w600, fontSize: 12.5)),
              ]),
            ),
          ),
          const Divider(height: 20),
          _ImportRow(icon: Icons.qr_code_scanner_rounded, title: 'Import prescription', subtitle: 'Photo, camera or a document', onTap: _openImport),
          const SizedBox(height: 8),
          _ImportRow(icon: Icons.folder_rounded, title: 'Import from Files', subtitle: 'PDF or document', onTap: _openImport),
        ],
      ),
    );
  }
}

class _MedicationCard extends StatelessWidget {
  final Map<String, dynamic> schedule;
  final String? todayStatus;
  final String? lastTakenAt;
  final VoidCallback onTap;
  const _MedicationCard({required this.schedule, required this.todayStatus, required this.lastTakenAt, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final frequency = schedule['frequency'] as String;
    final times = (schedule['times'] as List).cast<String>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: InkWell(
        borderRadius: BorderRadius.circular(careloopRadiusMd),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(color: careloopSurface, borderRadius: BorderRadius.circular(careloopRadiusMd), border: careloopCardBorder, boxShadow: careloopCardShadow),
          child: Row(children: [
            Container(width: 38, height: 38, decoration: BoxDecoration(color: careloopAbnormalBg, borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.medication_rounded, color: careloopDanger, size: 18)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(schedule['medicine_name'], style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                Text(
                  [schedule['strength'], frequencyLabel(frequency, times, schedule['day_of_week'] as int?)].where((v) => v != null && (v as String).isNotEmpty).join(' · '),
                  style: const TextStyle(color: careloopMuted, fontSize: 11),
                ),
              ]),
            ),
            if (frequency == 'as_needed')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: careloopSurfaceRaised, borderRadius: BorderRadius.circular(999)),
                child: const Text('PRN', style: TextStyle(color: careloopMuted, fontWeight: FontWeight.w700, fontSize: 10.5)),
              )
            else if (todayStatus != null)
              _StatusChip(status: todayStatus!),
          ]),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});
  @override
  Widget build(BuildContext context) {
    final (bg, fg, label, icon) = switch (status) {
      'taken' => (careloopGreenBg, careloopGreen, 'Taken', Icons.check_rounded),
      'skipped' => (careloopAbnormalBg, careloopDanger, 'Skipped', Icons.close_rounded),
      'due' => (careloopWarningBg, careloopWarning, 'Due', null),
      _ => (careloopNewBg, careloopInfo, 'Upcoming', null),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) Icon(icon, size: 11, color: fg) else Container(width: 6, height: 6, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 10.5)),
      ]),
    );
  }
}

class _Cabinet extends StatelessWidget {
  final int active;
  final int asNeeded;
  final int completed;
  final int stopped;
  const _Cabinet({required this.active, required this.asNeeded, required this.completed, required this.stopped});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Medication cabinet',
      child: Column(children: [
        _CabinetRow(label: 'Active', count: active, color: careloopGreen),
        _CabinetRow(label: 'As needed', count: asNeeded, color: careloopMuted),
        _CabinetRow(label: 'Completed', count: completed, color: careloopAccent),
        _CabinetRow(label: 'Stopped', count: stopped, color: careloopDanger),
      ]),
    );
  }
}

class _CabinetRow extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _CabinetRow({required this.label, required this.count, required this.color});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
        Text('$count', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: color)),
      ]),
    );
  }
}

class _ImportRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ImportRow({required this.icon, required this.title, required this.subtitle, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(careloopRadiusMd),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: careloopSurface, borderRadius: BorderRadius.circular(careloopRadiusMd), border: careloopCardBorder, boxShadow: careloopCardShadow),
        child: Row(children: [
          Container(width: 34, height: 34, decoration: BoxDecoration(color: careloopAccentLight, borderRadius: BorderRadius.circular(12)), child: Icon(icon, size: 16, color: careloopAccent)),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: careloopAccent, fontWeight: FontWeight.w700, fontSize: 13)),
            Text(subtitle, style: const TextStyle(color: careloopMuted, fontSize: 10.5)),
          ]),
        ]),
      ),
    );
  }
}
