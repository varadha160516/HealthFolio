import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../api_client.dart';
import '../auth_provider.dart';
import '../data/medical_reference.dart';
import '../theme.dart';
import '../widgets/autocomplete_field.dart';
import 'patient_history_screen.dart';
import 'visit_summary_screen.dart';

const _commonSymptoms = ['Headache', 'Cough', 'Fatigue', 'Body pain', 'Nausea', 'Vomiting', 'Dizziness', 'Chills'];
const _respiratoryFindings = ['Clear lungs', 'Wheezing', 'Crepitations', 'Reduced air entry'];
const _adviceOptions = ['Rest', 'Hydration', 'Diet', 'Monitor temperature', 'Return if symptoms worsen'];

class ConsultationScreen extends StatefulWidget {
  final String appointmentId;
  const ConsultationScreen({super.key, required this.appointmentId});
  @override
  State<ConsultationScreen> createState() => _ConsultationScreenState();
}

class _ConsultationScreenState extends State<ConsultationScreen> {
  Map<String, dynamic>? _appt;
  List<dynamic> _vitals = [];
  List<dynamic> _labOrders = [];
  List<dynamic> _visitHistory = [];
  List<dynamic> _catalog = [];
  bool _loading = true;
  bool _busy = false;

  // Vitals quick-entry
  final _bpSys = TextEditingController();
  final _bpDia = TextEditingController();
  final _pulse = TextEditingController();
  final _temp = TextEditingController();
  final _spo2 = TextEditingController();
  final _rr = TextEditingController();
  final _weight = TextEditingController();
  final _height = TextEditingController();

  // Symptoms
  final _chiefComplaint = TextEditingController();
  final _duration = TextEditingController();
  final Set<String> _symptoms = {};

  // Examination
  final _condition = TextEditingController(text: 'Stable');
  final _consciousness = TextEditingController(text: 'Alert & oriented');
  final _hydration = TextEditingController(text: 'Adequate');
  final Set<String> _respiratory = {};
  final _cardiovascular = TextEditingController();
  final _abdomen = TextEditingController();
  final _cns = TextEditingController();

  // Diagnosis + medications
  final _diagnosis = TextEditingController();
  final _icd = TextEditingController();
  final List<Map<String, String>> _lineItems = [];

  // Lab orders
  final Set<String> _selectedTests = {};
  final _clinicalIndication = TextEditingController();

  // Notes
  final _assessment = TextEditingController();
  final Set<String> _advice = {};

  // Follow-up
  String _followUpAfter = '3_days';
  final _followUpReason = TextEditingController();

  ApiClient get _api => context.read<AuthProvider>().api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final appt = await _api.getAppointment(widget.appointmentId);
    final vitals = await _api.getVitals(widget.appointmentId);
    final labOrders = await _api.getLabOrders(widget.appointmentId);
    final notes = await _api.getConsultationNotes(widget.appointmentId);
    List<dynamic> history = [];
    try {
      history = await _api.getPatientVisitHistory(widget.appointmentId);
    } catch (_) {}
    List<dynamic> catalog = [];
    try {
      catalog = await _api.getLabTestCatalog();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _appt = appt;
      _vitals = vitals;
      _labOrders = labOrders;
      _visitHistory = history;
      _catalog = catalog;
      _loading = false;
      if (notes != null) {
        _chiefComplaint.text = notes['chief_complaint'] ?? '';
        _duration.text = notes['symptom_duration'] ?? '';
        _symptoms.addAll((notes['symptoms'] as List).cast<String>());
        final exam = notes['examination'] as Map<String, dynamic>;
        final general = exam['general'] as Map<String, dynamic>?;
        if (general != null) {
          _condition.text = general['condition'] ?? _condition.text;
          _consciousness.text = general['consciousness'] ?? _consciousness.text;
          _hydration.text = general['hydration'] ?? _hydration.text;
        }
        final system = exam['system'] as Map<String, dynamic>?;
        if (system != null) {
          _respiratory.addAll(((system['respiratory'] as List?) ?? []).cast<String>());
          _cardiovascular.text = (system['cardiovascular'] as String?) ?? '';
          _abdomen.text = (system['abdomen'] as String?) ?? '';
          _cns.text = (system['cns'] as String?) ?? '';
        }
        _assessment.text = notes['assessment_notes'] ?? '';
        _advice.addAll((notes['advice'] as List).cast<String>());
        _followUpAfter = notes['follow_up_after'] ?? '3_days';
        _followUpReason.text = notes['follow_up_reason'] ?? '';
      }
    });
  }

  Future<void> _snack(String msg) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _runBusy(Future<void> Function() fn) async {
    setState(() => _busy = true);
    try {
      await fn();
    } on ApiException catch (e) {
      await _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveVitals() async {
    if ([_bpSys, _bpDia, _pulse, _temp, _spo2, _rr, _weight, _height].every((c) => c.text.trim().isEmpty)) return;
    await _runBusy(() async {
      await _api.addVitals(widget.appointmentId, {
        'systolic_bp': _bpSys.text.trim().isEmpty ? null : num.tryParse(_bpSys.text),
        'diastolic_bp': _bpDia.text.trim().isEmpty ? null : num.tryParse(_bpDia.text),
        'heart_rate': _pulse.text.trim().isEmpty ? null : num.tryParse(_pulse.text),
        'temperature_f': _temp.text.trim().isEmpty ? null : num.tryParse(_temp.text),
        'spo2': _spo2.text.trim().isEmpty ? null : num.tryParse(_spo2.text),
        'respiratory_rate': _rr.text.trim().isEmpty ? null : num.tryParse(_rr.text),
        'weight_kg': _weight.text.trim().isEmpty ? null : num.tryParse(_weight.text),
        'height_cm': _height.text.trim().isEmpty ? null : num.tryParse(_height.text),
      });
      _vitals = await _api.getVitals(widget.appointmentId);
      for (final c in [_bpSys, _bpDia, _pulse, _temp, _spo2, _rr, _weight, _height]) {
        c.clear();
      }
      await _snack('Vitals saved');
    });
  }

  Future<void> _saveNotes({bool silent = false}) async {
    await _api.saveConsultationNotes(widget.appointmentId, {
      'chief_complaint': _chiefComplaint.text.trim(),
      'symptom_duration': _duration.text.trim(),
      'symptoms': _symptoms.toList(),
      'examination': {
        'general': {'condition': _condition.text.trim(), 'consciousness': _consciousness.text.trim(), 'hydration': _hydration.text.trim()},
        'system': {'respiratory': _respiratory.toList(), 'cardiovascular': _cardiovascular.text.trim(), 'abdomen': _abdomen.text.trim(), 'cns': _cns.text.trim()},
      },
      'assessment_notes': _assessment.text.trim(),
      'advice': _advice.toList(),
      'follow_up_after': _followUpAfter,
      'follow_up_reason': _followUpReason.text.trim(),
    });
    if (!silent) await _snack('Notes saved');
  }

  Future<void> _issuePrescription() async {
    if (_lineItems.isEmpty) {
      await _snack('Add at least one medicine first');
      return;
    }
    await _runBusy(() async {
      await _api.issuePrescription(
        widget.appointmentId,
        diagnosisText: _diagnosis.text.trim().isEmpty ? null : _diagnosis.text.trim(),
        icdCode: _icd.text.trim().isEmpty ? null : _icd.text.trim(),
        lineItems: _lineItems.map((li) => {'medicine_name': li['name'], 'strength': li['strength'], 'dosage': li['dosage'], 'frequency': li['frequency'], 'duration': li['duration'], 'instructions': li['instructions']}).toList(),
      );
      setState(() => _lineItems.clear());
      await _snack('Prescription issued');
    });
  }

  Future<void> _orderTests() async {
    if (_selectedTests.isEmpty) {
      await _snack('Select at least one test');
      return;
    }
    await _runBusy(() async {
      await _api.orderLabTests(widget.appointmentId, testNames: _selectedTests.toList(), clinicalIndication: _clinicalIndication.text.trim().isEmpty ? null : _clinicalIndication.text.trim());
      _labOrders = await _api.getLabOrders(widget.appointmentId);
      setState(() => _selectedTests.clear());
      await _snack('Tests ordered');
    });
  }

  Future<void> _openLabTestPicker() async {
    final byCategory = <String, List<Map<String, dynamic>>>{};
    for (final t in _catalog.cast<Map<String, dynamic>>()) {
      final cat = (t['category'] as String?)?.trim();
      final label = cat == null || cat.isEmpty
          ? 'Other'
          : cat == 'popular'
              ? 'Popular'
              : '${cat[0].toUpperCase()}${cat.substring(1)}';
      byCategory.putIfAbsent(label, () => []).add(t);
    }
    final order = ['Popular', 'Blood', 'Urine', 'Imaging', 'Other'];
    final categories = byCategory.keys.toList()..sort((a, b) => order.indexOf(a).compareTo(order.indexOf(b)));

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(docRadiusXl))),
      builder: (sheetContext) {
        String query = '';
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            bool matches(Map<String, dynamic> t) => query.isEmpty || (t['name'] as String).toLowerCase().contains(query.toLowerCase());
            return DraggableScrollableSheet(
              initialChildSize: 0.85,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (context, scrollController) => Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(width: 38, height: 4, margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: docAccentLight, borderRadius: BorderRadius.circular(999))),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('Select lab tests', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                      Text('${_selectedTests.length} selected', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: docAccentDark)),
                    ]),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: const InputDecoration(labelText: 'Search tests', prefixIcon: Icon(Icons.search_rounded, size: 20)),
                      onChanged: (v) => setSheetState(() => query = v),
                    ),
                  ]),
                ),
                Expanded(
                  child: _catalog.isEmpty
                      ? const Center(child: Text('No test catalog available right now.', style: TextStyle(color: docMuted, fontSize: 13)))
                      : ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                          children: [
                            for (final cat in categories) ...[
                              if (byCategory[cat]!.any(matches)) ...[
                                Padding(
                                  padding: const EdgeInsets.only(top: 12, bottom: 4),
                                  child: Text(cat.toUpperCase(), style: const TextStyle(fontSize: 10, color: docMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
                                ),
                                for (final t in byCategory[cat]!.where(matches))
                                  CheckboxListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    controlAffinity: ListTileControlAffinity.leading,
                                    activeColor: docPrimary,
                                    title: Text(t['name'] as String, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                                    value: _selectedTests.contains(t['name']),
                                    onChanged: (checked) => setSheetState(() {
                                      if (checked == true) {
                                        _selectedTests.add(t['name'] as String);
                                      } else {
                                        _selectedTests.remove(t['name']);
                                      }
                                    }),
                                  ),
                              ],
                            ],
                          ],
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(onPressed: () => Navigator.pop(sheetContext), child: Text('Done — ${_selectedTests.length} selected')),
                  ),
                ),
              ]),
            );
          },
        );
      },
    );
    setState(() {});
  }

  Future<void> _scheduleFollowUp() async {
    await _runBusy(() async {
      final res = await _api.scheduleFollowUp(widget.appointmentId, after: _followUpAfter, reason: _followUpReason.text.trim().isEmpty ? null : _followUpReason.text.trim());
      await _saveNotes(silent: true);
      await _snack(res['followUpAppointmentId'] != null ? 'Follow-up scheduled' : 'Follow-up preference saved');
    });
  }

  Future<void> _completeVisit() async {
    final fee = await _askConsultationFee();
    if (fee == null) return; // cancelled
    await _runBusy(() async {
      await _saveNotes(silent: true);
      await _api.completeVisit(widget.appointmentId, feeAmount: fee);
      if (mounted) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => VisitSummaryScreen(appointmentId: widget.appointmentId)));
      }
    });
  }

  // Generates the invoice the member sees in HealthFolio — every visit needs a fee entered before
  // it can be completed, so the invoice always has a real, doctor-stated amount rather than a
  // guessed default.
  Future<double?> _askConsultationFee() async {
    final controller = TextEditingController();
    String? error;
    return showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Consultation fee'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Enter the fee for this visit — the patient will see this on their invoice.', style: TextStyle(fontSize: 12.5, color: docMuted)),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Fee (₹)', errorText: error, prefixText: '₹ '),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final fee = double.tryParse(controller.text.trim());
                if (fee == null || fee < 0) {
                  setDialogState(() => error = 'Enter a valid amount');
                  return;
                }
                Navigator.of(dialogContext).pop(fee);
              },
              child: const Text('Complete Visit'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const DocGradientScaffold(body: LoadingCenter());
    final member = _appt!['member'] as Map<String, dynamic>?;
    final allergies = ((_appt!['unlockedData']?['summary']?['allergies'] as List?) ?? []).map((a) => a['value']).join(', ');
    final dob = member?['dob'] as String?;
    final age = dob != null ? (DateTime.now().difference(DateTime.tryParse(dob) ?? DateTime.now()).inDays / 365.25).floor() : null;

    return DocGradientScaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${member?['name'] ?? ''}${age != null ? ' · $age' : ''}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          Text(allergies.isEmpty ? 'No known allergies' : 'Allergy: $allergies', style: TextStyle(fontSize: 11, color: allergies.isEmpty ? docMuted : docDanger, fontWeight: FontWeight.w600)),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PatientHistoryScreen(appointmentId: widget.appointmentId))),
            child: const Text('History'),
          ),
        ],
      ),
      body: Stack(children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          children: [
            _section('Vitals', Icons.monitor_heart_rounded, [
              if (_vitals.isNotEmpty) _latestVitalsRow(_vitals.first as Map<String, dynamic>),
              if (_vitals.isNotEmpty) const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _numField(_bpSys, 'BP sys')),
                const SizedBox(width: 8),
                Expanded(child: _numField(_bpDia, 'BP dia')),
                const SizedBox(width: 8),
                Expanded(child: _numField(_pulse, 'Pulse')),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _numField(_temp, 'Temp °F')),
                const SizedBox(width: 8),
                Expanded(child: _numField(_spo2, 'SpO₂ %')),
                const SizedBox(width: 8),
                Expanded(child: _numField(_rr, 'Resp/min')),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _numField(_weight, 'Weight kg')),
                const SizedBox(width: 8),
                Expanded(child: _numField(_height, 'Height cm')),
                const Spacer(),
              ]),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: OutlinedButton(onPressed: _busy ? null : _saveVitals, child: const Text('Save vitals'))),
            ]),
            _section('Symptoms', Icons.sick_rounded, [
              TextField(controller: _chiefComplaint, decoration: const InputDecoration(labelText: 'Chief complaint')),
              const SizedBox(height: 8),
              TextField(controller: _duration, decoration: const InputDecoration(labelText: 'Duration (e.g. 2 days)')),
              const SizedBox(height: 10),
              Wrap(spacing: 7, runSpacing: 7, children: [for (final s in _commonSymptoms) _toggleChip(s, _symptoms.contains(s), () => setState(() => _symptoms.contains(s) ? _symptoms.remove(s) : _symptoms.add(s)))]),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: OutlinedButton(onPressed: _busy ? null : () => _saveNotes(), child: const Text('Save symptoms'))),
            ]),
            if (_visitHistory.isNotEmpty) _section('Previous history', Icons.history_rounded, [_previousHistorySnippet(_visitHistory.first as Map<String, dynamic>)]),
            _section('Clinical examination', Icons.fact_check_rounded, [
              const Text('GENERAL', style: TextStyle(fontSize: 10, color: docMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
              const SizedBox(height: 8),
              TextField(controller: _condition, decoration: const InputDecoration(labelText: 'Patient condition')),
              const SizedBox(height: 8),
              TextField(controller: _consciousness, decoration: const InputDecoration(labelText: 'Consciousness')),
              const SizedBox(height: 8),
              TextField(controller: _hydration, decoration: const InputDecoration(labelText: 'Hydration')),
              const SizedBox(height: 14),
              const Text('SYSTEM EXAMINATION', style: TextStyle(fontSize: 10, color: docMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
              const SizedBox(height: 8),
              const Text('Respiratory', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
              const SizedBox(height: 6),
              Wrap(spacing: 7, runSpacing: 7, children: [for (final f in _respiratoryFindings) _toggleChip(f, _respiratory.contains(f), () => setState(() => _respiratory.contains(f) ? _respiratory.remove(f) : _respiratory.add(f)))]),
              const SizedBox(height: 10),
              TextField(controller: _cardiovascular, decoration: const InputDecoration(labelText: 'Cardiovascular findings')),
              const SizedBox(height: 8),
              TextField(controller: _abdomen, decoration: const InputDecoration(labelText: 'Abdomen findings')),
              const SizedBox(height: 8),
              TextField(controller: _cns, decoration: const InputDecoration(labelText: 'CNS findings')),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: OutlinedButton(onPressed: _busy ? null : () => _saveNotes(), child: const Text('Save examination'))),
            ]),
            _section('Diagnosis & medications', Icons.medication_rounded, [
              TextField(controller: _diagnosis, decoration: const InputDecoration(labelText: 'Diagnosis')),
              const SizedBox(height: 8),
              TextField(controller: _icd, decoration: const InputDecoration(labelText: 'ICD-10 code (optional)')),
              const SizedBox(height: 12),
              for (int i = 0; i < _lineItems.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(color: docSurfaceRaised, borderRadius: BorderRadius.circular(docRadiusSm)),
                    child: Row(children: [
                      Expanded(
                        child: Text('${_lineItems[i]['name']} ${_lineItems[i]['strength'] ?? ''}\n${_lineItems[i]['dosage'] ?? ''} · ${_lineItems[i]['duration'] ?? ''}${(_lineItems[i]['instructions'] ?? '').isEmpty ? '' : ' · ${_lineItems[i]['instructions']}'}'
                                .trim(),
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                      ),
                      medicationTimeDots(_lineItems[i]['frequency']),
                      IconButton(icon: const Icon(Icons.edit_outlined, size: 15), onPressed: () => _addMedicineSheet(existing: _lineItems[i], editIndex: i)),
                      IconButton(icon: const Icon(Icons.close_rounded, size: 16), onPressed: () => setState(() => _lineItems.removeAt(i))),
                    ]),
                  ),
                ),
              OutlinedButton.icon(icon: const Icon(Icons.add_rounded, size: 16), label: const Text('Add medicine'), onPressed: _addMedicineSheet),
            ]),
            _section('Lab tests', Icons.science_rounded, [
              OutlinedButton.icon(
                icon: const Icon(Icons.search_rounded, size: 16),
                label: Text(_selectedTests.isEmpty ? 'Select tests…' : '${_selectedTests.length} test${_selectedTests.length == 1 ? '' : 's'} selected'),
                onPressed: _openLabTestPicker,
                style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft),
              ),
              if (_selectedTests.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 7, runSpacing: 7, children: [
                  for (final t in _selectedTests)
                    Container(
                      padding: const EdgeInsets.only(left: 12, right: 6, top: 6, bottom: 6),
                      decoration: BoxDecoration(color: docAccentLight, borderRadius: BorderRadius.circular(docRadiusPill)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(t, style: const TextStyle(color: docAccentDark, fontWeight: FontWeight.w600, fontSize: 12)),
                        InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: () => setState(() => _selectedTests.remove(t)),
                          child: const Padding(padding: EdgeInsets.all(3), child: Icon(Icons.close_rounded, size: 13, color: docAccentDark)),
                        ),
                      ]),
                    ),
                ]),
              ],
              const SizedBox(height: 10),
              TextField(controller: _clinicalIndication, decoration: const InputDecoration(labelText: 'Clinical indication')),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: OutlinedButton(onPressed: _busy ? null : _orderTests, child: Text('Order ${_selectedTests.isEmpty ? '' : _selectedTests.length} test${_selectedTests.length == 1 ? '' : 's'}'.trim()))),
              if (_labOrders.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),
                for (final o in _labOrders.cast<Map<String, dynamic>>())
                  Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('• ${(o['test_names'] as List).join(', ')}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
              ],
            ]),
            _section('Assessment & Plan', Icons.notes_rounded, [
              TextField(controller: _assessment, maxLines: 3, decoration: const InputDecoration(labelText: 'Notes')),
              const SizedBox(height: 10),
              const Text('ADVICE', style: TextStyle(fontSize: 10, color: docMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
              const SizedBox(height: 8),
              Wrap(spacing: 7, runSpacing: 7, children: [for (final a in _adviceOptions) _toggleChip(a, _advice.contains(a), () => setState(() => _advice.contains(a) ? _advice.remove(a) : _advice.add(a)))]),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: OutlinedButton(onPressed: _busy ? null : () => _saveNotes(), child: const Text('Save notes'))),
            ]),
            _section('Follow-up', Icons.event_repeat_rounded, [
              Wrap(spacing: 7, runSpacing: 7, children: [
                for (final o in const [('3_days', '3 days'), ('1_week', '1 week'), ('1_month', '1 month'), ('as_needed', 'As needed')])
                  _toggleChip(o.$2, _followUpAfter == o.$1, () => setState(() => _followUpAfter = o.$1)),
              ]),
              const SizedBox(height: 10),
              TextField(controller: _followUpReason, decoration: const InputDecoration(labelText: 'Follow-up reason')),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: OutlinedButton(onPressed: _busy ? null : _scheduleFollowUp, child: const Text('Schedule follow-up'))),
            ]),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _busy ? null : _issuePrescription, child: const Text('Sign & issue prescription'))),
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: const BoxDecoration(color: docSurface, border: Border(top: BorderSide(color: docBorder))),
            child: Row(children: [
              Expanded(child: OutlinedButton(onPressed: _busy ? null : () => _saveNotes(), child: const Text('Save as draft'))),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(icon: const Icon(Icons.check_rounded), label: const Text('Complete Visit'), onPressed: _busy ? null : _completeVisit),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _latestVitalsRow(Map<String, dynamic> v) {
    return Wrap(spacing: 8, runSpacing: 8, children: [
      if (v['systolic_bp'] != null) _pill('BP', '${v['systolic_bp']}/${v['diastolic_bp']}'),
      if (v['heart_rate'] != null) _pill('Pulse', '${v['heart_rate']}'),
      if (v['temperature_f'] != null) _pill('Temp', '${v['temperature_f']}°'),
      if (v['spo2'] != null) _pill('SpO₂', '${v['spo2']}%'),
    ]);
  }

  Widget _pill(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: docAccentLight, borderRadius: BorderRadius.circular(docRadiusSm)),
        child: Text('$label $value', style: const TextStyle(color: docAccent, fontWeight: FontWeight.w700, fontSize: 11.5)),
      );

  Widget _previousHistorySnippet(Map<String, dynamic> visit) {
    final dt = DateTime.tryParse(visit['datetime'] as String? ?? '')?.toLocal();
    final prescription = visit['prescription'] as Map<String, dynamic>?;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(dt != null ? DateFormat('MMM d, yyyy').format(dt) : '', style: const TextStyle(fontSize: 10.5, color: docMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
      const SizedBox(height: 8),
      if (prescription?['diagnosis_text'] != null) Text('Diagnosis: ${prescription!['diagnosis_text']}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
      TextButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PatientHistoryScreen(appointmentId: widget.appointmentId))),
        child: const Text('View all history'),
      ),
    ]);
  }

  Widget _numField(TextEditingController c, String label) => TextField(controller: c, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: label));

  Widget _toggleChip(String label, bool on, VoidCallback onTap) => InkWell(
        borderRadius: BorderRadius.circular(docRadiusPill),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(color: on ? docAccentLight : docSurfaceRaised, borderRadius: BorderRadius.circular(docRadiusPill), border: on ? Border.all(color: docAccent) : null),
          child: Text(label, style: TextStyle(color: on ? docAccent : docTextPrimary, fontWeight: FontWeight.w600, fontSize: 12)),
        ),
      );

  Widget _section(String title, IconData icon, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 16, color: docPrimary),
            const SizedBox(width: 7),
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 10),
          DocCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children)),
        ]),
      );

  Future<void> _addMedicineSheet({Map<String, String>? existing, int? editIndex}) async {
    final name = TextEditingController(text: existing?['name'] ?? '');
    final strength = TextEditingController(text: existing?['strength'] ?? '');
    final dosage = TextEditingController(text: existing?['dosage'] ?? '');
    final duration = TextEditingController(text: existing?['duration'] ?? '');
    final times = <String>{for (final t in _kTimesOfDay) if ((existing?['frequency'] ?? '').contains(t)) t};
    String? foodTiming = existing?['instructions']?.isEmpty ?? true ? null : existing!['instructions'];

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(docRadiusXl))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(sheetContext).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(existing != null ? 'Edit medicine' : 'Add medicine', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              AutocompleteField(label: 'Medicine', options: kCommonMedicines, controller: name),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: AutocompleteField(label: 'Strength', options: kCommonStrengths, controller: strength)),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: dosage, decoration: const InputDecoration(labelText: 'Dose'))),
              ]),
              const SizedBox(height: 8),
              AutocompleteField(label: 'Duration', options: kDurationOptions, controller: duration),
              const SizedBox(height: 14),
              const Text('TIME OF DAY', style: TextStyle(fontSize: 10, color: docMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
              const SizedBox(height: 8),
              Wrap(spacing: 7, runSpacing: 7, children: [
                for (final t in _kTimesOfDay)
                  _sheetToggle(t, times.contains(t), () => setSheetState(() => times.contains(t) ? times.remove(t) : times.add(t))),
              ]),
              const SizedBox(height: 14),
              const Text('WITH FOOD', style: TextStyle(fontSize: 10, color: docMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _sheetToggle('Before food', foodTiming == 'Before food', () => setSheetState(() => foodTiming = foodTiming == 'Before food' ? null : 'Before food'), fill: true)),
                const SizedBox(width: 8),
                Expanded(child: _sheetToggle('After food', foodTiming == 'After food', () => setSheetState(() => foodTiming = foodTiming == 'After food' ? null : 'After food'), fill: true)),
              ]),
              const SizedBox(height: 18),
              SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => Navigator.pop(sheetContext, true), child: Text(existing != null ? 'Save changes' : 'Add to prescription'))),
            ]),
          ),
        ),
      ),
    );
    if (saved == true && name.text.trim().isNotEmpty) {
      final item = {
        'name': name.text.trim(),
        'strength': strength.text.trim(),
        'dosage': dosage.text.trim(),
        'frequency': times.isEmpty ? '' : _kTimesOfDay.where(times.contains).join(', '),
        'duration': duration.text.trim(),
        'instructions': foodTiming ?? '',
      };
      setState(() {
        if (editIndex != null) {
          _lineItems[editIndex] = item;
        } else {
          _lineItems.add(item);
        }
      });
    }
  }

  Widget _sheetToggle(String label, bool on, VoidCallback onTap, {bool fill = false}) => InkWell(
        borderRadius: BorderRadius.circular(docRadiusPill),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: fill ? 13 : 14, vertical: 10),
          alignment: fill ? Alignment.center : null,
          decoration: BoxDecoration(color: on ? docPrimary : docSurfaceRaised, borderRadius: BorderRadius.circular(docRadiusPill)),
          child: Text(label, style: TextStyle(color: on ? Colors.white : docTextPrimary, fontWeight: FontWeight.w600, fontSize: 12.5)),
        ),
      );
}

const _kTimesOfDay = ['Morning', 'Afternoon', 'Evening', 'Night', 'Bedtime'];

/// Small dot row showing which of the five times-of-day a medicine's frequency covers — parsed
/// back out of the composed "Morning, Night" string rather than kept as a separate field, since
/// the backend only has one frequency text column to store it in.
Widget medicationTimeDots(String? frequency) {
  final f = frequency ?? '';
  return Row(mainAxisSize: MainAxisSize.min, children: [
    for (final t in _kTimesOfDay)
      Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: f.contains(t) ? docPrimary : docBorder)),
      ),
  ]);
}
