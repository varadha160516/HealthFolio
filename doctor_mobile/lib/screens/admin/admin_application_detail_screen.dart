import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
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
    final duplicates = (_detail!['duplicates'] as Map<String, dynamic>?) ?? {};
    final providerDupes = ((duplicates['providers'] as List?) ?? []).cast<Map<String, dynamic>>();
    final appDupes = ((duplicates['applications'] as List?) ?? []).cast<Map<String, dynamic>>();
    final hasDuplicates = providerDupes.isNotEmpty || appDupes.isNotEmpty;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(hasDuplicates ? 'Registration number already in use' : 'Approve this application?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: hasDuplicates
              ? [
                  const Text(
                    'This registration number already belongs to another provider or application. Approving anyway still creates a live login for this applicant immediately.',
                    style: TextStyle(color: docDanger, fontSize: 12.5),
                  ),
                  const SizedBox(height: 10),
                  for (final p in providerDupes) Text('• Approved provider: ${p['name']}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  for (final a in appDupes) Text('• ${a['status']} application: ${a['full_name']}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                ]
              : [const Text('This creates a live login for the applicant immediately.')],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: hasDuplicates ? ElevatedButton.styleFrom(backgroundColor: docDanger) : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(hasDuplicates ? 'Approve anyway' : 'Approve'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final api = context.read<AuthProvider>().api;
      await api.approveProviderApplication(widget.applicationId, overrideDuplicate: hasDuplicates);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyOnNmc() async {
    final uri = Uri.parse('https://www.nmc.org.in/information-desk/indian-medical-register/');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
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
    final ocrExtraction = _detail!['ocrExtraction'] as Map<String, dynamic>?;
    final duplicates = (_detail!['duplicates'] as Map<String, dynamic>?) ?? {};
    final providerDupes = ((duplicates['providers'] as List?) ?? []).cast<Map<String, dynamic>>();
    final appDupes = ((duplicates['applications'] as List?) ?? []).cast<Map<String, dynamic>>();
    final hasDuplicates = providerDupes.isNotEmpty || appDupes.isNotEmpty;

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
            if (hasDuplicates) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: docDangerBg, borderRadius: BorderRadius.circular(docRadiusMd)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.warning_amber_rounded, size: 15, color: docDanger),
                    const SizedBox(width: 6),
                    const Text('REGISTRATION NUMBER ALREADY IN USE', style: TextStyle(fontSize: 10, color: docDanger, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
                  ]),
                  const SizedBox(height: 8),
                  for (final p in providerDupes) Text('• Approved provider: ${p['name']}', style: const TextStyle(fontSize: 12.5, color: docDanger, fontWeight: FontWeight.w600)),
                  for (final a in appDupes) Text('• ${a['status']} application: ${a['full_name']}', style: const TextStyle(fontSize: 12.5, color: docDanger, fontWeight: FontWeight.w600)),
                ]),
              ),
            ],
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
                if ((app['registration_number'] as String?)?.isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  TextButton.icon(
                    onPressed: _verifyOnNmc,
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    icon: const Icon(Icons.open_in_new_rounded, size: 14),
                    label: const Text('Look up on NMC\'s public register', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ],
            ]),
            if (app['role_requested'] == 'doctor')
              _section('What the certificate says', [
                if (ocrExtraction == null)
                  const Text('No registration certificate was read automatically — either none was attached, or it could not be read.', style: TextStyle(fontSize: 12, color: docMuted))
                else ...[
                  _ocrCompareRow('Full name', app['full_name'] as String?, ocrExtraction['full_name'] as String?),
                  _ocrCompareRow('Registration number', app['registration_number'] as String?, ocrExtraction['registration_number'] as String?),
                  _ocrCompareRow('Qualifications', app['qualifications'] as String?, ocrExtraction['qualifications'] as String?),
                  if ((ocrExtraction['registration_council'] as String?)?.isNotEmpty == true) _row('Issuing council (from certificate)', ocrExtraction['registration_council']),
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

  // Compares what the applicant typed against what the extraction pipeline read off the actually-
  // attached certificate — a plain-text nudge for the admin, not an automated pass/fail. A mismatch
  // is shown, never hidden or auto-resolved either way.
  Widget _ocrCompareRow(String label, String? typed, String? fromCertificate) {
    final hasTyped = typed != null && typed.isNotEmpty;
    final hasCert = fromCertificate != null && fromCertificate.isNotEmpty;
    if (!hasTyped && !hasCert) return const SizedBox.shrink();
    final matches = hasTyped && hasCert && _normalize(typed) == _normalize(fromCertificate);
    final mismatch = hasTyped && hasCert && !matches;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 130, child: Text(label, style: const TextStyle(color: docMuted, fontSize: 12, fontWeight: FontWeight.w600))),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Typed: ${hasTyped ? typed : '—'}', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: mismatch ? docDanger : docTextPrimary)),
            if (hasCert)
              Text(
                matches ? 'Certificate matches ✓' : 'Certificate says: $fromCertificate',
                style: TextStyle(fontSize: 11.5, color: matches ? docSuccess : docDanger, fontWeight: mismatch ? FontWeight.w600 : FontWeight.w400),
              )
            else
              const Text('Not readable from the attached certificate', style: TextStyle(fontSize: 11, color: docMutedDim, fontStyle: FontStyle.italic)),
          ]),
        ),
      ]),
    );
  }

  String? _normalize(String? s) => s?.trim().toLowerCase();

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
