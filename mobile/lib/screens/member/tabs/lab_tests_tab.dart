import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../../api_client.dart';
import '../../../auth_provider.dart';
import '../../../theme.dart';
import '../../../utils/motion.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/section_card.dart';
import 'document_viewer_screen.dart';

const _kRescheduleSlots = <(String, String)>[
  ('07:00-09:00', '7:00 – 9:00 AM'),
  ('09:00-11:00', '9:00 – 11:00 AM'),
  ('16:00-18:00', '4:00 – 6:00 PM'),
];

/// Per-member Lab Tests tab (request: "displayed in the family screen of member for whom it's
/// booked, in a new left panel tab"). The auto-file-to-Documents behavior is real, not simulated:
/// attaching a report uploads it through the existing document/extraction pipeline
/// (document_type='lab_report'), then links the resulting document back to this booking — the
/// same document immediately shows up in that member's real Documents tab, Lab Reports category,
/// no separate copy.
class LabTestsTab extends StatefulWidget {
  final String memberId;
  const LabTestsTab({super.key, required this.memberId});
  @override
  State<LabTestsTab> createState() => _LabTestsTabState();
}

class _LabTestsTabState extends State<LabTestsTab> {
  List<dynamic>? _bookings;
  String? _attachingId;

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

  Future<void> _attachReport(String bookingId) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_rounded), title: const Text('Take photo'), onTap: () => Navigator.of(context).pop('camera')),
          ListTile(leading: const Icon(Icons.image_rounded), title: const Text('Choose from Photos'), onTap: () => Navigator.of(context).pop('gallery')),
          ListTile(leading: const Icon(Icons.picture_as_pdf_rounded), title: const Text('Choose PDF'), onTap: () => Navigator.of(context).pop('pdf')),
        ]),
      ),
    );
    if (choice == null || !mounted) return;

    final files = <PickedFileBytes>[];
    if (choice == 'camera') {
      final photo = await ImagePicker().pickImage(source: ImageSource.camera);
      if (photo != null) files.add(PickedFileBytes(photo.name, await photo.readAsBytes()));
    } else if (choice == 'gallery') {
      final picked = await ImagePicker().pickMultiImage();
      for (final p in picked) {
        files.add(PickedFileBytes(p.name, await p.readAsBytes()));
      }
    } else {
      final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
      for (final f in picked) {
        files.add(PickedFileBytes(f.name, await f.readAsBytes()));
      }
    }
    if (files.isEmpty || !mounted) return;

    setState(() => _attachingId = bookingId);
    try {
      final api = context.read<AuthProvider>().api;
      final result = await api.uploadDocument(memberId: widget.memberId, documentType: 'lab_report', files: files);
      final documentId = result['documentId'] as String?;
      if (documentId != null) {
        await api.updateLabTestBooking(bookingId, {'status': 'report_ready', 'document_id': documentId});
      }
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _attachingId = null);
    }
  }

  Future<void> _reschedule(Map<String, dynamic> booking) async {
    DateTime date = DateTime.tryParse(booking['booked_date'] as String? ?? '') ?? DateTime.now().add(const Duration(days: 1));
    String slot = (booking['time_slot'] as String?) ?? _kRescheduleSlots.first.$1;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Reschedule collection'),
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
                items: [for (final s in _kRescheduleSlots) DropdownMenuItem(value: s.$1, child: Text(s.$2))],
                onChanged: (v) => setDialogState(() => slot = v ?? slot),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Back')),
            ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;
    final api = context.read<AuthProvider>().api;
    await api.updateLabTestBooking(booking['id'] as String, {'booked_date': date.toIso8601String().substring(0, 10), 'time_slot': slot});
    await _load();
  }

  Future<void> _cancel(Map<String, dynamic> booking) async {
    final tests = (booking['test_names'] as List).cast<String>().join(', ');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel this lab test?'),
        content: Text('The booked collection for $tests will be cancelled.'),
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
                busy: _attachingId == b['id'],
                onAttach: () => _attachReport(b['id'] as String),
                onReschedule: () => _reschedule(b),
                onCancel: () => _cancel(b),
              ),
        ],
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  final bool busy;
  final VoidCallback onAttach;
  final VoidCallback onReschedule;
  final VoidCallback onCancel;
  const _BookingCard({required this.booking, required this.busy, required this.onAttach, required this.onReschedule, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final tests = (booking['test_names'] as List).cast<String>();
    final status = booking['status'] as String;
    final documentId = booking['document_id'] as String?;
    final (bg, fg, label) = switch (status) {
      'report_ready' => (careloopGreenBg, careloopGreen, 'Reports Delivered'),
      'processing' => (careloopNewBg, careloopInfo, 'Collection Done'),
      'cancelled' => (careloopAbnormalBg, careloopDanger, 'Cancelled'),
      _ => (careloopWarningBg, careloopWarning, 'Collection Scheduled'),
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
                  Text(
                    '${booking['lab_name']} · Booked ${booking['booked_date']}${booking['time_slot'] != null ? ' · ${booking['time_slot']}' : ''}',
                    style: const TextStyle(color: careloopMuted, fontSize: 10.5),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
              child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 10)),
            ),
          ]),
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
          ] else if (status == 'cancelled') ...[
            // Cancelled — nothing further to do on this booking.
          ] else ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                onPressed: busy ? null : onAttach,
                icon: busy ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.upload_file_rounded, size: 15),
                label: Text(busy ? 'Uploading…' : 'Attach report'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              ),
              if (status == 'collection_scheduled') ...[
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
              ],
            ]),
          ],
        ],
      ),
    );
  }
}
