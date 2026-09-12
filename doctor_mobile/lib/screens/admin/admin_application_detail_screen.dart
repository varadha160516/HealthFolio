import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:provider/provider.dart';
import '../../auth_provider.dart';
import '../../theme.dart';

const _kDocTypeLabels = {
  'registration_certificate': 'Medical registration certificate',
  'government_id': 'Government-issued ID',
  'qualification_certificate': 'Qualification certificate',
  'clinic_proof': 'Clinic proof',
  'other': 'Other document',
};

class AdminApplicationDetailScreen extends StatefulWidget {
  final String applicationId;
  const AdminApplicationDetailScreen({super.key, required this.applicationId});
  @override
  State<AdminApplicationDetailScreen> createState() => _AdminApplicationDetailScreenState();
}

class _AdminApplicationDetailScreenState extends State<AdminApplicationDetailScreen> {
  Map<String, dynamic>? _detail;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().api;
    final detail = await api.getProviderApplicationDetail(widget.applicationId);
    if (mounted) setState(() => _detail = detail);
  }

  Future<void> _approve() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Approve this application?'),
        content: const Text('This creates a live login for the applicant immediately.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Approve')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final api = context.read<AuthProvider>().api;
      await api.approveProviderApplication(widget.applicationId);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reject this application'),
        content: TextField(controller: reasonController, maxLines: 3, decoration: const InputDecoration(labelText: 'Reason (shown to the applicant)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: docDanger),
            onPressed: () => Navigator.pop(dialogContext, reasonController.text.trim()),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (reason == null || reason.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      final api = context.read<AuthProvider>().api;
      await api.rejectProviderApplication(widget.applicationId, reason);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_detail == null) return const DocGradientScaffold(body: LoadingCenter());
    final app = _detail!['application'] as Map<String, dynamic>;
    final clinic = _detail!['clinic'] as Map<String, dynamic>?;
    final documents = (_detail!['documents'] as List).cast<Map<String, dynamic>>();
    final status = app['status'] as String;
    final submitted = DateTime.tryParse(app['created_at'] as String? ?? '')?.toLocal();

    return DocGradientScaffold(
      appBar: AppBar(title: const Text('Application')),
      body: Stack(children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          children: [
            Row(children: [
              Expanded(child: Text(app['full_name'] ?? '', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700))),
              _statusPill(status),
            ]),
            if (submitted != null) Text('Applied ${DateFormat('MMM d, yyyy · h:mm a').format(submitted)}', style: const TextStyle(color: docMuted, fontSize: 11.5)),
            const SizedBox(height: 16),
            _section('Contact', [
              _row('Email', app['email']),
              _row('Phone', app['phone']),
            ]),
            _section('Role', [
              _row('Applying as', app['role_requested'] == 'doctor' ? 'Doctor' : 'Clinic front desk'),
              if (app['role_requested'] == 'doctor') ...[
                _row('Specialty', app['specialty']),
                _row('Registration number', app['registration_number']),
                _row('Qualifications', app['qualifications']),
                _row('Years of experience', app['years_of_experience']?.toString()),
                _row('Consultation fee', app['default_fee'] != null ? '₹${app['default_fee']}' : null),
                _row('GST number', app['gst_number']),
              ],
            ]),
            _section('Clinic', [
              if (app['clinic_mode'] == 'existing') ...[
                _row('Clinic', clinic?['name']),
                _row('Address', [clinic?['address'], clinic?['city']].where((v) => v != null).join(', ')),
              ] else ...[
                _row('New clinic', app['new_clinic_name']),
                _row('Address', [app['new_clinic_address'], app['new_clinic_city']].where((v) => v != null && (v as String).isNotEmpty).join(', ')),
              ],
            ]),
            if (status == 'rejected' && (app['rejection_reason'] as String?)?.isNotEmpty == true)
              _section('Rejection reason', [Text(app['rejection_reason'], style: const TextStyle(color: docDanger, fontSize: 12.5))]),
            const Text('DOCUMENTS', style: TextStyle(fontSize: 10, color: docMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
            const SizedBox(height: 8),
            if (documents.isEmpty)
              const Padding(padding: EdgeInsets.only(bottom: 12), child: Text('No documents attached.', style: TextStyle(color: docMuted, fontSize: 12.5)))
            else
              for (final d in documents) _documentTile(d),
          ],
        ),
        if (status == 'pending')
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: const BoxDecoration(color: docSurface, border: Border(top: BorderSide(color: docBorder))),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : _reject,
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: docDanger)),
                    child: const Text('Reject', style: TextStyle(color: docDanger)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(flex: 2, child: ElevatedButton(onPressed: _busy ? null : _approve, child: const Text('Approve'))),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _statusPill(String status) {
    final (bg, fg, label) = switch (status) {
      'approved' => (docSuccessBg, docSuccess, 'Approved'),
      'rejected' => (docDangerBg, docDanger, 'Rejected'),
      _ => (docWarningBg, docWarning, 'Pending'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 10.5)),
    );
  }

  Widget _section(String title, List<Widget?> children) {
    final visible = children.whereType<Widget>().toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title.toUpperCase(), style: const TextStyle(fontSize: 10, color: docMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
        const SizedBox(height: 8),
        DocCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: visible)),
      ]),
    );
  }

  Widget? _row(String label, String? value) {
    if (value == null || value.isEmpty) return null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 130, child: Text(label, style: const TextStyle(color: docMuted, fontSize: 12, fontWeight: FontWeight.w600))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
      ]),
    );
  }

  Widget _documentTile(Map<String, dynamic> doc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: InkWell(
        borderRadius: BorderRadius.circular(docRadiusMd),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _DocumentViewerScreen(applicationId: widget.applicationId, document: doc))),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(color: docSurface, borderRadius: BorderRadius.circular(docRadiusMd), border: docCardBorder, boxShadow: docCardShadow),
          child: Row(children: [
            Container(width: 34, height: 34, decoration: BoxDecoration(color: docAccentLight, borderRadius: BorderRadius.circular(11)), child: const Icon(Icons.description_rounded, size: 16, color: docAccentDark)),
            const SizedBox(width: 12),
            Expanded(child: Text(_kDocTypeLabels[doc['document_type']] ?? doc['document_type'], style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5))),
            const Icon(Icons.chevron_right_rounded, color: docMuted),
          ]),
        ),
      ),
    );
  }
}

class _DocumentViewerScreen extends StatelessWidget {
  final String applicationId;
  final Map<String, dynamic> document;
  const _DocumentViewerScreen({required this.applicationId, required this.document});

  @override
  Widget build(BuildContext context) {
    return DocGradientScaffold(
      appBar: AppBar(title: Text(_kDocTypeLabels[document['document_type']] ?? 'Document')),
      body: FutureBuilder<Uint8List>(
        future: context.read<AuthProvider>().api.getApplicationDocumentBytes(applicationId, document['id'] as String),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const LoadingCenter();
          if (snapshot.hasError || snapshot.data == null) return const Center(child: Text("Couldn't load this document.", style: TextStyle(color: docMuted)));
          final bytes = snapshot.data!;
          final filename = (document['filename'] as String? ?? '').toLowerCase();
          if (filename.endsWith('.pdf')) {
            return pdfx.PdfView(controller: pdfx.PdfController(document: pdfx.PdfDocument.openData(bytes)));
          }
          return InteractiveViewer(minScale: 1, maxScale: 4, child: Center(child: Image.memory(bytes, fit: BoxFit.contain)));
        },
      ),
    );
  }
}
