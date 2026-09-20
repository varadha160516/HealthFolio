import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [url] in whatever app handles it — for a video consultation that's the Jitsi Meet app, or
/// the browser if that's all the phone has. Returns false and says so when nothing could open it.
Future<bool> openExternalLink(BuildContext context, String url, {String failure = "Couldn't open that on this phone."}) async {
  var ok = false;
  try {
    ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {
    ok = false;
  }
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure)));
  }
  return ok;
}
