import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../auth_provider.dart';
import '../theme.dart';

const _kLanguages = <(String, String, String)>[
  // (locale id, display name, short label for the "Translated from X" caption)
  ('en-US', 'English', 'English'),
  ('hi-IN', 'Hindi', 'Hindi'),
  ('ta-IN', 'Tamil', 'Tamil'),
  ('te-IN', 'Telugu', 'Telugu'),
  ('bn-IN', 'Bengali', 'Bengali'),
  ('kn-IN', 'Kannada', 'Kannada'),
  ('mr-IN', 'Marathi', 'Marathi'),
];

/// Mic-to-text using the same speech_to_text package already wired up for AI Chat, plus a
/// language picker and a real translate-to-English step (POST /translate, Claude-backed) when a
/// non-English language is selected — this second part is genuinely new, speech_to_text only
/// recognizes in the configured locale, it doesn't translate.
class VoiceLanguageButton extends StatefulWidget {
  /// Called once listening stops with a non-empty result. [translatedFrom] is the source
  /// language's display name when a translation happened, null when it was already English.
  final void Function(String text, {String? translatedFrom}) onResult;
  final ValueChanged<bool>? onListeningChanged;
  const VoiceLanguageButton({super.key, required this.onResult, this.onListeningChanged});

  @override
  State<VoiceLanguageButton> createState() => _VoiceLanguageButtonState();
}

class _VoiceLanguageButtonState extends State<VoiceLanguageButton> {
  final _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _listening = false;
  int _languageIndex = 0;
  bool _translating = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _speechAvailable = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') _setListening(false);
      },
      onError: (_) => _setListening(false),
    );
    if (mounted) setState(() {});
  }

  void _setListening(bool value) {
    if (!mounted) return;
    setState(() => _listening = value);
    widget.onListeningChanged?.call(value);
  }

  Future<void> _toggle() async {
    if (!_speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Voice input is not available on this device.')));
      return;
    }
    if (_listening) {
      await _speech.stop();
      _setListening(false);
      return;
    }
    _setListening(true);
    final (localeId, languageName, _) = _kLanguages[_languageIndex];
    String recognized = '';
    await _speech.listen(
      onResult: (SpeechRecognitionResult result) {
        recognized = result.recognizedWords;
        if (result.finalResult) _finish(recognized, languageName);
      },
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.confirmation,
        partialResults: true,
        pauseFor: const Duration(seconds: 3),
        listenFor: const Duration(seconds: 30),
        localeId: localeId,
      ),
    );
  }

  Future<void> _finish(String recognized, String languageName) async {
    _setListening(false);
    if (recognized.trim().isEmpty) return;
    if (languageName == 'English') {
      widget.onResult(recognized.trim());
      return;
    }
    setState(() => _translating = true);
    try {
      final api = context.read<AuthProvider>().api;
      final translated = await api.translateText(recognized.trim(), languageName);
      widget.onResult(translated, translatedFrom: languageName);
    } catch (_) {
      // Translation service unavailable — still hand back the raw recognized text rather than
      // losing what was said.
      widget.onResult(recognized.trim());
    } finally {
      if (mounted) setState(() => _translating = false);
    }
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (_, languageName, _) = _kLanguages[_languageIndex];
    return Row(mainAxisSize: MainAxisSize.min, children: [
      PopupMenuButton<int>(
        tooltip: 'Speak in…',
        initialValue: _languageIndex,
        onSelected: (i) => setState(() => _languageIndex = i),
        itemBuilder: (_) => [for (var i = 0; i < _kLanguages.length; i++) PopupMenuItem(value: i, child: Text(_kLanguages[i].$2))],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(color: careloopSurfaceRaised, borderRadius: BorderRadius.circular(999)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(languageName, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: careloopAccent)),
            const Icon(Icons.expand_more_rounded, size: 13, color: careloopAccent),
          ]),
        ),
      ),
      const SizedBox(width: 6),
      _translating
          ? const Padding(padding: EdgeInsets.all(6), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
          : IconButton(
              tooltip: _listening ? 'Stop listening' : 'Speak',
              icon: Icon(_listening ? Icons.mic_rounded : Icons.mic_none_rounded, color: _listening ? careloopPrimary : careloopMuted),
              onPressed: _toggle,
            ),
    ]);
  }
}
