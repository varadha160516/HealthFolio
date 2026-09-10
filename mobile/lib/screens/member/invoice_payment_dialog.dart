import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../auth_provider.dart';
import '../../theme.dart';

enum _PayStep { choose, processing, success }

/// Shown from HomeShell's invoice poll right after a doctor completes a visit with a fee entered.
/// Payment here is a demo flow only — there is no real payment gateway behind this, "paying"
/// just calls the API's mock /invoices/:id/pay, which marks the invoice paid immediately. The QR
/// code is a plain descriptive text payload (not a upi:// intent URI) so it can never be mistaken
/// for something a real banking app would act on.
class InvoicePaymentDialog extends StatefulWidget {
  final Map<String, dynamic> invoice;
  const InvoicePaymentDialog({super.key, required this.invoice});

  @override
  State<InvoicePaymentDialog> createState() => _InvoicePaymentDialogState();
}

class _InvoicePaymentDialogState extends State<InvoicePaymentDialog> {
  _PayStep _step = _PayStep.choose;
  String? _error;

  Future<void> _pay(String method) async {
    final api = context.read<AuthProvider>().api; // captured before the async gap below
    setState(() {
      _step = _PayStep.processing;
      _error = null;
    });
    try {
      await Future.delayed(const Duration(milliseconds: 1600)); // simulated gateway round-trip
      await api.payInvoice(widget.invoice['id'] as String, method);
      if (mounted) setState(() => _step = _PayStep.success);
    } catch (e) {
      if (mounted) {
        setState(() {
          _step = _PayStep.choose;
          _error = 'Payment could not be completed — please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step != _PayStep.processing,
      child: Dialog(
        backgroundColor: careloopSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(careloopRadiusXl)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: switch (_step) {
              _PayStep.choose => _buildChoose(),
              _PayStep.processing => _buildProcessing(),
              _PayStep.success => _buildSuccess(),
            },
          ),
        ),
      ),
    );
  }

  Widget _buildChoose() {
    final invoice = widget.invoice;
    final provider = invoice['provider'] as Map<String, dynamic>?;
    final member = invoice['member'] as Map<String, dynamic>?;
    final appt = invoice['appointment'] as Map<String, dynamic>?;
    final dt = appt?['datetime'] != null ? DateTime.tryParse(appt!['datetime'] as String)?.toLocal() : null;
    final fee = (invoice['fee_amount'] as num?)?.toDouble() ?? 0;
    final invoiceId = invoice['id'] as String;
    final qrPayload = 'CareLoop Invoice ${invoiceId.substring(0, 8).toUpperCase()} · ₹${fee.toStringAsFixed(2)} · Demo QR, not a real payment';

    return SingleChildScrollView(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Invoice', style: careloopSectionHeading().copyWith(fontSize: 19)),
              const Text('Visit consultation fee', style: TextStyle(fontSize: 11.5, color: careloopMuted)),
            ]),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => Navigator.of(context).pop(),
            child: Container(width: 30, height: 30, decoration: BoxDecoration(color: careloopSurfaceRaised, shape: BoxShape.circle), child: const Icon(Icons.close_rounded, size: 16)),
          ),
        ]),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: careloopSurfaceRaised, borderRadius: BorderRadius.circular(careloopRadiusMd)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _row('Doctor', '${provider?['name'] ?? '—'}${provider?['specialty'] != null ? ' · ${provider!['specialty']}' : ''}'),
            _row('Patient', member?['name'] as String? ?? '—'),
            if (dt != null) _row('Visit', '${DateFormat('MMM d, yyyy').format(dt)} · ${DateFormat('h:mm a').format(dt)}'),
          ]),
        ),
        const SizedBox(height: 16),
        Center(
          child: Column(children: [
            const Text('AMOUNT DUE', style: TextStyle(fontSize: 10, color: careloopMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
            const SizedBox(height: 3),
            Text('₹${fee.toStringAsFixed(2)}', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: careloopTextPrimary)),
          ]),
        ),
        const SizedBox(height: 16),
        Center(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(careloopRadiusMd), border: careloopCardBorder),
            child: QrImageView(data: qrPayload, size: 140, backgroundColor: Colors.white),
          ),
        ),
        const SizedBox(height: 4),
        const Center(child: Text('Demo QR — scanning it does not move real money', style: TextStyle(fontSize: 10.5, color: careloopMutedDim), textAlign: TextAlign.center)),
        const SizedBox(height: 18),
        if (_error != null) ...[
          Text(_error!, style: const TextStyle(color: careloopDanger, fontSize: 12.5)),
          const SizedBox(height: 10),
        ],
        const Text('CHOOSE PAYMENT METHOD', style: TextStyle(fontSize: 10, color: careloopMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
        const SizedBox(height: 8),
        _payMethodTile(icon: Icons.credit_card_rounded, label: 'Credit / Debit Card', onTap: () => _pay('card')),
        const SizedBox(height: 8),
        _payMethodTile(icon: Icons.qr_code_2_rounded, label: 'UPI', onTap: () => _pay('upi')),
        const SizedBox(height: 8),
        _payMethodTile(icon: Icons.account_balance_rounded, label: 'Net Banking', onTap: () => _pay('netbanking')),
        const SizedBox(height: 10),
        Center(
          child: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Pay later')),
        ),
      ]),
    );
  }

  Widget _buildProcessing() {
    return SizedBox(
      height: 220,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const CircularProgressIndicator(color: careloopPrimary),
        const SizedBox(height: 16),
        const Text('Processing payment…', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
      ]),
    );
  }

  Widget _buildSuccess() {
    final fee = (widget.invoice['fee_amount'] as num?)?.toDouble() ?? 0;
    return SizedBox(
      height: 260,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 56,
          height: 56,
          decoration: const BoxDecoration(gradient: LinearGradient(colors: careloopPrimaryGradient), shape: BoxShape.circle),
          child: const Icon(Icons.check_rounded, color: Colors.white, size: 28),
        ),
        const SizedBox(height: 14),
        const Text('Payment successful', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 4),
        Text('₹${fee.toStringAsFixed(2)} paid', style: const TextStyle(color: careloopMuted, fontSize: 13)),
        const SizedBox(height: 20),
        ElevatedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
      ]),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 62, child: Text(label, style: const TextStyle(fontSize: 11.5, color: careloopMuted, fontWeight: FontWeight.w600))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
        ]),
      );

  Widget _payMethodTile({required IconData icon, required String label, required VoidCallback onTap}) => InkWell(
        borderRadius: BorderRadius.circular(careloopRadiusMd),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(color: careloopSurface, border: careloopCardBorder, borderRadius: BorderRadius.circular(careloopRadiusMd)),
          child: Row(children: [
            Icon(icon, size: 19, color: careloopAccent),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5))),
            const Icon(Icons.chevron_right_rounded, size: 18, color: careloopMutedDim),
          ]),
        ),
      );
}
