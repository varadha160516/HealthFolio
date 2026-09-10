import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../auth_provider.dart';
import '../../../theme.dart';
import '../../../utils/motion.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/section_card.dart';
import 'document_viewer_screen.dart';

const _kSlots = <(String, String)>[
  ('07:00-09:00', '7:00 – 9:00 AM'),
  ('09:00-11:00', '9:00 – 11:00 AM'),
  ('16:00-18:00', '4:00 – 6:00 PM'),
];

/// Per-member Lab Tests tab (request: "displayed in the family screen of member for whom it's
/// booked, in a new left panel tab"). A booking now moves through a real status machine:
/// pending_schedule (doctor-ordered, no date/slot chosen yet) -> collection_scheduled -> processing
/// -> report_ready, with cancelled reachable from either of the first two. Only the transitions
/// each status actually allows are shown — no "attach report" self-upload step, no cancel before a
/// test is even scheduled.
class LabTestsTab extends StatefulWidget {
  final String memberId;
  const LabTestsTab({super.key, required this.memberId});
  @override
  State<LabTestsTab> createState() => _LabTestsTabState();
}

class _LabTestsTabState extends State<LabTestsTab> {
  List<dynamic>? _bookings;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().api;
    final bookings = await api.getMemberLabTestBookings(widget.memberId);
    if (mounted) setState(() => _bookings = bookings);
  }

  Future<void> _pickDateAndSlot(Map<String, dynamic> booking, {required String title, required String confirmLabel}) async {
    DateTime date = DateTime.tryParse(booking['booked_date'] as String? ?? '') ?? DateTime.now().add(const Duration(days: 1));
    String slot = (booking['time_slot'] as String?) ?? _kSlots.first.$1;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton(
                onPressed: () async {
                  final picked = await showDatePicker(context: dialogContext, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 60)), initialDate: date);
                  if (picked == null) return;
                  setDialogState(() => date = picked);
                },
                child: Text(date.toIso8601String().substring(0, 10)),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: slot,
                decoration: const InputDecoration(labelText: 'Collection time'),
                items: [for (final s in _kSlots) DropdownMenuItem(value: s.$1, child: Text(s.$2))],
                onChanged: (v) => setDialogState(() => slot = v ?? slot),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Back')),
            ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(confirmLabel)),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;
    final api = context.read<AuthProvider>().api;
    final payload = <String, dynamic>{'booked_date': date.toIso8601String().substring(0, 10), 'time_slot': slot};
    if (booking['status'] == 'pending_schedule') payload['status'] = 'collection_scheduled';
    await api.updateLabTestBooking(booking['id'] as String, payload);
    await _load();
  }

  Future<void> _cancel(Map<String, dynamic> booking) async {
    final tests = (booking['test_names'] as List).cast<String>().join(', ');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel this lab test?'),
        content: Text('The booking for $tests will be cancelled.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: careloopDanger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel test'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final api = context.read<AuthProvider>().api;
    await api.updateLabTestBooking(booking['id'] as String, {'status': 'cancelled'});
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_bookings == null) return const LoadingCenter();
    final bookings = _bookings!.cast<Map<String, dynamic>>();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, careloopFabClearance),
        children: [
          Text('Lab Tests', style: careloopPageTitle().copyWith(fontSize: 21)),
          const SizedBox(height: 2),
          const Text('Booked tests and reports for this member', style: TextStyle(color: careloopMuted, fontSize: 11.5)),
          const SizedBox(height: 14),
          if (bookings.isEmpty)
            const EmptyState(icon: Icons.science_outlined, message: 'No lab tests booked yet.')
          else
            for (final b in bookings)
              _BookingCard(
                booking: b,
                onSchedule: () => _pickDateAndSlot(b, title: 'Schedule collection', confirmLabel: 'Schedule'),
                onReschedule: () => _pickDateAndSlot(b, title: 'Reschedule collection', confirmLabel: 'Save'),
                onCancel: () => _cancel(b),
              ),
        ],
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  final VoidCallback onSchedule;
  final VoidCallback onReschedule;
  final VoidCallback onCancel;
  const _BookingCard({required this.booking, required this.onSchedule, required this.onReschedule, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final tests = (booking['test_names'] as List).cast<String>();
    final status = booking['status'] as String;
    final documentId = booking['document_id'] as String?;
    final (bg, fg, label) = switch (status) {
      'report_ready' => (careloopGreenBg, careloopGreen, 'Reports Delivered'),
      'processing' => (careloopNewBg, careloopInfo, 'Sample Collection Done'),
      'cancelled' => (careloopAbnormalBg, careloopDanger, 'Cancelled'),
      'pending_schedule' => (careloopSurfaceRaised, careloopMuted, 'Not Scheduled'),
      _ => (careloopWarningBg, careloopWarning, 'Scheduled'),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(color: careloopSurface, borderRadius: BorderRadius.circular(careloopRadiusMd), border: careloopCardBorder, boxShadow: careloopCardShadow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Each test on its own line — not comma-joined — so a multi-test booking reads
                  // as a real list rather than one run-on line.
                  for (final t in tests)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(width: 4, height: 4, margin: const EdgeInsets.only(right: 6), decoration: const BoxDecoration(color: careloopTextPrimary, shape: BoxShape.circle)),
                        Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                      ]),
                    ),
                  Text(booking['lab_name'] as String? ?? '', style: const TextStyle(color: careloopMuted, fontSize: 10.5)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
              child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 10)),
            ),
          ]),
          if (booking['booked_date'] != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(color: careloopAccentLight, borderRadius: BorderRadius.circular(10)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.calendar_today_rounded, size: 13, color: careloopAccentDark),
                const SizedBox(width: 6),
                Text(
                  'Booked for ${booking['booked_date']}${booking['time_slot'] != null ? ' · ${_formatSlot(booking['time_slot'] as String)}' : ''}',
                  style: const TextStyle(color: careloopAccentDark, fontWeight: FontWeight.w600, fontSize: 11),
                ),
              ]),
            ),
          ],
          if (status == 'report_ready' && documentId != null) ...[
            const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1)),
            Row(children: [
              const Icon(Icons.check_circle_rounded, size: 14, color: careloopGreen),
              const SizedBox(width: 5),
              const Expanded(child: Text('Added to Documents · Lab Reports', style: TextStyle(color: careloopGreen, fontSize: 10.5, fontWeight: FontWeight.w600))),
              InkWell(
                onTap: () => Navigator.of(context).push(pushRoute(DocumentViewerScreen(documentId: documentId))),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('View report', style: TextStyle(color: careloopAccent, fontWeight: FontWeight.w700, fontSize: 11.5)),
                  Icon(Icons.chevron_right_rounded, size: 16, color: careloopAccent),
                ]),
              ),
            ]),
          ] else if (status == 'pending_schedule') ...[
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: onSchedule, child: const Text('Schedule'))),
          ] else if (status == 'collection_scheduled') ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                onPressed: onReschedule,
                icon: const Icon(Icons.event_repeat_rounded, size: 15),
                label: const Text('Reschedule'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              ),
              OutlinedButton.icon(
                onPressed: onCancel,
                icon: const Icon(Icons.close_rounded, size: 15, color: careloopDanger),
                label: const Text('Cancel', style: TextStyle(color: careloopDanger)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  side: const BorderSide(color: careloopDanger),
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  static String _formatSlot(String slot) {
    final match = _kSlots.where((s) => s.$1 == slot);
    return match.isEmpty ? slot : match.first.$2;
  }
}
