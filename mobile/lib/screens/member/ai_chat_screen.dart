import 'package:flutter/material.dart';
import 'tabs/ai_chat_tab.dart';
import '../../widgets/glass.dart';

/// "Ask me" as a standalone route rather than a tab — reachable via a floating action button from
/// every screen in a member's profile (and, via a member picker, from the Family dashboard too),
/// so asking a question never requires first navigating to a specific tab.
class AiChatScreen extends StatelessWidget {
  final Map<String, dynamic> member;
  const AiChatScreen({super.key, required this.member});

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      appBar: GlassAppBar(title: Text('Ask me about ${member['name'] ?? 'their health'}')),
      body: AiChatTab(memberId: member['id'] as String),
    );
  }
}
