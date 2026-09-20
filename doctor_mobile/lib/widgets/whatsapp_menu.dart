import 'package:flutter/material.dart';
import '../api_client.dart';
import '../services/external_link.dart';
import '../theme.dart';

/// The WhatsApp nudges that make sense for a visit right now — same rules as the server's
/// buildWhatsAppLink (server/src/whatsapp.ts), which is what actually enforces them. Every one of
/// these is a short prompt to open the app or a place in the line; none carries anything clinical.
List<(String, String)> whatsappOptions({required String status, required bool video, required bool hasToken, bool hasSummary = false}) => [
      if (status == 'scheduled') ('reminder', 'Appointment reminder'),
      if (!video && status == 'checked_in' && hasToken) ('token', 'Token number and wait'),
      if (video && status != 'completed' && status != 'cancelled') ('video_ready', 'Doctor is ready — join video'),
      if (hasSummary) ('summary_ready', 'Visit summary is ready'),
    ];

const _whatsappGreen = Color(0xFF25D366);

/// Only shown for a patient who agreed to WhatsApp updates (the server says so with
/// `whatsapp_available`; it never sends the number to the client — the link it returns is the only
/// place it appears, and that opens straight into WhatsApp).
class WhatsAppMenuButton extends StatelessWidget {
  final List<(String, String)> options;
  final Future<String> Function(String kind) getLink;
  const WhatsAppMenuButton({super.key, required this.options, required this.getLink});

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      tooltip: 'Message on WhatsApp',
      icon: const Icon(Icons.chat_rounded, size: 20, color: _whatsappGreen),
      onSelected: (kind) async {
        final messenger = ScaffoldMessenger.of(context);
        try {
          final url = await getLink(kind);
          if (!context.mounted) return;
          await openExternalLink(context, url, failure: "Couldn't open WhatsApp on this phone.");
        } on ApiException catch (e) {
          messenger.showSnackBar(SnackBar(content: Text(e.message)));
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem<String>(
          enabled: false,
          height: 30,
          child: Text('MESSAGE ON WHATSAPP', style: TextStyle(fontSize: 10, color: docMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
        ),
        for (final (kind, label) in options) PopupMenuItem<String>(value: kind, child: Text(label, style: const TextStyle(fontSize: 13))),
      ],
    );
  }
}
