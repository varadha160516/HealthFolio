import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../auth_provider.dart';
import '../../../theme.dart';
import '../../../utils/range_format.dart';
import '../../../widgets/glass.dart';
import '../../../widgets/ledger.dart';
import '../../../widgets/section_card.dart';

/// The actual original uploaded file(s) plus the parsed values side by side — so a member (or a
/// doctor being shown the app) can always go back and verify a parsed number against the real
/// source document, for any document type (lab report, prescription, radiology, etc.).
class DocumentViewerScreen extends StatefulWidget {
  final String documentId;
  const DocumentViewerScreen({super.key, required this.documentId});
  @override
  State<DocumentViewerScreen> createState() => _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends State<DocumentViewerScreen> {
  Map<String, dynamic>? _detail;
  List<dynamic>? _pages;
  int _pageIndex = 0;
  bool _downloading = false;
  final Map<String, Future<Uint8List>> _fileCache = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().api;
    final detail = await api.getDocument(widget.documentId);
    final pages = await api.getDocumentPages(widget.documentId);
    if (mounted) {
      setState(() {
        _detail = detail;
        _pages = pages;
      });
    }
  }

  Future<Uint8List> _fileFor(String filename) =>
      _fileCache.putIfAbsent(filename, () => context.read<AuthProvider>().api.getDocumentFileBytes(widget.documentId, filename));

  /// Saves the current page to a temp file and opens the OS share sheet — on Android that sheet's
  /// own "Save to Files"/"Save to Drive" targets are the actual download step; sharing this way
  /// needs no storage permission, unlike writing straight into a public Downloads directory.
  Future<void> _download(Map<String, dynamic> page, String documentType) async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final bytes = await _fileFor(page['filename'] as String);
      final ext = (page['filename'] as String).split('.').last;
      final dir = await getTemporaryDirectory();
      final safeName = documentType.replaceAll('_', '-');
      final file = File('${dir.path}/$safeName-${widget.documentId.substring(0, 8)}.$ext');
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not download: $e')));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_detail == null || _pages == null) return const GlassScaffold(body: LoadingCenter());
    final doc = _detail!['document'] as Map<String, dynamic>;
    final parameters = (_detail!['parameters'] as List<dynamic>).cast<Map<String, dynamic>>();
    final lineItems = ((_detail!['prescriptionLineItems'] as List<dynamic>?) ?? const []).cast<Map<String, dynamic>>();
    final pages = _pages!.cast<Map<String, dynamic>>();

    return GlassScaffold(
      appBar: GlassAppBar(
        title: Text((doc['document_type'] as String).replaceAll('_', ' ')),
        actions: [
          if (pages.isNotEmpty)
            IconButton(
              icon: _downloading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.download_rounded),
              tooltip: 'Download',
              onPressed: _downloading ? null : () => _download(pages[_pageIndex], doc['document_type'] as String),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(children: [
              Expanded(
                child: Text(
                  '${doc['source_lab_name'] ?? '—'} · ${doc['test_date'] ?? (doc['upload_date'] as String).substring(0, 10)}',
                  style: const TextStyle(color: careloopMuted),
                ),
              ),
              StatusPill(doc['status'], tone: doc['status'] == 'parsed' ? PillTone.success : doc['status'] == 'manual_entry_required' ? PillTone.danger : PillTone.warning),
            ]),
          ),
          if (pages.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: InfoBanner('No original file on record for this document.'))
          else ...[
            SizedBox(
              height: 380,
              child: Stack(children: [
                PageView.builder(
                  itemCount: pages.length,
                  onPageChanged: (i) => setState(() => _pageIndex = i),
                  itemBuilder: (_, i) => _PageView(page: pages[i], loadBytes: () => _fileFor(pages[i]['filename'])),
                ),
                if (pages.length > 1)
                  Positioned(
                    bottom: 8,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                        child: Text('${_pageIndex + 1} / ${pages.length}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                      ),
                    ),
                  ),
              ]),
            ),
            const Divider(height: 1),
          ],
          Expanded(
            child: lineItems.isNotEmpty
                ? ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      LedgerTable(
                        title: 'Prescribed medicines',
                        rows: [
                          for (final li in lineItems)
                            LedgerRow(
                              label: li['medicine_name'] ?? '',
                              sublabel: [li['strength'], li['dosage'], li['frequency'], li['duration']].where((e) => e != null).join(' · '),
                              trailing: const SizedBox.shrink(),
                            ),
                        ],
                      ),
                    ],
                  )
                : parameters.isEmpty
                    ? const Center(child: Text('No parsed values for this document.', style: TextStyle(color: careloopMuted)))
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          LedgerTable(
                            title: 'Extracted values',
                            rows: [for (final p in parameters) _extractedRow(p)],
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}

class _PageView extends StatelessWidget {
  final Map<String, dynamic> page;
  final Future<Uint8List> Function() loadBytes;
  const _PageView({required this.page, required this.loadBytes});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: loadBytes(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError || snapshot.data == null) {
          return const Center(child: Text("Couldn't load this page.", style: TextStyle(color: careloopMuted)));
        }
        final bytes = snapshot.data!;
        if (page['mime_type'] == 'application/pdf') {
          return pdfx.PdfView(controller: pdfx.PdfController(document: pdfx.PdfDocument.openData(bytes)));
        }
        return InteractiveViewer(minScale: 1, maxScale: 4, child: Center(child: Image.memory(bytes, fit: BoxFit.contain)));
      },
    );
  }
}

LedgerRow _extractedRow(Map<String, dynamic> param) {
  final value = param['canonical_value'] != null ? '${param['canonical_value']}' : '${param['value_raw']}';
  final unit = (param['canonical_unit'] ?? param['unit_raw']) as String?;
  final rangeType = param['range_type'] ?? param['dict_range_type'];
  final resolved = (param['resolved_reference_range'] ?? param['printed_reference_range']) as Map<String, dynamic>?;
  final range = formatReferenceRange(rangeType, resolved);
  return LedgerRow(
    label: param['raw_label_as_printed'] ?? '',
    sublabel: range.isEmpty ? null : 'Range: $range',
    trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
      LedgerValue(value, unit: unit),
      const SizedBox(height: 3),
      StatusPill.forReviewStatus(param['review_status']),
    ]),
  );
}
