import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth_provider.dart';
import '../theme.dart';
import 'provider_application_screen.dart';

class ApplicationStatusScreen extends StatefulWidget {
  const ApplicationStatusScreen({super.key});
  @override
  State<ApplicationStatusScreen> createState() => _ApplicationStatusScreenState();
}

class _ApplicationStatusScreenState extends State<ApplicationStatusScreen> {
  final _email = TextEditingController();
  final _referenceCode = TextEditingController();
  bool _checking = false;
  String? _error;
  Map<String, dynamic>? _result;

  Future<void> _check() async {
    if (_email.text.trim().isEmpty || _referenceCode.text.trim().isEmpty) {
      setState(() => _error = 'Enter both your email and reference code');
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
      _result = null;
    });
    try {
      final api = context.read<AuthProvider>().api;
      final result = await api.getApplicationStatus(email: _email.text.trim(), referenceCode: _referenceCode.text.trim().toUpperCase());
      if (mounted) setState(() => _result = result);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _resubmit() async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ProviderApplicationScreen(existingApplication: _result, referenceCode: _referenceCode.text.trim().toUpperCase())),
    );
    if (updated == true) _check();
  }

  @override
  Widget build(BuildContext context) {
    final status = _result?['status'] as String?;
    return DocGradientScaffold(
      appBar: AppBar(title: const Text('Application status')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
        children: [
          TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email you applied with')),
          const SizedBox(height: 10),
          TextField(controller: _referenceCode, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Reference code', hintText: 'APP-XXXXXX')),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _checking ? null : _check,
              child: _checking ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Check status'),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!, style: const TextStyle(color: docDanger, fontSize: 12.5)),
          ],
          if (_result != null) ...[
            const SizedBox(height: 22),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: docSurface, borderRadius: BorderRadius.circular(docRadiusMd), border: docCardBorder, boxShadow: docCardShadow),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(_result!['full_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                  _statusPill(status),
                ]),
                const SizedBox(height: 6),
                Text('Applied as ${_result!['role_requested'] == 'doctor' ? 'Doctor' : 'Clinic front desk'}', style: const TextStyle(color: docMuted, fontSize: 12)),
                if (status == 'rejected' && (_result!['rejection_reason'] as String?)?.isNotEmpty == true) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: docDangerBg, borderRadius: BorderRadius.circular(docRadiusSm)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('REASON', style: TextStyle(fontSize: 9.5, color: docDanger, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
                      const SizedBox(height: 4),
                      Text(_result!['rejection_reason'], style: const TextStyle(color: docDanger, fontSize: 12.5)),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _resubmit, child: const Text('Update & resubmit'))),
                ],
                if (status == 'approved') ...[
                  const SizedBox(height: 12),
                  const Text('You can now sign in with the email and password you applied with.', style: TextStyle(color: docSuccess, fontSize: 12.5, fontWeight: FontWeight.w600)),
                ],
                if (status == 'pending') ...[
                  const SizedBox(height: 12),
                  const Text('Still under review — check back soon.', style: TextStyle(color: docMuted, fontSize: 12.5)),
                ],
              ]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusPill(String? status) {
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
}
