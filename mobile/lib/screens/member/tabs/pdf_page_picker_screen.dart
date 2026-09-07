import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
import '../../../theme.dart';
import '../../../widgets/glass.dart';
import '../../../widgets/section_card.dart';

/// Lets a member pick specific pages out of a multi-page PDF instead of uploading the whole
/// thing — shows an actual thumbnail of every page (not just a page number) since nobody has
/// page numbers memorized for a 50-page export. Returns the chosen 1-indexed page numbers, or
/// null if the user cancels.
class PdfPagePickerScreen extends StatefulWidget {
  final Uint8List pdfBytes;
  final String filename;
  const PdfPagePickerScreen({super.key, required this.pdfBytes, required this.filename});

  @override
  State<PdfPagePickerScreen> createState() => _PdfPagePickerScreenState();
}

class _PdfPagePickerScreenState extends State<PdfPagePickerScreen> {
  pdfx.PdfDocument? _document;
  int? _pageCount;
  String? _error;
  final Set<int> _selected = {};

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final doc = await pdfx.PdfDocument.openData(widget.pdfBytes);
      if (!mounted) {
        await doc.close();
        return;
      }
      setState(() {
        _document = doc;
        _pageCount = doc.pagesCount;
      });
    } catch (e) {
      if (mounted) setState(() => _error = "Couldn't open this PDF: $e");
    }
  }

  @override
  void dispose() {
    _document?.close();
    super.dispose();
  }

  // Memoized per page — without this, every setState() (e.g. toggling one page's selection)
  // would hand FutureBuilder a brand-new Future instance for every visible thumbnail, and
  // FutureBuilder treats a changed future identity as "start over", re-rendering already-loaded
  // thumbnails from scratch on every tap.
  final Map<int, Future<pdfx.PdfPageImage?>> _thumbnailCache = {};
  Future<pdfx.PdfPageImage?> _thumbnailFor(int pageNumber) => _thumbnailCache.putIfAbsent(pageNumber, () => _renderThumbnail(pageNumber));

  Future<pdfx.PdfPageImage?> _renderThumbnail(int pageNumber) async {
    final doc = _document;
    if (doc == null) return null;
    final page = await doc.getPage(pageNumber);
    try {
      // Half native resolution is plenty for a picker thumbnail and keeps rendering fast even
      // across many pages — this is only for the user to recognize which page is which.
      return await page.render(
        width: page.width / 2,
        height: page.height / 2,
        format: pdfx.PdfPageImageFormat.jpeg,
        quality: 65,
      );
    } finally {
      await page.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      appBar: GlassAppBar(title: Text('Choose pages — ${widget.filename}')),
      body: _error != null
          ? Padding(padding: const EdgeInsets.all(16), child: InfoBanner(_error!))
          : _pageCount == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Row(children: [
                        Expanded(
                          child: Text('$_pageCount page(s) — tap to select which ones to upload.', style: const TextStyle(color: careloopMuted)),
                        ),
                        TextButton(
                          onPressed: () => setState(() => _selected.addAll(List.generate(_pageCount!, (i) => i + 1))),
                          child: const Text('Select all'),
                        ),
                        TextButton(onPressed: () => setState(() => _selected.clear()), child: const Text('Clear')),
                      ]),
                    ),
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 0.72,
                        ),
                        itemCount: _pageCount,
                        itemBuilder: (_, i) {
                          final pageNumber = i + 1;
                          final isSelected = _selected.contains(pageNumber);
                          return _PageThumbnail(
                            pageNumber: pageNumber,
                            selected: isSelected,
                            loadImage: () => _thumbnailFor(pageNumber),
                            onTap: () => setState(() => isSelected ? _selected.remove(pageNumber) : _selected.add(pageNumber)),
                          );
                        },
                      ),
                    ),
                  ],
                ),
      bottomNavigationBar: _pageCount == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton(onPressed: () => Navigator.of(context).pop(null), child: const Text('Cancel')),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _selected.isEmpty ? null : () => Navigator.of(context).pop(_selected.toList()..sort()),
                      child: Text(_selected.isEmpty ? 'Select at least one page' : 'Use ${_selected.length} page(s)'),
                    ),
                  ),
                ]),
              ),
            ),
    );
  }
}

class _PageThumbnail extends StatelessWidget {
  final int pageNumber;
  final bool selected;
  final Future<pdfx.PdfPageImage?> Function() loadImage;
  final VoidCallback onTap;
  const _PageThumbnail({required this.pageNumber, required this.selected, required this.loadImage, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: selected ? careloopPrimary : careloopBorder, width: selected ? 3 : 1),
          borderRadius: BorderRadius.circular(8),
          color: Colors.white,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: FutureBuilder<pdfx.PdfPageImage?>(
                future: loadImage(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)));
                  }
                  final bytes = snapshot.data?.bytes;
                  if (bytes == null) return const Center(child: Icon(Icons.broken_image_rounded, color: careloopMuted));
                  return Image.memory(bytes, fit: BoxFit.contain);
                },
              ),
            ),
            Positioned(
              left: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                child: Text('$pageNumber', style: const TextStyle(color: Colors.white, fontSize: 11)),
              ),
            ),
            if (selected)
              const Positioned(
                right: 4,
                top: 4,
                child: CircleAvatar(radius: 11, backgroundColor: careloopPrimary, child: Icon(Icons.check_rounded, size: 14, color: Colors.white)),
              ),
          ],
        ),
      ),
    );
  }
}
