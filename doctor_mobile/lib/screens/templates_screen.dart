import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth_provider.dart';
import '../theme.dart';

/// Reusable prescriptions and lab-test panels. These aren't just a management list -- they're
/// loaded directly into the consultation screen's Add Medicine / Select Lab Tests sheets (see
/// consultation_screen.dart's "Load from template" / "Load panel" actions), which is what makes
/// them actually save time instead of being a disconnected admin page.
class TemplatesScreen extends StatefulWidget {
  const TemplatesScreen({super.key});
  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 2, vsync: this);
  List<dynamic>? _prescriptionTemplates;
  List<dynamic>? _labPanels;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().api;
    final results = await Future.wait([api.getPrescriptionTemplates(), api.getLabTestPanels()]);
    if (mounted) {
      setState(() {
        _prescriptionTemplates = results[0];
        _labPanels = results[1];
      });
    }
  }

  Future<void> _addPrescriptionTemplate() async {
    final nameController = TextEditingController();
    final diagnosisController = TextEditingController();
    final medicineController = TextEditingController();
    final strengthController = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New prescription template'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Template name', hintText: 'e.g. Common cold')),
            const SizedBox(height: 10),
            TextField(controller: diagnosisController, decoration: const InputDecoration(labelText: 'Diagnosis (optional)')),
            const SizedBox(height: 10),
            const Align(alignment: Alignment.centerLeft, child: Text('One medicine to start — add more from the consultation screen after loading it.', style: TextStyle(fontSize: 11.5, color: docMuted))),
            const SizedBox(height: 8),
            TextField(controller: medicineController, decoration: const InputDecoration(labelText: 'Medicine name')),
            const SizedBox(height: 10),
            TextField(controller: strengthController, decoration: const InputDecoration(labelText: 'Strength (optional)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Save')),
        ],
      ),
    );
    if (saved != true || !mounted) return;
    if (nameController.text.trim().isEmpty || medicineController.text.trim().isEmpty) return;
    try {
      await context.read<AuthProvider>().api.addPrescriptionTemplate({
        'name': nameController.text.trim(),
        'diagnosis_text': diagnosisController.text.trim().isEmpty ? null : diagnosisController.text.trim(),
        'line_items': [
          {'medicine_name': medicineController.text.trim(), 'strength': strengthController.text.trim().isEmpty ? null : strengthController.text.trim()},
        ],
      });
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _deletePrescriptionTemplate(String id) async {
    await context.read<AuthProvider>().api.deletePrescriptionTemplate(id);
    _load();
  }

  Future<void> _addLabPanel() async {
    final nameController = TextEditingController();
    final testsController = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New lab panel'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Panel name', hintText: 'e.g. Diabetes panel')),
          const SizedBox(height: 10),
          TextField(controller: testsController, maxLines: 3, decoration: const InputDecoration(labelText: 'Test names, comma-separated')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Save')),
        ],
      ),
    );
    if (saved != true || !mounted) return;
    final tests = testsController.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
    if (nameController.text.trim().isEmpty || tests.isEmpty) return;
    try {
      await context.read<AuthProvider>().api.addLabTestPanel({'name': nameController.text.trim(), 'test_names': tests});
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _deleteLabPanel(String id) async {
    await context.read<AuthProvider>().api.deleteLabTestPanel(id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return DocGradientScaffold(
      appBar: AppBar(
        title: const Text('Templates'),
        bottom: TabBar(controller: _tabController, tabs: const [Tab(text: 'Prescriptions'), Tab(text: 'Lab panels')]),
      ),
      body: _prescriptionTemplates == null
          ? const LoadingCenter()
          : TabBarView(controller: _tabController, children: [
              _PrescriptionTemplatesList(templates: _prescriptionTemplates!, onAdd: _addPrescriptionTemplate, onDelete: _deletePrescriptionTemplate),
              _LabPanelsList(panels: _labPanels ?? [], onAdd: _addLabPanel, onDelete: _deleteLabPanel),
            ]),
    );
  }
}

class _PrescriptionTemplatesList extends StatelessWidget {
  final List<dynamic> templates;
  final VoidCallback onAdd;
  final void Function(String id) onDelete;
  const _PrescriptionTemplatesList({required this.templates, required this.onAdd, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: onAdd, icon: const Icon(Icons.add_rounded, size: 16), label: const Text('New template'))),
        const SizedBox(height: 14),
        if (templates.isEmpty) const EmptyState(icon: Icons.description_outlined, message: 'No templates yet.'),
        for (final t in templates.cast<Map<String, dynamic>>())
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: DocCard(
              padding: const EdgeInsets.all(13),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t['name'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                    if ((t['diagnosis_text'] as String? ?? '').isNotEmpty) Text(t['diagnosis_text'], style: const TextStyle(fontSize: 11.5, color: docMuted)),
                    Text(
                      (t['line_items'] as List).map((li) => li['medicine_name']).join(', '),
                      style: const TextStyle(fontSize: 11.5, color: docAccent),
                    ),
                  ]),
                ),
                InkWell(onTap: () => onDelete(t['id'] as String), child: const Icon(Icons.delete_outline_rounded, size: 18, color: docMutedDim)),
              ]),
            ),
          ),
      ],
    );
  }
}

class _LabPanelsList extends StatelessWidget {
  final List<dynamic> panels;
  final VoidCallback onAdd;
  final void Function(String id) onDelete;
  const _LabPanelsList({required this.panels, required this.onAdd, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: onAdd, icon: const Icon(Icons.add_rounded, size: 16), label: const Text('New panel'))),
        const SizedBox(height: 14),
        if (panels.isEmpty) const EmptyState(icon: Icons.science_outlined, message: 'No lab panels yet.'),
        for (final p in panels.cast<Map<String, dynamic>>())
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: DocCard(
              padding: const EdgeInsets.all(13),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p['name'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                    Text((p['test_names'] as List).join(', '), style: const TextStyle(fontSize: 11.5, color: docAccent)),
                  ]),
                ),
                InkWell(onTap: () => onDelete(p['id'] as String), child: const Icon(Icons.delete_outline_rounded, size: 18, color: docMutedDim)),
              ]),
            ),
          ),
      ],
    );
  }
}
