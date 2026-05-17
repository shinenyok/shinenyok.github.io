import 'package:flutter/material.dart';

import 'site/site_shell.dart';

class IconForgeApp extends StatelessWidget {
  const IconForgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'App Icon Forge',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff1f8a70),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xfff6f7f2),
        useMaterial3: true,
      ),
      home: const SiteShell(),
    );
  }
}
