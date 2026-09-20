import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../auth_provider.dart';
import '../../theme.dart';
import '../../widgets/section_card.dart';

/// The letter a doctor sent after a visit. When it was sent in another language, that version is
/// shown first with the doctor's English original one tap away — the translation is machine-made,
/// so the source the doctor actually reviewed is always reachable.
class AfterVisitSummaryScreen extends StatefulWidget {
  final String appointmentId;
  const AfterVisitSummaryScreen({super.key, required this.appointmentId});

  @override
  State<AfterVisitSummaryScreen> createState() => _AfterVisitSummaryScreenState();
}

class _AfterVisitSummaryScreenState extends State<AfterVisitSummaryScreen> {
  Map<String, dynamic>? _summary;
  String? _error;
  bool _showEnglish = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await context.read<AuthProvider>().api.getPatientSummary(widget.appointmentId);
      if (mounted) setState(() => _summary = s);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: careloopBg,
      appBar: AppBar(title: const Text('Visit summary')),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: const TextStyle(color: careloopMuted), textAlign: TextAlign.center)))
          : _summary == null
              ? const LoadingCenter()
              : _content(_summary!),
    );
  }

  Widget _content(Map<String, dynamic> s) {
    final language = s['language'] as String? ?? 'English';
    final translated = s['translated_text'] as String?;
    final translatedAvailable = language != 'English' && translated != null && translated.isNotEmpty;
    final showing = translatedAvailable && !_showEnglish ? translated : s['english_text'] as String;
    final sentAt = DateTime.tryParse(s['sent_at'] as String? ?? '')?.toLocal();
    final visitAt = DateTime.tryParse(s['appointment_datetime'] as String? ?? '');

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Text(s['provider_name'] as String? ?? 'Your doctor', style: careloopSectionHeading().copyWith(fontSize: 18)),
        Text(
          [
            if (visitAt != null) 'Visit on ${DateFormat('MMM d, yyyy').format(visitAt.toLocal())}',
            if (sentAt != null) 'sent ${DateFormat('MMM d').format(sentAt)}',
          ].join(' · '),
          style: const TextStyle(color: careloopMuted, fontSize: 11.5),
        ),
        const SizedBox(height: 14),
        if (translatedAvailable) ...[
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: careloopSurface, border: careloopCardBorder, borderRadius: BorderRadius.circular(999)),
            child: Row(children: [
              for (final (label, english) in [(language, false), ('English', true)])
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => setState(() => _showEnglish = english),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(color: _showEnglish == english ? careloopAccentLight : Colors.transparent, borderRadius: BorderRadius.circular(999)),
                      child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _showEnglish == english ? careloopAccent : careloopMuted)),
                    ),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 12),
        ],
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: careloopSurface, borderRadius: BorderRadius.circular(careloopRadiusMd), border: careloopCardBorder, boxShadow: careloopCardShadow),
          child: SelectableText(showing, style: const TextStyle(fontSize: 14, height: 1.55, color: careloopTextPrimary)),
        ),
        if (translatedAvailable && !_showEnglish) ...[
          const SizedBox(height: 10),
          Text(
            'This $language version was translated automatically from your doctor\'s English letter. If anything looks unclear, check the English version or ask the clinic.',
            style: const TextStyle(color: careloopMuted, fontSize: 11, fontStyle: FontStyle.italic, height: 1.4),
          ),
        ],
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: careloopSurfaceRaised, borderRadius: BorderRadius.circular(careloopRadiusMd)),
          child: const Text(
            'This summary is from your doctor\'s own notes for this visit. It is not a substitute for talking to them — contact the clinic if you have questions or your symptoms change.',
            style: TextStyle(color: careloopMuted, fontSize: 11, height: 1.4, fontStyle: FontStyle.italic),
          ),
        ),
      ],
    );
  }
}
