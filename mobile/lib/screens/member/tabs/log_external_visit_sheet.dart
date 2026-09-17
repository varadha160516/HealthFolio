import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../../api_client.dart';
import '../../../auth_provider.dart';
import '../../../theme.dart';

const _kDocumentTypes = {
  'prescription': 'Prescription',
  'discharge_summary': 'Discharge summary',
  'lab_report': 'Lab report',
  'radiology_scan': 'Radiology scan',
  'other': 'Other document',
};

/// A member's own record of a visit to a doctor not on CareLoop — the realistic alternative to a
/// real external-EHR/ABDM integration. Purely self-declared; its value is that medications logged
/// from this visit feed straight into the safety net's existing cross-provider checks, with no
/// change to that logic. An optional attached document goes through the same upload+OCR pipeline
/// as everything else in the app — a prescription attachment is what lets the caller skip straight
/// to reviewing real extracted line items instead of manual entry.
class LogExternalVisitSheet extends StatefulWidget {
  final String memberId;
  const LogExternalVisitSheet({super.key, required this.memberId});
  @override
  State<LogExternalVisitSheet> createState() => _LogExternalVisitSheetState();
}

class _LogExternalVisitSheetState extends State<LogExternalVisitSheet> {
  final _doctorName = TextEditingController();
  final _hospitalName = TextEditingController();
  final _diagnosis = TextEditingController();
  final _notes = TextEditingController();
  final _visitDate = TextEditingController(text: DateTime.now().toIso8601String().substring(0, 10));
  bool _busy = false;
  String? _error;

  PickedFileBytes? _attachment;
  String _documentType = 'prescription';

  @override
  void dispose() {
    _doctorName.dispose();
    _hospitalName.dispose();
    _diagnosis.dispose();
    _notes.dispose();
    _visitDate.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = DateTime.tryParse(_visitDate.text.trim()) ?? now;
    final picked = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(now.year - 5), lastDate: now);
    if (picked != null) setState(() => _visitDate.text = picked.toIso8601String().substring(0, 10));
  }

  Future<void> _pickAttachment() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_rounded), title: const Text('Take photo'), onTap: () => Navigator.of(context).pop('camera')),
          ListTile(leading: const Icon(Icons.image_rounded), title: const Text('Choose from gallery'), onTap: () => Navigator.of(context).pop('gallery')),
          ListTile(leading: const Icon(Icons.picture_as_pdf_rounded), title: const Text('Choose PDF'), onTap: () => Navigator.of(context).pop('pdf')),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    try {
      if (choice == 'camera' || choice == 'gallery') {
        final picked = await ImagePicker().pickImage(source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery);
        if (picked == null) return;
        final bytes = await picked.readAsBytes();
        if (mounted) setState(() => _attachment = PickedFileBytes(picked.name, bytes));
      } else {
        final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
        if (picked.isEmpty) return;
        final file = picked.first;
        final bytes = await file.readAsBytes();
        if (mounted) setState(() => _attachment = PickedFileBytes(file.name, bytes));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not attach file: $e')));
    }
  }

  Future<void> _save() async {
    if (_doctorName.text.trim().isEmpty) {
      setState(() => _error = 'Doctor name is required');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = context.read<AuthProvider>().api;

      String? documentId;
      String? prescriptionId;
      if (_attachment != null) {
        final uploadResult = await api.uploadDocument(memberId: widget.memberId, documentType: _documentType, files: [_attachment!]);
        documentId = uploadResult['documentId'] as String?;
        prescriptionId = uploadResult['prescriptionId'] as String?;
      }

      final result = await api.addExternalVisit(widget.memberId, {
        'doctor_name': _doctorName.text.trim(),
        'hospital_name': _hospitalName.text.trim().isEmpty ? null : _hospitalName.text.trim(),
        'visit_date': _visitDate.text.trim(),
        'diagnosis': _diagnosis.text.trim().isEmpty ? null : _diagnosis.text.trim(),
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        if (documentId != null) 'document_id': documentId,
      });
      if (mounted) {
        Navigator.of(context).pop({
          'saved': true,
          'doctor_name': _doctorName.text.trim(),
          'hospital_name': _hospitalName.text.trim(),
          'diagnosis': _diagnosis.text.trim(),
          'id': result['id'],
          'documentId': documentId,
          'documentType': _attachment != null ? _documentType : null,
          'prescriptionId': prescriptionId,
        });
      }
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(left: 18, right: 18, top: 12, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: careloopBorder, borderRadius: BorderRadius.circular(999)))),
              const SizedBox(height: 16),
              Text('Log an outside visit', style: careloopSectionHeading().copyWith(fontSize: 18)),
              const SizedBox(height: 4),
              const Text(
                'For a doctor or hospital not on CareLoop. This helps your own Safety Check catch things like duplicate medications across providers.',
                style: TextStyle(color: careloopMuted, fontSize: 11.5, height: 1.4),
              ),
              const SizedBox(height: 16),
              if (_error != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: careloopAbnormalBg, borderRadius: BorderRadius.circular(careloopRadiusMd)),
                  child: Text(_error!, style: const TextStyle(color: careloopDanger, fontSize: 12.5, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 12),
              ],
              TextField(controller: _doctorName, decoration: const InputDecoration(labelText: 'Doctor name')),
              const SizedBox(height: 10),
              TextField(controller: _hospitalName, decoration: const InputDecoration(labelText: 'Hospital / clinic (optional)')),
              const SizedBox(height: 10),
              TextField(
                controller: _visitDate,
                readOnly: true,
                onTap: _pickDate,
                decoration: const InputDecoration(labelText: 'Visit date', suffixIcon: Icon(Icons.calendar_month_rounded, size: 18)),
              ),
              const SizedBox(height: 10),
              TextField(controller: _diagnosis, decoration: const InputDecoration(labelText: 'Diagnosis / reason (optional)')),
              const SizedBox(height: 10),
              TextField(controller: _notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes (optional)')),
              const SizedBox(height: 16),
              InkWell(
                borderRadius: BorderRadius.circular(careloopRadiusMd),
                onTap: _pickAttachment,
                child: Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(color: careloopSurface, borderRadius: BorderRadius.circular(careloopRadiusMd), border: careloopCardBorder),
                  child: Row(children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(color: _attachment != null ? careloopGreenBg : careloopAccentLight, borderRadius: BorderRadius.circular(11)),
                      child: Icon(_attachment != null ? Icons.check_rounded : Icons.attach_file_rounded, size: 16, color: _attachment != null ? careloopGreen : careloopAccent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Attach a document (optional)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                        Text(_attachment?.filename ?? 'e.g. a photo of the prescription', style: TextStyle(color: _attachment != null ? careloopGreen : careloopMuted, fontSize: 10.5)),
                      ]),
                    ),
                    if (_attachment != null) IconButton(icon: const Icon(Icons.close_rounded, size: 17), onPressed: () => setState(() => _attachment = null)),
                  ]),
                ),
              ),
              if (_attachment != null) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _documentType,
                  decoration: const InputDecoration(labelText: 'What kind of document is this?'),
                  items: [for (final e in _kDocumentTypes.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                  onChanged: (v) => setState(() => _documentType = v ?? _documentType),
                ),
                if (_documentType == 'prescription') ...[
                  const SizedBox(height: 6),
                  const Text('We\'ll read the medicines off it so you can add them in one step.', style: TextStyle(color: careloopMuted, fontSize: 10.5, fontStyle: FontStyle.italic)),
                ],
              ],
              const SizedBox(height: 18),
              ElevatedButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving…' : 'Save visit')),
            ],
          ),
        ),
      ),
    );
  }
}
