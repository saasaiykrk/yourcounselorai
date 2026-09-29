import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Blocks screenshots, screen recording and the recent-apps preview on
/// Android while a case screen is open (FLAG_SECURE, see MainActivity.kt).
/// iPhone can't block screenshots; instead the app is blurred in the app
/// switcher (SceneDelegate.swift). Other platforms: no-op.
class ScreenProtection {
  static const _channel = MethodChannel('yourcounselor/screen_protection');
  static int _holders = 0;

  static Future<void> _apply(bool on) async {
    try {
      await _channel.invokeMethod<void>(on ? 'enable' : 'disable');
    } on MissingPluginException {
      // iOS, web and tests have no handler.
    } on PlatformException {
      // Never let protection failures crash a consult.
    }
  }

  static void acquire() {
    if (_holders++ == 0) _apply(true);
  }

  static void release() {
    if (_holders > 0 && --_holders == 0) _apply(false);
  }
}

/// Wrap any screen that shows case text or a reply.
class ProtectedScreen extends StatefulWidget {
  const ProtectedScreen({super.key, required this.child});

  final Widget child;

  @override
  State<ProtectedScreen> createState() => _ProtectedScreenState();
}

class _ProtectedScreenState extends State<ProtectedScreen> {
  @override
  void initState() {
    super.initState();
    ScreenProtection.acquire();
  }

  @override
  void dispose() {
    ScreenProtection.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
