import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:provider/provider.dart';
import '../../../api_client.dart';
import '../../../auth_provider.dart';
import '../../../theme.dart';
import '../../../utils/motion.dart';
import '../../../widgets/section_card.dart';
import 'pdf_page_picker_screen.dart';

const _docTypes = [
  ('lab_report', 'Lab report'),
  ('prescription', 'Prescription'),
  ('radiology_scan', 'Radiology scan'),
  ('discharge_summary', 'Discharge summary'),
  ('vaccination_record', 'Vaccination record'),
  ('other', 'Other'),
];

class UploadTab extends StatefulWidget {
  final String memberId;
  final VoidCallback onUploaded;
  const UploadTab({super.key, required this.memberId, required this.onUploaded});
  @override
  State<UploadTab> createState() => _UploadTabState();
}

class _UploadTabState extends State<UploadTab> {
  String _documentType = 'lab_report';
  final List<PickedFileBytes> _files = [];
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _result;
  String? _extractionMode; // null while loading; 'live' or 'mock' once known

  @override
  void initState() {
    super.initState();
    _loadExtractionMode();
  }

  Future<void> _loadExtractionMode() async {
    try {
      final mode = await context.read<AuthProvider>().api.getExtractionMode();
      if (mounted) setState(() => _extractionMode = mode);
    } catch (_) {
      // Health check failing isn't worth blocking the upload UI over — leave the banner in its
      // "unknown" state (rendered as the cautious mock-mode wording below).
    }
  }

  Future<void> _pickPhotos() async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage();
    for (final p in picked) {
      _files.add(PickedFileBytes(p.name, await p.readAsBytes()));
    }
    setState(() {});
  }

  Future<void> _pickPdf() async {
    final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    for (final f in picked) {
      final bytes = await f.readAsBytes();
      List<int>? selectedPages;
      try {
        final doc = await pdfx.PdfDocument.openData(bytes);
        final count = doc.pagesCount;
        await doc.close();
        if (count > 1 && mounted) {
          // Multi-page PDF — let the member pick which pages actually matter instead of
          // uploading (and paying to have a model read) the whole thing.
          final result = await Navigator.of(context).push<List<int>>(pushRoute(PdfPagePickerScreen(pdfBytes: bytes, filename: f.name)));
          if (result == null) continue; // cancelled the picker — don't add this file at all
          selectedPages = result;
        }
      } catch (_) {
        // Couldn't read the page count (unusual/corrupt PDF) — fall back to uploading the whole
        // file as before rather than blocking the upload entirely.
      }
      _files.add(PickedFileBytes(f.name, bytes, selectedPages: selectedPages));
    }
    setState(() {});
  }

  Future<void> _submit({String? mockFixture}) async {
    if (mockFixture == null && _files.isEmpty) {
      setState(() => _error = 'Choose at least one page (photo or PDF).');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });

    // A blocking modal spinner — impossible to miss, unlike a bar buried in a scrollable list.
    // Real reports with 50-100+ result rows can take well over a minute (the model is reading and
    // transcribing every single row, one at a time) — say so up front rather than let it look stuck.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(children: [
          CircularProgressIndicator(),
          SizedBox(width: 20),
          Expanded(
            child: Text('Reading the document… a large report (50+ results) can take a minute or more.'),
          ),
        ]),
      ),
    );

    try {
      final api = context.read<AuthProvider>().api;
      final res = await api.uploadDocument(memberId: widget.memberId, documentType: _documentType, mockFixture: mockFixture, files: _files);
      setState(() {
        _result = res;
        _files.clear();
      });
      widget.onUploaded();
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // close the spinner dialog
        final failed = res['status'] == 'manual_entry_required';
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(failed ? "Couldn't read it automatically" : 'Uploaded'),
            content: Text(failed
                ? "The document was saved, but reading it automatically didn't work this time — it'll need to be entered manually. Nothing was lost."
                : _summaryText(res)),
            actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
          ),
        );
      }
    } catch (e) {
      setState(() => _error = e.toString());
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // close the spinner dialog
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Upload failed'),
            content: Text('$e'),
            actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _summaryText(Map<String, dynamic> res) {
    final p = res['pipeline'];
    if (p == null) return 'Document stored.';
    final newCandidates = p['newCandidateCount'] as int? ?? 0;
    return 'Extracted ${p['extractedCount']} values — check the Overview tab to see them.'
        '${newCandidates > 0 ? " $newCandidates label(s) weren't recognized and were sent for review separately." : ''}';
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, careloopFabClearance),
      children: [
        // Only worth telling the user about when it changes what they should expect: in mock
        // mode, a real upload won't reflect the actual file, so point them at the demo buttons
        // instead. Nothing useful to say once real reading is working, so stay quiet then.
        if (_extractionMode == 'mock')
          const InfoBanner(
            "This test version isn't reading real documents yet — try the sample buttons below instead to see how it works.",
            info: true,
          ),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Upload a document', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _documentType,
                decoration: const InputDecoration(labelText: 'Document type'),
                items: [for (final t in _docTypes) DropdownMenuItem(value: t.$1, child: Text(t.$2))],
                onChanged: (v) => setState(() => _documentType = v ?? 'lab_report'),
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(onPressed: _pickPhotos, icon: const Icon(Icons.photo_camera_rounded), label: const Text('Add photos')),
                OutlinedButton.icon(onPressed: _pickPdf, icon: const Icon(Icons.picture_as_pdf_rounded), label: const Text('Add PDF')),
              ]),
              if (_files.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _files
                        .map((f) => f.selectedPages != null ? '${f.filename} (pages ${f.selectedPages!.join(', ')})' : f.filename)
                        .join(', '),
                  ),
                ),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _busy ? null : () => _submit(), child: Text(_busy ? 'Uploading…' : 'Upload & extract')),
              if (_documentType == 'lab_report') ...[
                const SizedBox(height: 14),
                const Text('Or try the golden test set (Section 4.8):', style: TextStyle(fontSize: 11)),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton(onPressed: _busy ? null : () => _submit(mockFixture: 'golden_report_a'), child: const Text('Load Tata 1mg-style CBC report')),
                  OutlinedButton(onPressed: _busy ? null : () => _submit(mockFixture: 'golden_report_b'), child: const Text('Load PharmEasy/Thyrocare trends report')),
                ]),
              ],
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: InfoBanner(_error!)),
              if (_result != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _result!['status'] == 'manual_entry_required'
                      ? const InfoBanner(
                          "The document was saved, but reading it automatically didn't work this time. It'll need to be "
                          'entered manually — nothing was lost.',
                        )
                      : InfoBanner(_summaryText(_result!), info: true),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
