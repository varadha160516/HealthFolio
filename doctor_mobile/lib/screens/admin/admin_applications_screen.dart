import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../auth_provider.dart';
import '../../theme.dart';
import 'admin_application_detail_screen.dart';

class AdminApplicationsScreen extends StatefulWidget {
  const AdminApplicationsScreen({super.key});
  @override
  State<AdminApplicationsScreen> createState() => _AdminApplicationsScreenState();
}

class _AdminApplicationsScreenState extends State<AdminApplicationsScreen> {
  List<dynamic>? _applications;
  String _filter = 'pending';
  String _sort = 'newest';
  final _searchController = TextEditingController();
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().api;
    final list = await api.getProviderApplications(status: _filter, search: _search, sort: _sort);
    if (mounted) setState(() => _applications = list);
  }

  Future<void> _openDetail(Map<String, dynamic> app) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => AdminApplicationDetailScreen(applicationId: app['id'] as String)));
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          const Text('Provider applications', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          const Text('Review and approve new doctors and clinic staff', style: TextStyle(color: docMuted, fontSize: 11.5)),
          const SizedBox(height: 14),
          SizedBox(
            height: 34,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              _chip('pending', 'Pending'),
              _chip('approved', 'Approved'),
              _chip('rejected', 'Rejected'),
            ]),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search name, email, registration no.',
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  suffixIcon: _search.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _search = '');
                            _load();
                          },
                        ),
                ),
                onSubmitted: (v) {
                  setState(() => _search = v.trim());
                  _load();
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: _sort == 'newest' ? 'Newest first' : 'Oldest first',
              icon: Icon(_sort == 'newest' ? Icons.south_rounded : Icons.north_rounded, size: 20),
              onPressed: () {
                setState(() => _sort = _sort == 'newest' ? 'oldest' : 'newest');
                _load();
              },
            ),
          ]),
          const SizedBox(height: 14),
          if (_applications == null)
            const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: CircularProgressIndicator(color: docPrimary)))
          else if (_applications!.isEmpty)
            const EmptyState(icon: Icons.inbox_rounded, message: 'Nothing here.')
          else
            for (final a in _applications!.cast<Map<String, dynamic>>()) _applicationCard(a),
        ],
      ),
    );
  }

  Widget _chip(String value, String label) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(docRadiusPill),
        onTap: () {
          setState(() {
            _filter = value;
            _applications = null;
          });
          _load();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(color: selected ? docPrimary : docSurface, borderRadius: BorderRadius.circular(docRadiusPill), border: selected ? null : Border.all(color: docBorder)),
          child: Text(label, style: TextStyle(color: selected ? Colors.white : docTextPrimary, fontWeight: FontWeight.w600, fontSize: 12.5)),
        ),
      ),
    );
  }

  Widget _applicationCard(Map<String, dynamic> app) {
    final clinic = app['clinic_mode'] == 'new' ? app['new_clinic_name'] : null;
    final submitted = DateTime.tryParse(app['created_at'] as String? ?? '')?.toLocal();
    final documentCount = (app['document_count'] as num?)?.toInt() ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: InkWell(
        borderRadius: BorderRadius.circular(docRadiusMd),
        onTap: () => _openDetail(app),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(color: docSurface, borderRadius: BorderRadius.circular(docRadiusMd), border: docCardBorder, boxShadow: docCardShadow),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: docAccentLight, borderRadius: BorderRadius.circular(12)),
              child: Icon(app['role_requested'] == 'doctor' ? Icons.medical_services_rounded : Icons.support_agent_rounded, size: 18, color: docAccentDark),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(app['full_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                Text(
                  [app['role_requested'] == 'doctor' ? (app['specialty'] ?? 'Doctor') : 'Clinic front desk', clinic].where((v) => v != null).join(' · '),
                  style: const TextStyle(color: docMuted, fontSize: 11.5),
                ),
                Row(children: [
                  if (submitted != null) Text(DateFormat('MMM d, yyyy').format(submitted), style: const TextStyle(color: docMutedDim, fontSize: 10)),
                  if (submitted != null) const SizedBox(width: 6),
                  Icon(Icons.description_outlined, size: 11, color: documentCount == 0 ? docDanger : docMutedDim),
                  const SizedBox(width: 2),
                  Text(
                    documentCount == 0 ? 'No documents' : '$documentCount document${documentCount == 1 ? '' : 's'}',
                    style: TextStyle(color: documentCount == 0 ? docDanger : docMutedDim, fontSize: 10, fontWeight: documentCount == 0 ? FontWeight.w700 : FontWeight.w400),
                  ),
                ]),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: docMuted),
          ]),
        ),
      ),
    );
  }
}
