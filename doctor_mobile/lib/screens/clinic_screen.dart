import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth_provider.dart';
import '../theme.dart';

/// Clinic details + doctor roster. Editing is clinic_admin-only server-side; a plain doctor sees
/// a read-only view of the same data.
class ClinicScreen extends StatefulWidget {
  const ClinicScreen({super.key});
  @override
  State<ClinicScreen> createState() => _ClinicScreenState();
}

class _ClinicScreenState extends State<ClinicScreen> {
  Map<String, dynamic>? _clinic;
  List<dynamic>? _providers;
  bool _notFound = false;
  bool _editing = false;
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().api;
    try {
      final results = await Future.wait([api.getMyClinic(), api.getClinicProviders()]);
      if (mounted) {
        setState(() {
          _clinic = results[0] as Map<String, dynamic>;
          _providers = results[1] as List<dynamic>;
          _nameController.text = _clinic!['name'] as String? ?? '';
          _addressController.text = _clinic!['address'] as String? ?? '';
          _cityController.text = _clinic!['city'] as String? ?? '';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _notFound = true);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await context.read<AuthProvider>().api.updateClinic({
        'name': _nameController.text.trim(),
        'address': _addressController.text.trim(),
        'city': _cityController.text.trim(),
      });
      await _load();
      if (mounted) setState(() => _editing = false);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AuthProvider>().session!;
    final isAdmin = session.role == 'provider_clinic_admin';

    if (_notFound) {
      return DocGradientScaffold(
        appBar: AppBar(title: const Text('Clinic')),
        body: const Center(child: EmptyState(icon: Icons.local_hospital_outlined, message: 'Not associated with a clinic.')),
      );
    }
    if (_clinic == null) return const DocGradientScaffold(body: LoadingCenter());

    return DocGradientScaffold(
      appBar: AppBar(
        title: const Text('Clinic'),
        actions: [
          if (isAdmin && !_editing) IconButton(icon: const Icon(Icons.edit_rounded), onPressed: () => setState(() => _editing = true)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const Text('CLINIC DETAILS', style: TextStyle(fontSize: 10, color: docMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
          const SizedBox(height: 8),
          DocCard(
            child: _editing
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Clinic name')),
                    const SizedBox(height: 10),
                    TextField(controller: _addressController, decoration: const InputDecoration(labelText: 'Address')),
                    const SizedBox(height: 10),
                    TextField(controller: _cityController, decoration: const InputDecoration(labelText: 'City')),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: OutlinedButton(onPressed: () => setState(() => _editing = false), child: const Text('Cancel'))),
                      const SizedBox(width: 10),
                      Expanded(child: ElevatedButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save'))),
                    ]),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_clinic!['name'] as String? ?? 'Unnamed clinic', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    if ((_clinic!['address'] as String? ?? '').isNotEmpty) Text(_clinic!['address'], style: const TextStyle(fontSize: 12.5, color: docMuted)),
                    if ((_clinic!['city'] as String? ?? '').isNotEmpty) Text(_clinic!['city'], style: const TextStyle(fontSize: 12.5, color: docMuted)),
                  ]),
          ),
          const SizedBox(height: 20),
          const Text('DOCTORS AT THIS CLINIC', style: TextStyle(fontSize: 10, color: docMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
          const SizedBox(height: 8),
          for (final p in (_providers ?? []).cast<Map<String, dynamic>>())
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: DocCard(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: docAccentLight, borderRadius: BorderRadius.circular(10)),
                    child: Icon(p['type'] == 'clinic_admin' ? Icons.badge_rounded : Icons.local_hospital_rounded, size: 16, color: docPrimary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p['name'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      Text(p['type'] == 'clinic_admin' ? 'Clinic admin' : (p['specialty'] as String? ?? 'Doctor'), style: const TextStyle(fontSize: 11, color: docMuted)),
                    ]),
                  ),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}
