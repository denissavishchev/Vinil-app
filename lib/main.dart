import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_controller.dart';
import 'ui/home_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
  );
  final app = AppController();
  runApp(VinilApp(app: app));
  app.init();
}

class VinilApp extends StatelessWidget {
  final AppController app;
  const VinilApp({super.key, required this.app});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Devis Vinil',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: navy,
    ),
    home: HomeScreen(app: app),
  );
}
