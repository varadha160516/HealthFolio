package com.careloop.careloop_mobile

import io.flutter.embedding.android.FlutterFragmentActivity

// local_auth's BiometricPrompt integration requires a FragmentActivity host, not the plain
// FlutterActivity the template generates by default.
class MainActivity : FlutterFragmentActivity()
