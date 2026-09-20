import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../api_client.dart';
import '../../auth_provider.dart';
import '../../theme.dart';
import '../clinic_screen.dart';
import 'walk_in_sheet.dart';

/// The front desk's whole app: the clinic's day across every doctor, and the few actions that move
/// the queue (check in, cancel, walk-in). It only ever shows who is here, when, and where they are in
/// line — no reasons for visit and nothing clinical (the server doesn't send any). Reception can't
/// open a consultation or request access to anyone's records; that stays the doctor's.
class FrontDeskShell extends StatefulWidget {
  const FrontDeskShell({super.key});
  @override
  State<FrontDeskShell> createState() => _FrontDeskShellState();
}

class _FrontDeskShellState extends State<FrontDeskShell> {
  Map<String, dynamic>? _queue;
  String? _error;
  DateTime _date = DateTime.now();
  Timer? _poll;
  final Set<String> _busy = {};

  static String _fmt(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  bool get _isToday => _fmt(_date) == _fmt(DateTime.now());
  ApiClient get _api => context.read<AuthProvider>().api;

  @override
  void initState() {
    super.initState();
    _load();
    // The desk is a live board: a doctor starting a consultation or a patient arriving elsewhere
    // should show up without anyone pulling to refresh.
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final requested = _fmt(_date);
    try {
      final q = await _api.getFrontDeskQueue(requested);
      // A poll that was in flight when the date changed must not overwrite the new day.
      if (mounted && requested == _fmt(_date)) {
        setState(() {
          _queue = q;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && !silent) setState(() => _error = '$e');
    }
  }

  void _setDate(DateTime d) {
    setState(() {
      _date = d;
      _queue = null;
    });
    _load();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime.now().subtract(const Duration(days: 30)), lastDate: DateTime.now().add(const Duration(days: 90)));
    if (picked != null) _setDate(picked);
  }

  Future<void> _checkIn(String id) async {
    setState(() => _busy.add(id));
    try {
      final r = await _api.frontDeskCheckIn(id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Checked in — token ${r['token']}')));
      await _load(silent: true);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _cancel(Map<String, dynamic> a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel this appointment?'),
        content: Text('${(a['patient'] as Map)['name']}\'s visit will be cancelled and the doctor will be told.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Keep it')),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: docDanger), onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Cancel appointment')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy.add(a['id'] as String));
    try {
      await _api.frontDeskCancel(a['id'] as String);
      await _load(silent: true);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy.remove(a['id'] as String));
    }
  }

  Future<void> _openWalkIn() async {
    final doctors = ((_queue?['doctors'] as List?) ?? const []).cast<Map<String, dynamic>>();
    if (doctors.isEmpty) return;
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => WalkInSheet(doctors: [for (final d in doctors) (d['id'] as String, d['name'] as String)]),
    );
    if (created == true) _load(silent: true);
  }

  // Who to look at first: people with the doctor, then the waiting line (by token), then the rest of
  // the day in booking order, and finished/closed visits last.
  static int _rank(Map<String, dynamic> a) => switch (_bucket(a['status'] as String)) {
        'in_progress' => 0,
        'waiting' => 1,
        'scheduled' => 2,
        'completed' => 3,
        _ => 4,
      };

  static String _bucket(String status) {
    if (status == 'scheduled') return 'scheduled';
    if (status == 'checked_in' || status == 'consent_requested') return 'waiting';
    if (status == 'consent_granted' || status == 'in_consultation') return 'in_progress';
    if (status == 'completed') return 'completed';
    return 'closed';
  }

  List<Map<String, dynamic>> _sorted(List<dynamic> appts) {
    final list = appts.cast<Map<String, dynamic>>().toList();
    list.sort((a, b) {
      final r = _rank(a).compareTo(_rank(b));
      if (r != 0) return r;
      if (_bucket(a['status'] as String) == 'waiting') return ((a['token_number'] as num?) ?? 0).compareTo((b['token_number'] as num?) ?? 0);
      return (a['datetime'] as String).compareTo(b['datetime'] as String);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final clinicName = (_queue?['clinic'] as Map?)?['name'] as String?;
    final doctors = ((_queue?['doctors'] as List?) ?? const []).cast<Map<String, dynamic>>();
    int total(String key) => doctors.fold(0, (sum, d) => sum + ((d['counts'] as Map)[key] as int));

    return DocGradientScaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Front desk', style: docSectionHeading().copyWith(fontSize: 17)),
          if (clinicName != null) Text(clinicName, style: const TextStyle(fontSize: 11, color: docMuted, fontWeight: FontWeight.w500)),
        ]),
        actions: [
          // Front desk is the only role allowed to edit the clinic's own details (PATCH /clinics/me),
          // and this screen used to be reachable from the doctor shell's More tab they no longer get.
          IconButton(
            icon: const Icon(Icons.local_hospital_rounded),
            tooltip: 'Clinic details',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ClinicScreen())),
          ),
          IconButton(icon: const Icon(Icons.logout_rounded), tooltip: 'Log out', onPressed: () => context.read<AuthProvider>().logout()),
        ],
      ),
      floatingActionButton: doctors.isEmpty
          ? null
          : FloatingActionButton.extended(onPressed: _openWalkIn, icon: const Icon(Icons.person_add_alt_1_rounded), label: const Text('Walk-in')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, docFabClearance),
          children: [
            Row(children: [
              _dateChip('Today', _isToday, () => _setDate(DateTime.now())),
              const SizedBox(width: 8),
              _dateChip('Tomorrow', _fmt(_date) == _fmt(DateTime.now().add(const Duration(days: 1))), () => _setDate(DateTime.now().add(const Duration(days: 1)))),
              const SizedBox(width: 8),
              InkWell(
                borderRadius: BorderRadius.circular(docRadiusPill),
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(color: docSurface, borderRadius: BorderRadius.circular(docRadiusPill), border: Border.all(color: docBorder)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.calendar_month_rounded, size: 14, color: docMuted),
                    const SizedBox(width: 5),
                    Text(DateFormat('EEE, MMM d').format(_date), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: docDangerBg, borderRadius: BorderRadius.circular(docRadiusMd)),
                child: Text(_error!, style: const TextStyle(color: docDanger, fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
            if (_queue == null && _error == null)
              const Padding(padding: EdgeInsets.only(top: 60), child: LoadingCenter())
            else if (doctors.isEmpty && _queue != null)
              const EmptyState(icon: Icons.medical_services_outlined, message: 'No doctors are attached to this clinic yet.')
            else ...[
              Row(children: [
                _summary('Waiting', total('waiting'), docWarning),
                _summary('With doctor', total('in_progress'), docSuccess),
                _summary('Upcoming', total('scheduled'), docAccent),
                _summary('Done', total('completed'), docMuted),
              ]),
              const SizedBox(height: 14),
              for (final d in doctors) _lane(d),
            ],
          ],
        ),
      ),
    );
  }

  Widget _dateChip(String label, bool selected, VoidCallback onTap) => InkWell(
        borderRadius: BorderRadius.circular(docRadiusPill),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(color: selected ? docPrimary : docSurface, borderRadius: BorderRadius.circular(docRadiusPill), border: selected ? null : Border.all(color: docBorder)),
          child: Text(label, style: TextStyle(color: selected ? Colors.white : docTextPrimary, fontWeight: FontWeight.w600, fontSize: 12.5)),
        ),
      );

  Widget _summary(String label, int n, Color color) => Expanded(
        child: Column(children: [
          Text('$n', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
          Text(label, style: const TextStyle(fontSize: 10.5, color: docMuted, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _lane(Map<String, dynamic> d) {
    final appts = _sorted(d['appointments'] as List);
    final counts = d['counts'] as Map;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DocCard(
        padding: const EdgeInsets.all(13),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.medical_services_rounded, size: 15, color: docAccentDark),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                '${d['name']}${(d['specialty'] as String?)?.isNotEmpty == true ? ' · ${d['specialty']}' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
            Text('${counts['waiting']} waiting', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: (counts['waiting'] as int) > 0 ? docWarning : docMutedDim)),
          ]),
          const SizedBox(height: 8),
          if (appts.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No appointments this day.', style: TextStyle(fontSize: 12, color: docMuted)))
          else
            for (var i = 0; i < appts.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              _row(appts[i]),
            ],
        ]),
      ),
    );
  }

  Widget _row(Map<String, dynamic> a) {
    final patient = a['patient'] as Map<String, dynamic>;
    final status = a['status'] as String;
    final time = DateTime.tryParse(a['datetime'] as String? ?? '');
    final token = a['token_number'] as int?;
    final age = patient['age'];
    final sex = (patient['sex'] as String?) ?? '';
    final busy = _busy.contains(a['id']);
    final done = _bucket(status) == 'completed' || _bucket(status) == 'closed';

    return Opacity(
      opacity: done ? 0.55 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: token != null ? docAccentLight : docSurfaceRaised, borderRadius: BorderRadius.circular(11)),
            child: token != null
                ? Text('$token', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: docAccentDark))
                : Text(time != null ? DateFormat('h:mm').format(time) : '—', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: docMuted)),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${patient['name']}${age != null ? ' · $age${sex.isEmpty ? '' : sex[0].toUpperCase()}' : ''}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
              Text(
                [
                  if (time != null) DateFormat('h:mm a').format(time),
                  if (a['is_walk_in'] == true) 'Walk-in',
                  if (a['is_follow_up'] == true) 'Follow-up',
                ].join(' · '),
                style: const TextStyle(fontSize: 11, color: docMuted),
              ),
            ]),
          ),
          if (status == 'scheduled') ...[
            if (busy)
              const Padding(padding: EdgeInsets.symmetric(horizontal: 14), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
            else ...[
              TextButton(onPressed: () => _checkIn(a['id'] as String), child: const Text('Check in')),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, size: 18, color: docMuted),
                onSelected: (v) {
                  if (v == 'cancel') _cancel(a);
                },
                itemBuilder: (_) => const [PopupMenuItem(value: 'cancel', child: Text('Cancel appointment'))],
              ),
            ],
          ] else
            StatusPill.forAppointment(status),
        ]),
      ),
    );
  }
}
