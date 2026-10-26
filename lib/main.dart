import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'data/local_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: CircularProgressIndicator())),
    ),
  );
  try {
    await LocalBootstrap.initialize();
    runApp(const ProviderScope(child: BookLibraryApp()));
  } catch (error) {
    runApp(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('Local library')),
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Your stored data has been preserved. The library could not be opened.\n\n$error',
            ),
          ),
        ),
      ),
    );
  }
}
