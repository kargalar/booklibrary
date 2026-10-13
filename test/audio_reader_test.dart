import 'dart:io';

import 'package:booklibrary/views/audio_reader_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('audio resumes, seeks and saves timestamped notes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'audio.position': 120000,
      'audio.speed': 1.5,
    });
    final messenger = tester.binding.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    var position = 120000;
    String? note;
    double? progress;
    for (final name in [
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers.global/events',
    ]) {
      messenger.setMockMethodCallHandler(
        MethodChannel(name),
        (_) async => null,
      );
    }
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (call) async {
        calls.add(call);
        final arguments = call.arguments as Map;
        final channel = 'xyz.luan/audioplayers/events/${arguments['playerId']}';
        if (call.method == 'create') {
          messenger.setMockMethodCallHandler(
            MethodChannel(channel),
            (_) async => null,
          );
        }
        if (call.method == 'setSourceUrl' || call.method == 'seek') {
          if (call.method == 'seek') position = arguments['position'] as int;
          await messenger.handlePlatformMessage(
            channel,
            const StandardMethodCodec().encodeSuccessEnvelope({
              'event': call.method == 'seek'
                  ? 'audio.onSeekComplete'
                  : 'audio.onPrepared',
              'value': true,
            }),
            (_) {},
          );
        }
        if (call.method == 'getDuration') return 600000;
        if (call.method == 'getCurrentPosition') return position;
        return null;
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AudioReaderPage(
          file: File('test.mp3'),
          title: 'Sesli kitap',
          storageKey: 'audio',
          onProgress: (value) async => progress = value,
          onQuickNote: (value) async => note = value,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('0:01:20 / 0:06:40'), findsOneWidget);
    expect(
      calls.any(
        (call) =>
            call.method == 'setPlaybackRate' &&
            call.arguments['playbackRate'] == 1.5,
      ),
      isTrue,
    );
    await tester.tap(find.byTooltip('Forward 10 seconds'));
    await tester.pumpAndSettle();
    expect(position, 130000);
    expect(progress, closeTo(130 / 600, .0001));
    await tester.tap(find.byTooltip('Quick note'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Önemli bölüm');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(note, '[0:02:10] Önemli bölüm');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(
      (await SharedPreferences.getInstance()).getInt('audio.position'),
      130000,
    );
    expect(tester.takeException(), isNull);
  });
}
