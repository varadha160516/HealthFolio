import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import '../../../auth_provider.dart';
import '../../../theme.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/section_card.dart';

class _ChatMsg {
  final String id;
  final String role; // 'user' | 'assistant'
  final String content;
  _ChatMsg({required this.id, required this.role, required this.content});
}

const _suggestedQuestions = [
  'What does my last report say?',
  'Anything out of range I should know about?',
  'Any diet or exercise tips for me?',
];

/// AI Health Assistant — answers questions about this member's own uploaded lab reports,
/// consultations and prescriptions (never invented data — see server/pipeline/chatAssistant.ts),
/// and can suggest general home food/exercise ideas for out-of-range results. Text and voice in
/// both directions: speech_to_text fills the input box (on-device, no cloud key), flutter_tts
/// reads assistant replies aloud (on-device too).
class AiChatTab extends StatefulWidget {
  final String memberId;
  const AiChatTab({super.key, required this.memberId});

  @override
  State<AiChatTab> createState() => _AiChatTabState();
}

class _AiChatTabState extends State<AiChatTab> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _speech = stt.SpeechToText();
  final _tts = FlutterTts();

  List<_ChatMsg>? _messages;
  bool _sending = false;
  bool _speechAvailable = false;
  bool _listening = false;
  bool _autoSpeak = true;
  String? _speakingId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _initVoice();
  }

  Future<void> _initVoice() async {
    _speechAvailable = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') setState(() => _listening = false);
      },
      onError: (_) => setState(() => _listening = false),
    );
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.48);
    await _tts.setPitch(1.0);
    _tts.setCompletionHandler(() => setState(() => _speakingId = null));
    _tts.setCancelHandler(() => setState(() => _speakingId = null));
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().api;
    try {
      final history = await api.getChatHistory(widget.memberId);
      if (!mounted) return;
      setState(() => _messages = history
          .cast<Map<String, dynamic>>()
          .map((m) => _ChatMsg(id: m['id'], role: m['role'], content: m['content']))
          .toList());
      _scrollToBottom();
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load the conversation.');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  Future<void> _send([String? text]) async {
    final message = (text ?? _input.text).trim();
    if (message.isEmpty || _sending) return;
    final api = context.read<AuthProvider>().api;
    final tempId = 'pending-${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      _messages = [...?_messages, _ChatMsg(id: tempId, role: 'user', content: message)];
      _input.clear();
      _sending = true;
      _error = null;
    });
    _scrollToBottom();
    try {
      final resp = await api.sendChatMessage(widget.memberId, message);
      final assistant = resp['assistantMessage'] as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _messages = [..._messages!, _ChatMsg(id: assistant['id'], role: 'assistant', content: assistant['content'])];
        _sending = false;
      });
      _scrollToBottom();
      if (_autoSpeak) _speak(assistant['id'], assistant['content']);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages = _messages!.where((m) => m.id != tempId).toList();
        _input.text = message;
        _sending = false;
        _error = 'Could not reach the health assistant — please try again.';
      });
    }
  }

  Future<void> _toggleListening() async {
    if (!_speechAvailable) {
      setState(() => _error = 'Voice input is not available on this device.');
      return;
    }
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }
    setState(() {
      _listening = true;
      _error = null;
    });
    await _speech.listen(
      onResult: (SpeechRecognitionResult result) => setState(() => _input.text = result.recognizedWords),
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.confirmation,
        partialResults: true,
        pauseFor: const Duration(seconds: 3),
        listenFor: const Duration(seconds: 30),
      ),
    );
  }

  Future<void> _speak(String id, String text) async {
    if (_speakingId == id) {
      await _tts.stop();
      setState(() => _speakingId = null);
      return;
    }
    setState(() => _speakingId = id);
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> _clearConversation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Start a new conversation?'),
        content: const Text('This clears the chat history for this member. It cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final api = context.read<AuthProvider>().api;
    await api.clearChatHistory(widget.memberId);
    if (mounted) setState(() => _messages = []);
  }

  @override
  void dispose() {
    _speech.stop();
    _tts.stop();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_messages == null) return const LoadingCenter();

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: careloopSurface, borderRadius: BorderRadius.circular(careloopRadiusMd), border: careloopCardBorder, boxShadow: careloopCardShadow),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(
              child: Text(
                'General wellness guidance based on your records — not a diagnosis. Always consult your doctor for anything serious.',
                style: const TextStyle(color: careloopMuted, fontSize: 12, height: 1.3),
              ),
            ),
            IconButton(
              tooltip: _autoSpeak ? 'Auto-speak replies: on' : 'Auto-speak replies: off',
              icon: Icon(_autoSpeak ? Icons.volume_up_rounded : Icons.volume_off_rounded, color: careloopMuted, size: 20),
              onPressed: () => setState(() => _autoSpeak = !_autoSpeak),
            ),
            IconButton(
              tooltip: 'New conversation',
              icon: const Icon(Icons.refresh_rounded, color: careloopMuted, size: 20),
              onPressed: _messages!.isEmpty ? null : _clearConversation,
            ),
          ]),
        ),
        Expanded(
          child: _messages!.isEmpty
              ? _EmptyState(onPick: (q) => _send(q))
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  itemCount: _messages!.length,
                  itemBuilder: (_, i) {
                    final m = _messages![i];
                    return _Bubble(
                      msg: m,
                      speaking: _speakingId == m.id,
                      onSpeak: m.role == 'assistant' ? () => _speak(m.id, m.content) : null,
                    );
                  },
                ),
        ),
        if (_sending)
          const Padding(
            padding: EdgeInsets.only(left: 20, bottom: 6),
            child: Row(mainAxisAlignment: MainAxisAlignment.start, children: [
              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: careloopPrimary)),
              SizedBox(width: 8),
              Text('Thinking…', style: TextStyle(color: careloopMuted, fontSize: 12.5)),
            ]),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_error!, style: const TextStyle(color: careloopDanger, fontSize: 12.5)),
          ),
        SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            decoration: BoxDecoration(color: careloopSurface, borderRadius: BorderRadius.circular(careloopRadiusLg), border: careloopCardBorder, boxShadow: careloopCardShadow),
            child: Row(children: [
              IconButton(
                tooltip: _listening ? 'Stop listening' : 'Ask by voice',
                icon: Icon(_listening ? Icons.mic_rounded : Icons.mic_none_rounded, color: _listening ? careloopPrimary : careloopMuted),
                onPressed: _toggleListening,
              ),
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(hintText: _listening ? 'Listening…' : 'Ask about a report, result or symptom…', isDense: true),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                icon: const Icon(Icons.arrow_upward_rounded),
                onPressed: _sending ? null : () => _send(),
                style: IconButton.styleFrom(backgroundColor: careloopAccent, disabledBackgroundColor: careloopAccent.withValues(alpha: 0.35)),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  final _ChatMsg msg;
  final bool speaking;
  final VoidCallback? onSpeak;
  const _Bubble({required this.msg, this.speaking = false, this.onSpeak});

  @override
  Widget build(BuildContext context) {
    final isUser = msg.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        child: Column(
          crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 5),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? careloopPrimary : careloopSurface,
                borderRadius: BorderRadius.circular(careloopRadiusMd),
                border: isUser ? null : careloopCardBorder,
              ),
              child: Text(msg.content, style: TextStyle(color: isUser ? Colors.white : careloopTextPrimary, fontSize: careloopTypeBody, height: 1.4)),
            ),
            if (onSpeak != null)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: InkWell(
                  onTap: onSpeak,
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(speaking ? Icons.stop_circle_rounded : Icons.volume_up_rounded, size: 16, color: careloopMuted),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final void Function(String) onPick;
  const _EmptyState({required this.onPick});

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.health_and_safety_rounded,
      message: 'Ask about a recent report, result, or consultation.',
      action: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: _suggestedQuestions
            .map((q) => ActionChip(
                  label: Text(q, style: const TextStyle(fontSize: 12.5)),
                  onPressed: () => onPick(q),
                ))
            .toList(),
      ),
    );
  }
}
