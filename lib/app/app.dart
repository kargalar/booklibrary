import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../views/auth_gate.dart';
import 'app_theme.dart';
import 'providers.dart';

class BookLibraryApp extends ConsumerStatefulWidget {
  const BookLibraryApp({super.key});

  @override
  ConsumerState<BookLibraryApp> createState() => _BookLibraryAppState();
}

class _BookLibraryAppState extends ConsumerState<BookLibraryApp> {
  @override
  void initState() {
    super.initState();
    unawaited(ref.read(themeControllerProvider).load());
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeControllerProvider).value;
    const seedColor = Color(0xFF606060);
    final lightScheme =
        ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.light,
        ).copyWith(
          surface: const Color(0xFFF3F3F3),
          surfaceContainerLowest: Colors.white,
        );
    final darkScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
    );

    return MaterialApp(
      title: 'Book Library',
      theme: buildAppTheme(lightScheme),
      darkTheme: buildAppTheme(darkScheme),
      themeMode: themeMode,
      home: const AuthGate(),
    );
  }
}

class MyApp extends BookLibraryApp {
  const MyApp({super.key});
}
