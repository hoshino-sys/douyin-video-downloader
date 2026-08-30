import 'package:flutter/material.dart';

import 'pages/splash_page.dart';
import 'services/theme_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await themeController.load();
  runApp(const DoukApp());
}

class DoukApp extends StatelessWidget {
  const DoukApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) => MaterialApp(
        title: '夜星视频下载器',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFE2C55), brightness: Brightness.light),
          useMaterial3: true,
          fontFamily: 'Noto Sans SC',
          fontFamilyFallback: const ['Microsoft YaHei UI'],
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFE2C55), brightness: Brightness.dark),
          useMaterial3: true,
          fontFamily: 'Noto Sans SC',
          fontFamilyFallback: const ['Microsoft YaHei UI'],
        ),
        themeMode: themeController.mode,
        home: const SplashPage(),
      ),
    );
  }
}
