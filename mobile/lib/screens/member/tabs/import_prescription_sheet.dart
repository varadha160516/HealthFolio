import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:provider/provider.dart';
import '../../../api_client.dart';
import '../../../auth_provider.dart';
import '../../../theme.dart';
import '../../../utils/motion.dart';
import 'pdf_page_picker_screen.dart';

/// Entry points for "Import prescription" (request points 2 &amp; 6): camera, gallery, or a PDF —
/// always uploaded as document_type='prescription', so it runs through the existing prescription
/// OCR pipeline. Pops with the upload's raw response map on success (documentId/prescriptionId),
/// so the caller can push straight into the review screen; null/false on cancel.
class ImportPrescriptionSheet extends StatefulWidget {
  final String memberId;
  const ImportPrescriptionSheet({super.key, required this.memberId});

  @override
  State<ImportPrescriptionSheet> createState() => _ImportPrescriptionSheetState();
}

class _ImportPrescriptionSheetState extends State<ImportPrescriptionSheet> {
  bool _busy = false;

  Future<void> _fromCamera() async {
    final photo = await ImagePicker().pickImage(source: ImageSource.camera);
    if (photo == null || !mounted) return;
    await _upload([PickedFileBytes(photo.name, await photo.readAsBytes())]);
  }

  Future<void> _fromGallery() async {
    final picked = await ImagePicker().pickMultiImage();
    if (picked.isEmpty || !mounted) return;
    final files = <PickedFileBytes>[];
    for (final p in picked) {
      files.add(PickedFileBytes(p.name, await p.readAsBytes()));
    }
    await _upload(files);
  }

  Future<void> _fromFiles() async {
    final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (picked.isEmpty || !mounted) return;
    final files = <PickedFileBytes>[];
    for (final f in picked) {
      final bytes = await f.readAsBytes();
      List<int>? selectedPages;
      try {
        final doc = await pdfx.PdfDocument.openData(bytes);
        final count = doc.pagesCount;
        await doc.close();
        if (count > 1 && mounted) {
          final result = await Navigator.of(context).push<List<int>>(pushRoute(PdfPagePickerScreen(pdfBytes: bytes, filename: f.name)));
          if (result == null) continue;
          selectedPages = result;
        }
      } catch (_) {
        // Corrupt/unreadable page count — fall back to uploading the whole file.
      }
      files.add(PickedFileBytes(f.name, bytes, selectedPages: selectedPages));
    }
    if (files.isEmpty || !mounted) return;
    await _upload(files);
  }

  Future<void> _upload(List<PickedFileBytes> files) async {
    setState(() => _busy = true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(children: [
          CircularProgressIndicator(),
          SizedBox(width: 20),
          Expanded(child: Text('Reading the prescription…')),
        ]),
      ),
    );
    try {
      final api = context.read<AuthProvider>().api;
      final result = await api.uploadDocument(memberId: widget.memberId, documentType: 'prescription', files: files);
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // close spinner
        Navigator.of(context).pop(result);
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Import failed'),
            content: Text('$e'),
            actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: careloopBorder, borderRadius: BorderRadius.circular(999)))),
            const SizedBox(height: 16),
            Text('Import prescription', style: careloopSectionHeading().copyWith(fontSize: 18)),
            const Text('Bring in medicines from anywhere', style: TextStyle(color: careloopMuted, fontSize: 11.5)),
            const SizedBox(height: 14),
            _Entry(icon: Icons.photo_camera_rounded, title: 'Take photo of prescription', subtitle: 'Camera', onTap: _busy ? null : _fromCamera),
            _Entry(icon: Icons.image_rounded, title: 'Select image from Photos', subtitle: 'Gallery', onTap: _busy ? null : _fromGallery),
            _Entry(icon: Icons.picture_as_pdf_rounded, title: 'Select PDF or document', subtitle: 'Files', onTap: _busy ? null : _fromFiles),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: careloopSurfaceRaised, borderRadius: BorderRadius.circular(14)),
              child: const Row(children: [
                Icon(Icons.info_outline_rounded, size: 16, color: careloopAccent),
                SizedBox(width: 8),
                Expanded(child: Text('Nothing is added automatically — you review and confirm every medicine first.', style: TextStyle(fontSize: 10.5, color: careloopTextPrimary))),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _Entry extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  const _Entry({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Container(width: 36, height: 36, decoration: BoxDecoration(color: careloopAbnormalBg, borderRadius: BorderRadius.circular(12)), child: Icon(icon, size: 17, color: careloopDanger)),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
            Text(subtitle, style: const TextStyle(color: careloopMuted, fontSize: 10.5)),
          ]),
        ]),
      ),
    );
  }
}
