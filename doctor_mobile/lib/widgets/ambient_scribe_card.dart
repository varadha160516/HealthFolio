import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../theme.dart';

/// Ambient consultation scribe — continuous on-device speech-to-text (speech_to_text) while the
/// doctor talks through the visit, auto-restarted across the OS recognizer's own session limits
/// so it covers a whole consultation, not just one utterance. The transcript stays visible the
/// whole time (never a black box), and "Fill notes" only runs when the doctor explicitly taps it
/// — nothing is sent to the server, and nothing is saved to the record, until they choose to.
class AmbientScribeCard extends StatefulWidget {
  /// Called with the final transcript when the doctor taps "Fill notes". The parent owns calling
  /// the structuring API and merging the result into its own form state.
  final Future<void> Function(String transcript) onFillNotes;
  const AmbientScribeCard({super.key, required this.onFillNotes});

  @override
  State<AmbientScribeCard> createState() => _AmbientScribeCardState();
}

class _AmbientScribeCardState extends State<AmbientScribeCard> {
  final _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _initializing = true;
  bool _recording = false;
  bool _filling = false;
  String _transcript = '';
  String _partial = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final available = await _speech.initialize(onStatus: _onStatus, onError: (_) {});
    if (mounted) {
      setState(() {
        _speechAvailable = available;
        _initializing = false;
      });
    }
  }

  // The OS speech recognizer ends a session on its own after a pause or a max duration — while
  // the doctor is still recording, immediately start a new session so the transcript keeps
  // growing across the whole consultation instead of cutting off after ~a minute.
  void _onStatus(String status) {
    if ((status == 'done' || status == 'notListening') && _recording) _listenChunk();
  }

  Future<void> _start() async {
    if (!_speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Voice input is not available on this device.')));
      return;
    }
    setState(() {
      _recording = true;
      _transcript = '';
      _partial = '';
    });
    await _listenChunk();
  }

  Future<void> _listenChunk() async {
    await _speech.listen(
      onResult: (SpeechRecognitionResult result) {
        if (!mounted) return;
        if (result.finalResult) {
          setState(() {
            _transcript = [_transcript, result.recognizedWords].where((s) => s.isNotEmpty).join(' ');
            _partial = '';
          });
        } else {
          setState(() => _partial = result.recognizedWords);
        }
      },
      listenOptions: stt.SpeechListenOptions(listenMode: stt.ListenMode.dictation, partialResults: true, pauseFor: const Duration(seconds: 8), listenFor: const Duration(seconds: 55)),
    );
  }

  Future<void> _stop() async {
    setState(() => _recording = false);
    await _speech.stop();
  }

  Future<void> _fillNotes() async {
    final transcript = _transcript.trim();
    if (transcript.isEmpty) return;
    setState(() => _filling = true);
    try {
      await widget.onFillNotes(transcript);
    } finally {
      if (mounted) setState(() => _filling = false);
    }
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasTranscript = _transcript.trim().isNotEmpty || _partial.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(color: docAccentLight, borderRadius: BorderRadius.circular(docRadiusMd)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.mic_rounded, size: 15, color: _recording ? docDanger : docAccentDark),
          const SizedBox(width: 6),
          const Text('AMBIENT SCRIBE', style: TextStyle(fontSize: 10, color: docAccentDark, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
          const Spacer(),
          if (_recording) Container(width: 7, height: 7, decoration: const BoxDecoration(color: docDanger, shape: BoxShape.circle)),
        ]),
        const SizedBox(height: 8),
        Text(
          _recording ? 'Listening — talk through the visit as usual.' : 'Talk through the visit and this will draft your notes below for you to review.',
          style: const TextStyle(fontSize: 12.5, height: 1.4, color: docTextPrimary),
        ),
        if (hasTranscript) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 110),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: docSurface, borderRadius: BorderRadius.circular(docRadiusSm)),
            child: SingleChildScrollView(
              reverse: true,
              child: Text(
                [_transcript, _partial].where((s) => s.isNotEmpty).join(' '),
                style: const TextStyle(fontSize: 11.5, color: docTextPrimary, height: 1.4),
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _initializing ? null : (_recording ? _stop : _start),
              icon: Icon(_recording ? Icons.stop_circle_outlined : Icons.mic_none_rounded, size: 16),
              label: Text(_recording ? 'Stop' : (hasTranscript ? 'Resume' : 'Start recording')),
            ),
          ),
          if (!_recording && hasTranscript) ...[
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: _filling ? null : _fillNotes,
                child: _filling
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Fill notes from this'),
              ),
            ),
          ],
        ]),
      ]),
    );
  }
}
