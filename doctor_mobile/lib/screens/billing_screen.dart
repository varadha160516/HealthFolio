import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../auth_provider.dart';
import '../theme.dart';

/// Every invoice this doctor has issued, with a simple revenue summary — the provider-side
/// mirror of the member's own invoice list. Summary buckets are computed client-side from the
/// same list rather than duplicating date logic server-side.
class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key});
  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  List<dynamic>? _invoices;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final invoices = await context.read<AuthProvider>().api.getMyInvoices();
    if (mounted) setState(() => _invoices = invoices);
  }

  @override
  Widget build(BuildContext context) {
    if (_invoices == null) return const DocGradientScaffold(body: LoadingCenter());
    final invoices = _invoices!.cast<Map<String, dynamic>>();
    final now = DateTime.now();
    final today = invoices.where((i) => _isSameDay(DateTime.parse(i['issued_at'] as String).toLocal(), now));
    final thisMonth = invoices.where((i) {
      final dt = DateTime.parse(i['issued_at'] as String).toLocal();
      return dt.year == now.year && dt.month == now.month;
    });
    final paidThisMonth = thisMonth.where((i) => i['status'] == 'paid').fold<double>(0, (sum, i) => sum + (i['fee_amount'] as num).toDouble());
    final pendingCount = invoices.where((i) => i['status'] == 'pending').length;

    return DocGradientScaffold(
      appBar: AppBar(title: const Text('Billing')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Row(children: [
              Expanded(child: _StatCard(label: 'Today', value: '${today.length}', sub: 'invoices')),
              const SizedBox(width: 10),
              Expanded(child: _StatCard(label: 'This month', value: '₹${paidThisMonth.toStringAsFixed(0)}', sub: 'collected')),
              const SizedBox(width: 10),
              Expanded(child: _StatCard(label: 'Pending', value: '$pendingCount', sub: 'unpaid')),
            ]),
            const SizedBox(height: 18),
            const Text('ALL INVOICES', style: TextStyle(fontSize: 10, color: docMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
            const SizedBox(height: 8),
            if (invoices.isEmpty)
              const EmptyState(icon: Icons.receipt_long_rounded, message: 'No invoices issued yet.')
            else
              for (final inv in invoices) _InvoiceRow(invoice: inv),
          ],
        ),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  const _StatCard({required this.label, required this.value, required this.sub});
  @override
  Widget build(BuildContext context) {
    return DocCard(
      padding: const EdgeInsets.all(13),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(), style: const TextStyle(fontSize: 9.5, color: docMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        Text(sub, style: const TextStyle(fontSize: 10.5, color: docMuted)),
      ]),
    );
  }
}

class _InvoiceRow extends StatelessWidget {
  final Map<String, dynamic> invoice;
  const _InvoiceRow({required this.invoice});
  @override
  Widget build(BuildContext context) {
    final status = invoice['status'] as String;
    final (bg, fg, label) = switch (status) {
      'paid' => (docSuccessBg, docSuccess, 'Paid'),
      'cancelled' => (docDangerBg, docDanger, 'Cancelled'),
      _ => (docWarningBg, docWarning, 'Pending'),
    };
    final issuedAt = DateTime.tryParse(invoice['issued_at'] as String? ?? '')?.toLocal();
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: DocCard(
        padding: const EdgeInsets.all(13),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(invoice['member_name'] as String? ?? 'Patient', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
              if (issuedAt != null) Text(DateFormat('MMM d, yyyy · h:mm a').format(issuedAt), style: const TextStyle(fontSize: 11, color: docMuted)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('₹${(invoice['fee_amount'] as num).toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
              child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 10)),
            ),
          ]),
        ]),
      ),
    );
  }
}
