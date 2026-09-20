import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../api_client.dart';
import '../auth_provider.dart';
import '../theme.dart';

/// Writes the patient's after-visit letter. The safe shape of this flow is deliberate:
///  1. the server drafts an English letter from the doctor's OWN visit record (medicines, advice,
///     tests and follow-up are copied verbatim from what was issued — only a short "what we found"
///     paragraph is model-written);
///  2. the doctor edits that English — it is the only text they can actually verify;
///  3. a translation into the patient's language is PREVIEWED, never auto-sent, and any later edit
///     to the English invalidates it, so what the patient receives is always a translation of
///     exactly what the doctor approved (and they see the English original beside it).
class AfterVisitSummaryCard extends StatefulWidget {
  final String appointmentId;
  const AfterVisitSummaryCard({super.key, required this.appointmentId});

  @override
  State<AfterVisitSummaryCard> createState() => _AfterVisitSummaryCardState();
}

class _AfterVisitSummaryCardState extends State<AfterVisitSummaryCard> {
  Map<String, dynamic>? _existing;
  List<String> _languages = const ['English'];
  String _language = 'English';
  bool _loading = true;
  bool _editing = false;
  bool _busy = false;
  String? _translated; // preview of the CURRENT english text in _language; null = none / stale
  final _english = TextEditingController();

  ApiClient get _api => context.read<AuthProvider>().api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _english.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await _api.getAfterVisitSummary(widget.appointmentId);
      if (!mounted) return;
      setState(() {
        _existing = res['summary'] as Map<String, dynamic>?;
        _languages = ((res['languages'] as List?) ?? const ['English']).cast<String>();
        _language = _existing?['language'] as String? ?? res['suggestedLanguage'] as String? ?? 'English';
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _guard(Future<void> Function() fn) async {
    setState(() => _busy = true);
    try {
      await fn();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _draft() => _guard(() async {
        final text = await _api.draftAfterVisitSummary(widget.appointmentId);
        if (!mounted) return;
        setState(() {
          _english.text = text;
          _translated = null;
          _editing = true;
        });
      });

  Future<void> _preview() => _guard(() async {
        final t = await _api.translateAfterVisitSummary(widget.appointmentId, _english.text.trim(), _language);
        if (mounted) setState(() => _translated = t);
      });

  Future<void> _send() => _guard(() async {
        final saved = await _api.sendAfterVisitSummary(
          widget.appointmentId,
          englishText: _english.text.trim(),
          language: _language,
          translatedText: _language == 'English' ? null : _translated,
        );
        if (!mounted) return;
        setState(() {
          _existing = saved;
          _editing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Summary sent to the patient.')));
      });

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    final sentAt = DateTime.tryParse(_existing?['sent_at'] as String? ?? '')?.toLocal();
    final canSend = !_busy && _english.text.trim().isNotEmpty && (_language == 'English' || _translated != null);

    return DocCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.mark_email_read_outlined, size: 15, color: docPrimary),
          const SizedBox(width: 6),
          const Text('AFTER-VISIT SUMMARY FOR THE PATIENT', style: TextStyle(fontSize: 10, color: docMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
        ]),
        const SizedBox(height: 8),
        if (!_editing) ...[
          if (_existing != null)
            Text(
              'Sent${sentAt != null ? ' ${DateFormat('MMM d, h:mm a').format(sentAt)}' : ''} in ${_existing!['language']}. The patient can read it in HealthFolio.',
              style: const TextStyle(fontSize: 12.5, color: docSuccess, fontWeight: FontWeight.w600, height: 1.4),
            )
          else
            const Text('A plain-language letter with their medicines, advice and follow-up, in the language they read best.', style: TextStyle(fontSize: 12.5, color: docMuted, height: 1.4)),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _draft,
              icon: _busy ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.edit_note_rounded, size: 17),
              label: Text(_existing != null ? 'Write a new version' : 'Draft a summary'),
            ),
          ),
        ] else ...[
          const Text('Review and edit — this English text is what you are approving.', style: TextStyle(fontSize: 11.5, color: docMuted)),
          const SizedBox(height: 8),
          TextField(
            controller: _english,
            maxLines: 14,
            minLines: 8,
            style: const TextStyle(fontSize: 12.5, height: 1.45),
            decoration: const InputDecoration(alignLabelWithHint: true),
            // Any edit makes a previewed translation stale — it no longer matches what's approved.
            onChanged: (_) => setState(() => _translated = null),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _language,
            decoration: const InputDecoration(labelText: 'Patient reads'),
            items: [for (final l in _languages) DropdownMenuItem(value: l, child: Text(l))],
            onChanged: (v) => setState(() {
              _language = v ?? _language;
              _translated = null;
            }),
          ),
          if (_language != 'English') ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy || _english.text.trim().isEmpty ? null : _preview,
                icon: _busy ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.translate_rounded, size: 16),
                label: Text(_translated == null ? 'Preview $_language translation' : 'Re-translate'),
              ),
            ),
            if (_translated != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(color: docAccentLight, borderRadius: BorderRadius.circular(docRadiusSm)),
                child: Text(_translated!, style: const TextStyle(fontSize: 12.5, height: 1.45)),
              ),
              const SizedBox(height: 6),
              const Text(
                'Machine translation. You can\'t verify it yourself, so the patient always sees your English original beside it.',
                style: TextStyle(fontSize: 10.5, color: docMuted, fontStyle: FontStyle.italic, height: 1.4),
              ),
            ],
          ],
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: _busy ? null : () => setState(() => _editing = false), child: const Text('Cancel'))),
            const SizedBox(width: 10),
            Expanded(flex: 2, child: ElevatedButton(onPressed: canSend ? _send : null, child: const Text('Send to patient'))),
          ]),
          if (_language != 'English' && _translated == null)
            const Padding(padding: EdgeInsets.only(top: 6), child: Text('Preview the translation to enable sending.', style: TextStyle(fontSize: 10.5, color: docMuted))),
        ],
      ]),
    );
  }
}
