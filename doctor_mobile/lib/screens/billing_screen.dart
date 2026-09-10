import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../auth_provider.dart';
import '../theme.dart';

/// Every invoice this doctor has issued, with a simple revenue summary — the provider-side
/// mirror of the member's own invoice list. Summary buckets are computed client-side from the
/// same list rather than duplicating date logic server-side. Search/date-filter hit the server
/// (?q=/?from=/?to= on GET /providers/me/invoices); "export" copies the current filtered list as
/// CSV to the clipboard rather than pulling in a file-sharing package for one button.
class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key});
  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  List<dynamic>? _invoices;
  final _searchController = TextEditingController();
  DateTimeRange? _dateRange;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().api;
    final invoices = await api.getMyInvoices(
      query: _searchController.text.trim(),
      from: _dateRange?.start.toIso8601String().substring(0, 10),
      to: _dateRange?.end.toIso8601String().substring(0, 10),
    );
    if (mounted) setState(() => _invoices = invoices);
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 730)),
      lastDate: DateTime.now(),
      initialDateRange: _dateRange,
    );
    if (picked == null) return;
    setState(() => _dateRange = picked);
    _load();
  }

  void _clearDateRange() {
    setState(() => _dateRange = null);
    _load();
  }

  Future<void> _exportCsv() async {
    if (_invoices == null || _invoices!.isEmpty) return;
    final buffer = StringBuffer('Patient,Date,Fee,Status,Payment Method\n');
    for (final inv in _invoices!.cast<Map<String, dynamic>>()) {
      final issuedAt = DateTime.tryParse(inv['issued_at'] as String? ?? '')?.toLocal();
      final dateStr = issuedAt != null ? DateFormat('yyyy-MM-dd HH:mm').format(issuedAt) : '';
      buffer.writeln('"${inv['member_name'] ?? ''}",$dateStr,${inv['fee_amount']},${inv['status']},${inv['payment_method'] ?? ''}');
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('CSV copied to clipboard — paste into a spreadsheet')));
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
      appBar: AppBar(
        title: const Text('Billing'),
        actions: [IconButton(icon: const Icon(Icons.ios_share_rounded), tooltip: 'Export CSV', onPressed: _exportCsv)],
      ),
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
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                labelText: 'Search by patient name',
                suffixIcon: IconButton(icon: const Icon(Icons.search_rounded), onPressed: _load),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDateRange,
                  icon: const Icon(Icons.date_range_rounded, size: 16),
                  label: Text(_dateRange == null
                      ? 'Filter by date'
                      : '${DateFormat('MMM d').format(_dateRange!.start)} – ${DateFormat('MMM d').format(_dateRange!.end)}'),
                ),
              ),
              if (_dateRange != null) IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: _clearDateRange),
            ]),
            const SizedBox(height: 18),
            const Text('INVOICES', style: TextStyle(fontSize: 10, color: docMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
            const SizedBox(height: 8),
            if (invoices.isEmpty)
              const EmptyState(icon: Icons.receipt_long_rounded, message: 'No invoices found.')
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
