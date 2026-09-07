import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:provider/provider.dart';
import '../../../api_client.dart';
import '../../../auth_provider.dart';
import '../../../theme.dart';
import 'document_list_screen.dart';
import 'pdf_page_picker_screen.dart';
import '../../../utils/motion.dart';

/// Redesigned entry point for adding a document — type grid + upload actions in one sheet,
/// wired to the same api.uploadDocument() path the original Upload tab used. Returns `true` via
/// Navigator.pop on a successful upload so the caller knows to refresh the Documents tab.
class AddDocumentSheet extends StatefulWidget {
  final String memberId;
  const AddDocumentSheet({super.key, required this.memberId});

  @override
  State<AddDocumentSheet> createState() => _AddDocumentSheetState();
}

class _AddDocumentSheetState extends State<AddDocumentSheet> {
  String _documentType = kDocTypeOrder.first;
  bool _busy = false;

  Future<void> _uploadFromDevice() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_rounded), title: const Text('Photos'), onTap: () => Navigator.of(context).pop('photos')),
          ListTile(leading: const Icon(Icons.picture_as_pdf_rounded), title: const Text('PDF'), onTap: () => Navigator.of(context).pop('pdf')),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    final files = <PickedFileBytes>[];
    if (choice == 'photos') {
      final picked = await ImagePicker().pickMultiImage();
      for (final p in picked) {
        files.add(PickedFileBytes(p.name, await p.readAsBytes()));
      }
    } else {
      final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
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
    }
    if (files.isEmpty || !mounted) return;
    await _submit(files);
  }

  Future<void> _scanDocument() async {
    final photo = await ImagePicker().pickImage(source: ImageSource.camera);
    if (photo == null || !mounted) return;
    await _submit([PickedFileBytes(photo.name, await photo.readAsBytes())]);
  }

  Future<void> _submit(List<PickedFileBytes> files) async {
    setState(() => _busy = true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(children: [
          CircularProgressIndicator(),
          SizedBox(width: 20),
          Expanded(child: Text('Reading the document… a large report can take a minute or more.')),
        ]),
      ),
    );
    try {
      final api = context.read<AuthProvider>().api;
      await api.uploadDocument(memberId: widget.memberId, documentType: _documentType, files: files);
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // close spinner
        Navigator.of(context).pop(true); // close sheet, signal success
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // close spinner
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
            Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Add Document', style: careloopSectionHeading().copyWith(fontSize: 18)),
                    const Text('Select type of document', style: TextStyle(color: careloopMuted, fontSize: 11.5)),
                  ],
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => Navigator.of(context).pop(false),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(color: careloopSurface, shape: BoxShape.circle, border: careloopCardBorder),
                  child: const Icon(Icons.close_rounded, size: 14, color: careloopTextPrimary),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.7,
              children: [
                for (final t in kDocTypeOrder)
                  _TypeTile(
                    label: kDocTypeLabels[t]!,
                    icon: kDocTypeIcons[t]!,
                    bg: kDocTypeColors[t]!.$1,
                    fg: kDocTypeColors[t]!.$2,
                    selected: _documentType == t,
                    onTap: () => setState(() => _documentType = t),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            const Divider(height: 1, color: careloopBorder),
            _ActionRow(
              icon: Icons.upload_rounded,
              title: 'Upload from device',
              subtitle: 'PDF, JPG, PNG',
              onTap: _busy ? null : _uploadFromDevice,
            ),
            _ActionRow(
              icon: Icons.document_scanner_rounded,
              title: 'Scan Document',
              subtitle: 'Take a photo and upload',
              onTap: _busy ? null : _scanDocument,
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color bg;
  final Color fg;
  final bool selected;
  final VoidCallback onTap;
  const _TypeTile({required this.label, required this.icon, required this.bg, required this.fg, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: selected ? Border.all(color: fg, width: 2) : null,
        ),
        child: Row(children: [
          Container(width: 32, height: 32, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: Icon(icon, size: 15, color: fg)),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: selected ? fg : careloopTextPrimary), maxLines: 2, overflow: TextOverflow.ellipsis)),
        ]),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  const _ActionRow({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Container(width: 34, height: 34, decoration: BoxDecoration(color: careloopAccentLight, borderRadius: BorderRadius.circular(12)), child: Icon(icon, size: 16, color: careloopAccent)),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: careloopAccent, fontWeight: FontWeight.w600, fontSize: 13.5)),
              Text(subtitle, style: const TextStyle(color: careloopMuted, fontSize: 10.5)),
            ],
          ),
        ]),
      ),
    );
  }
}
