import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/auth/auth_service.dart';
import 'core/config.dart';
import 'core/theme/app_theme.dart';
import 'router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.validate();
  await initAuthBackend();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(ProviderScope(child: YourCounselorApp(router: buildRouter())));
}

class YourCounselorApp extends StatelessWidget {
  const YourCounselorApp({super.key, required this.router});

  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Your Counselor',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: router,
    );
  }
}
