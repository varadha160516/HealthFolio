import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api_client.dart';
import '../../auth_provider.dart';
import '../../theme.dart';
import '../../widgets/glass.dart';
import '../../widgets/section_card.dart';
import '../../widgets/voice_language_button.dart';

class _Msg {
  final String id;
  final String role;
  final String content;
  _Msg({required this.id, required this.role, required this.content});
}

/// Symptom intake agent (Roadmap Section 2.4) — a short clarifying Q&A that turns a free-text
/// description into a structured, dated entry. `entryId` null starts a brand-new entry with the
/// member's first description; otherwise this continues (or, once completed, just displays) an
/// existing one. See server/src/pipeline/symptomIntake.ts for the safety design — this screen
/// only renders whatever the server already decided, it never judges urgency itself.
class SymptomIntakeScreen extends StatefulWidget {
  final String memberId;
  final String? entryId;
  final String? openingMessage; // set only when starting a brand-new entry from the tab's input
  const SymptomIntakeScreen({super.key, required this.memberId, this.entryId, this.openingMessage});

  @override
  State<SymptomIntakeScreen> createState() => _SymptomIntakeScreenState();
}

class _SymptomIntakeScreenState extends State<SymptomIntakeScreen> {
  Map<String, dynamic>? _entry;
  List<_Msg> _messages = [];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _busy = false;
  String? _error;
  String? _translatedFrom;

  ApiClient get _api => context.read<AuthProvider>().api;

  @override
  void initState() {
    super.initState();
    if (widget.entryId != null) {
      _loadExisting();
    } else if (widget.openingMessage != null) {
      _send(widget.openingMessage);
    }
  }

  Future<void> _loadExisting() async {
    setState(() => _busy = true);
    try {
      final e = await _api.getSymptomEntry(widget.entryId!);
      _applyEntry(e);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load this entry.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _applyEntry(Map<String, dynamic> e) {
    if (!mounted) return;
    setState(() {
      _entry = e;
      _messages = (e['messages'] as List<dynamic>).cast<Map<String, dynamic>>().map((m) => _Msg(id: m['id'], role: m['role'], content: m['content'])).toList();
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  bool get _completed => _entry != null && _entry!['status'] == 'completed';
  bool get _urgent => _entry != null && _entry!['urgent_flag'] == 1;

  Future<void> _send([String? text]) async {
    final message = (text ?? _input.text).trim();
    if (message.isEmpty || _busy || _completed) return;
    setState(() {
      _busy = true;
      _error = null;
      _input.clear();
    });
    try {
      final result = _entry == null ? await _api.startSymptomEntry(widget.memberId, message) : await _api.continueSymptomEntry(_entry!['id'] as String, message);
      _applyEntry(result);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not send that — please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      appBar: const GlassAppBar(title: Text('Log a symptom')),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: careloopSurface, borderRadius: BorderRadius.circular(careloopRadiusMd), border: careloopCardBorder, boxShadow: careloopCardShadow),
            child: const Text(
              'A few short questions to log this clearly — never a diagnosis. If anything feels urgent, contact a doctor or emergency services right away.',
              style: TextStyle(color: careloopMuted, fontSize: 12, height: 1.3),
            ),
          ),
          if (_urgent)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: InfoBanner('This was flagged as possibly urgent — please contact a doctor or emergency services.'),
            ),
          Expanded(
            child: _messages.isEmpty && _busy
                ? const LoadingCenter()
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) => _Bubble(msg: _messages[i]),
                  ),
          ),
          if (_completed && _entry != null) _SummaryCard(entry: _entry!),
          if (_busy && _messages.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(left: 20, bottom: 6),
              child: Row(mainAxisAlignment: MainAxisAlignment.start, children: [
                SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: careloopPrimary)),
                SizedBox(width: 8),
                Text('…', style: TextStyle(color: careloopMuted, fontSize: 12.5)),
              ]),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_error!, style: const TextStyle(color: careloopDanger, fontSize: 12.5)),
            ),
          if (!_completed)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_translatedFrom != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('Translated from $_translatedFrom', style: const TextStyle(color: careloopMutedDim, fontSize: 10.5, fontStyle: FontStyle.italic)),
                      ),
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      VoiceLanguageButton(
                        onResult: (text, {translatedFrom}) => setState(() {
                          _input.text = text;
                          _translatedFrom = translatedFrom;
                        }),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      decoration: BoxDecoration(color: careloopSurface, borderRadius: BorderRadius.circular(careloopRadiusLg), border: careloopCardBorder, boxShadow: careloopCardShadow),
                      child: Row(children: [
                        Expanded(
                          child: TextField(
                            controller: _input,
                            minLines: 1,
                            maxLines: 4,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(hintText: _entry == null ? "What's going on?" : 'Your answer…', isDense: true),
                            onSubmitted: (_) => _send(),
                            onChanged: (_) => setState(() => _translatedFrom = null),
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton.filled(
                          icon: const Icon(Icons.arrow_upward_rounded),
                          onPressed: _busy ? null : () => _send(),
                          style: IconButton.styleFrom(backgroundColor: careloopAccent, disabledBackgroundColor: careloopAccent.withValues(alpha: 0.35)),
                        ),
                      ]),
                    ),
                  ],
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
            ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final _Msg msg;
  const _Bubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final isUser = msg.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isUser ? careloopPrimary : careloopSurface,
            borderRadius: BorderRadius.circular(careloopRadiusMd),
            border: isUser ? null : careloopCardBorder,
          ),
          child: Text(msg.content, style: TextStyle(color: isUser ? Colors.white : careloopTextPrimary, fontSize: careloopTypeBody, height: 1.4)),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final Map<String, dynamic> entry;
  const _SummaryCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final fields = <String, String?>{
      'Onset': entry['onset'] as String?,
      'Severity': entry['severity'] as String?,
      'Duration': entry['duration'] as String?,
      'Associated factors': entry['associated_factors'] as String?,
    }..removeWhere((_, v) => v == null || v.trim().isEmpty);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: SectionCard(
        title: 'Logged',
        icon: Icons.fact_check_rounded,
        child: fields.isEmpty
            ? const Text('Saved to this member\'s records.', style: TextStyle(color: careloopMuted, fontSize: 13))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final e in fields.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: RichText(
                        text: TextSpan(children: [
                          TextSpan(text: '${e.key}: ', style: const TextStyle(color: careloopMuted, fontSize: 13, fontWeight: FontWeight.w600)),
                          TextSpan(text: e.value, style: const TextStyle(color: careloopTextPrimary, fontSize: 13)),
                        ]),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
