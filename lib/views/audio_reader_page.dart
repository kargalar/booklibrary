import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

String audioTimestamp(Duration duration) {
  final seconds = duration.inSeconds;
  return '${seconds ~/ 3600}:${(seconds ~/ 60 % 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
}

String audioPlaybackTimestamp(Duration duration, double speed) {
  final safeSpeed = speed > 0 ? speed : 1.0;
  return audioTimestamp(
    Duration(milliseconds: (duration.inMilliseconds / safeSpeed).round()),
  );
}

class AudioNotification {
  static const _channel = MethodChannel(
    'com.example.booklibrary/audio_notification',
  );
  static AudioPlayer? _player;
  static double _speed = 1;
  static String? _title;
  static bool? _playing;
  static int? _positionMs, _durationMs;
  static bool _handlerConfigured = false;

  static void attach(AudioPlayer player) {
    if (!identical(_player, player)) {
      _title = null;
      _playing = null;
      _positionMs = null;
      _durationMs = null;
    }
    _player = player;
    if (!_handlerConfigured) {
      _handlerConfigured = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'action') {
          await _handleAction(call.arguments as String?);
        }
      });
    }
    unawaited(_ready());
  }

  static Future<void> _ready() async {
    try {
      await _channel.invokeMethod<void>('ready');
    } catch (_) {}
  }

  static Future<void> _handleAction(String? action) async {
    final player = _player;
    if (player == null) return;
    try {
      switch (action) {
        case 'playPause':
          if (player.state == PlayerState.playing) {
            await player.pause();
          } else {
            final position = await player.getCurrentPosition() ?? Duration.zero;
            final duration = await player.getDuration() ?? Duration.zero;
            if (duration > Duration.zero && position >= duration) {
              await player.seek(Duration.zero);
            }
            await player.resume();
            await player.setPlaybackRate(_speed);
          }
        case 'rewind':
          await _skip(player, const Duration(seconds: -5));
        case 'forward':
          await _skip(player, const Duration(seconds: 5));
        case 'stop':
          await player.stop();
      }
    } catch (_) {}
  }

  static Future<void> _skip(AudioPlayer player, Duration offset) async {
    final position = await player.getCurrentPosition() ?? Duration.zero;
    final duration = await player.getDuration() ?? Duration.zero;
    final target = Duration(
      milliseconds: (position.inMilliseconds + offset.inMilliseconds).clamp(
        0,
        duration.inMilliseconds,
      ),
    );
    await player.seek(target);
  }

  static Future<void> update({
    required String title,
    required Duration position,
    required Duration duration,
    required double speed,
    required bool playing,
    bool force = false,
  }) async {
    final safeSpeed = speed > 0 ? speed : 1.0;
    if (duration.inMilliseconds <= 0) return;
    _speed = safeSpeed;
    final positionMs = position.inMilliseconds;
    final durationMs = duration.inMilliseconds;
    if (!force &&
        _title == title &&
        _playing == playing &&
        _durationMs == durationMs &&
        (_positionMs == null || (positionMs - _positionMs!).abs() < 1000)) {
      return;
    }
    _title = title;
    _playing = playing;
    _positionMs = positionMs;
    _durationMs = durationMs;
    try {
      await _channel.invokeMethod<void>('update', {
        'title': title,
        'playing': playing,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'positionText': audioPlaybackTimestamp(position, safeSpeed),
        'durationText': audioPlaybackTimestamp(duration, safeSpeed),
        'speed': safeSpeed,
      });
    } catch (_) {}
  }

  static void detach(AudioPlayer player) {
    if (!identical(_player, player)) return;
    _player = null;
    _title = null;
    _playing = null;
    _positionMs = null;
    _durationMs = null;
    unawaited(_hide());
  }

  static Future<void> _hide() async {
    try {
      await _channel.invokeMethod<void>('hide');
    } catch (_) {}
  }
}

class AudioReaderPage extends StatefulWidget {
  const AudioReaderPage({
    super.key,
    required this.file,
    required this.title,
    required this.storageKey,
    required this.onProgress,
    required this.onQuickNote,
    this.player,
    this.coverPath,
    this.coverUrl,
    this.coverStorageUrl,
    this.localCoverPath,
  });
  final File file;
  final String title;
  final String storageKey;
  final Future<void> Function(double) onProgress;
  final Future<void> Function(String) onQuickNote;
  final AudioPlayer? player;
  final String? coverPath, coverUrl, coverStorageUrl, localCoverPath;

  @override
  State<AudioReaderPage> createState() => _AudioReaderPageState();
}

class _AudioReaderPageState extends State<AudioReaderPage>
    with WidgetsBindingObserver {
  late final AudioPlayer player = widget.player ?? AudioPlayer();
  final subscriptions = <StreamSubscription<dynamic>>[];
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  double speed = 1;
  bool ready = false;
  bool saving = false;
  bool saveAgain = false;
  bool dragging = false;
  String? error;
  Timer? checkpoint;
  Timer? sleepTimer;
  int sleepMinutes = 0;
  SharedPreferences? prefs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AudioNotification.attach(player);
    subscriptions.add(
      player.onPositionChanged.listen((value) {
        if (mounted && !dragging) {
          setState(() => position = value);
          _updateNotification();
        }
      }),
    );
    subscriptions.add(
      player.onDurationChanged.listen((value) {
        if (mounted) {
          setState(() => duration = value);
          _updateNotification(force: true);
        }
      }),
    );
    subscriptions.add(
      player.onPlayerStateChanged.listen((_) {
        if (mounted) {
          setState(() {});
          _updateNotification(force: true);
        }
      }),
    );
    subscriptions.add(
      player.onPlayerComplete.listen((_) {
        position = duration;
        _updateNotification(force: true);
        unawaited(_persist());
      }),
    );
    subscriptions.add(
      player.eventStream.listen(
        (_) {},
        onError: (Object value) {
          if (mounted) {
            setState(() => error = 'Audio could not be played: $value');
          }
        },
      ),
    );
    unawaited(_load());
    if (widget.player == null) {
      checkpoint = Timer.periodic(
        const Duration(seconds: 10),
        (_) => unawaited(_persist()),
      );
    }
  }

  void _updateNotification({bool force = false}) => unawaited(
    AudioNotification.update(
      title: widget.title,
      position: position,
      duration: duration,
      speed: speed,
      playing: player.state == PlayerState.playing,
      force: force,
    ),
  );

  Future<void> _load() async {
    try {
      prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      await player.setSource(DeviceFileSource(widget.file.path));
      if (!mounted) return;
      await player.setReleaseMode(ReleaseMode.stop);
      duration = await player.getDuration() ?? Duration.zero;
      speed = (prefs!.getDouble('${widget.storageKey}.speed') ?? 1).clamp(
        .5,
        2,
      );
      final milliseconds = prefs!.getInt('${widget.storageKey}.position') ?? 0;
      position = Duration(
        milliseconds: milliseconds.clamp(0, duration.inMilliseconds),
      );
      await player.seek(position);
      await player.setPlaybackRate(speed);
      if (mounted) {
        setState(() => ready = true);
        _updateNotification(force: true);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'This audio file could not be opened. Select another supported file.',
        );
      }
    }
  }

  Future<void> _persist() async {
    if (!ready || duration.inMilliseconds == 0) return;
    if (saving) {
      saveAgain = true;
      return;
    }
    saving = true;
    try {
      await prefs!.setInt(
        '${widget.storageKey}.position',
        position.inMilliseconds,
      );
      await widget.onProgress(
        (position.inMilliseconds / duration.inMilliseconds).clamp(0, 1),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Progress could not be saved. It will be retried.',
        );
      }
    } finally {
      saving = false;
      if (saveAgain) {
        saveAgain = false;
        unawaited(_persist());
      }
    }
  }

  Future<void> _act(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'The operation could not be completed. Try again.',
        );
      }
    }
  }

  Future<void> _seek(Duration value) async {
    final target = Duration(
      milliseconds: value.inMilliseconds.clamp(0, duration.inMilliseconds),
    );
    await player.seek(target);
    if (mounted) {
      setState(() => position = target);
      _updateNotification(force: true);
    }
    await _persist();
  }

  void _setSleepTimer(int minutes) {
    sleepTimer?.cancel();
    if (mounted) setState(() => sleepMinutes = minutes);
    if (minutes > 0) {
      sleepTimer = Timer(
        Duration(minutes: minutes),
        () => _act(() async {
          await player.pause();
          _updateNotification(force: true);
          await _persist();
          if (mounted) setState(() => sleepMinutes = 0);
        }),
      );
    }
  }

  Future<void> _note() async {
    final timestamp = audioTimestamp(position);
    var text = '';
    var noteSaving = false;
    String? noteError;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => PopScope(
          canPop: !noteSaving,
          child: AlertDialog(
            title: Text('Add note · $timestamp'),
            content: TextField(
              onChanged: (value) => text = value,
              enabled: !noteSaving,
              decoration: InputDecoration(errorText: noteError),
              autofocus: true,
              minLines: 3,
              maxLines: 6,
            ),
            actions: [
              TextButton(
                onPressed: noteSaving ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: noteSaving
                    ? null
                    : () async {
                        if (text.trim().isEmpty) return;
                        update(() {
                          noteSaving = true;
                          noteError = null;
                        });
                        try {
                          await widget.onQuickNote(
                            '[$timestamp] ${text.trim()}',
                          );
                          if (context.mounted) {
                            update(() => noteSaving = false);
                            Navigator.pop(context);
                          }
                        } catch (_) {
                          if (context.mounted) {
                            update(() {
                              noteSaving = false;
                              noteError = 'Could not save the note. Try again.';
                            });
                          }
                        }
                      },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_persist());
      _updateNotification(force: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    checkpoint?.cancel();
    sleepTimer?.cancel();
    for (final subscription in subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_persist());
    if (widget.player == null) unawaited(player.dispose());
    super.dispose();
  }

  Widget _coverFallback() => const ColoredBox(
    color: Colors.black12,
    child: Center(child: Icon(Icons.headphones_rounded, size: 72)),
  );

  Widget _audioCover() {
    final coverPath = widget.coverPath;
    final coverUrl = widget.coverStorageUrl?.startsWith('http') == true
        ? widget.coverStorageUrl
        : coverPath?.startsWith('http') == true
        ? coverPath
        : widget.coverUrl;
    final localPath = widget.localCoverPath?.isNotEmpty == true
        ? widget.localCoverPath
        : coverPath?.startsWith('http') == true
        ? null
        : coverPath;
    final image = localPath?.isNotEmpty == true
        ? Image.file(
            File(localPath!),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => coverUrl?.isNotEmpty == true
                ? Image.network(
                    coverUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _coverFallback(),
                  )
                : _coverFallback(),
          )
        : coverUrl?.isNotEmpty == true
        ? Image.network(
            coverUrl!,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _coverFallback(),
          )
        : _coverFallback();
    return Center(
      child: SizedBox(
        width: 160,
        height: 220,
        child: ClipRRect(borderRadius: BorderRadius.circular(14), child: image),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.title),
      actions: [
        IconButton(
          tooltip: 'Quick note',
          onPressed: ready ? () => _act(_note) : null,
          icon: const Icon(Icons.note_add_outlined),
        ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              _audioCover(),
              const SizedBox(height: 24),
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (!ready && error == null)
                const Center(child: CircularProgressIndicator()),
              Slider(
                value: position.inMilliseconds.toDouble().clamp(
                  0,
                  duration.inMilliseconds.toDouble(),
                ),
                max: duration.inMilliseconds > 0
                    ? duration.inMilliseconds.toDouble()
                    : 1,
                onChanged: ready
                    ? (value) => setState(() {
                        dragging = true;
                        position = Duration(milliseconds: value.round());
                      })
                    : null,
                onChangeEnd: ready
                    ? (value) => _act(() async {
                        try {
                          await _seek(Duration(milliseconds: value.round()));
                        } finally {
                          dragging = false;
                        }
                      })
                    : null,
              ),
              Text(
                '${audioPlaybackTimestamp(position, speed)} / ${audioPlaybackTimestamp(duration, speed)}',
                textAlign: TextAlign.center,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Back 10 seconds',
                    onPressed: ready
                        ? () => _act(
                            () => _seek(position - const Duration(seconds: 10)),
                          )
                        : null,
                    icon: const Icon(Icons.replay_10),
                  ),
                  IconButton.filled(
                    iconSize: 48,
                    tooltip: player.state == PlayerState.playing
                        ? 'Pause'
                        : 'listen',
                    onPressed: ready
                        ? () => _act(() async {
                            if (player.state == PlayerState.playing) {
                              await player.pause();
                              _updateNotification(force: true);
                              await _persist();
                            } else {
                              if (position >= duration) {
                                await _seek(Duration.zero);
                              }
                              await player.resume();
                              await player.setPlaybackRate(speed);
                              _updateNotification(force: true);
                            }
                          })
                        : null,
                    icon: Icon(
                      player.state == PlayerState.playing
                          ? Icons.pause
                          : Icons.play_arrow,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Forward 10 seconds',
                    onPressed: ready
                        ? () => _act(
                            () => _seek(position + const Duration(seconds: 10)),
                          )
                        : null,
                    icon: const Icon(Icons.forward_10),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  PopupMenuButton<double>(
                    enabled: ready,
                    tooltip: 'Playback speed: ${speed}x',
                    padding: EdgeInsets.zero,
                    iconSize: 22,
                    icon: const Icon(Icons.speed),
                    onSelected: (value) => _act(() async {
                      await player.setPlaybackRate(value);
                      await prefs!.setDouble(
                        '${widget.storageKey}.speed',
                        value,
                      );
                      if (mounted) {
                        setState(() => speed = value);
                        _updateNotification(force: true);
                      }
                    }),
                    itemBuilder: (_) => [
                      for (final value in [.5, .75, 1.0, 1.25, 1.5, 1.75, 2.0])
                        CheckedPopupMenuItem<double>(
                          value: value,
                          checked: speed == value,
                          child: Text('${value}x'),
                        ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  PopupMenuButton<int>(
                    enabled: ready,
                    tooltip: sleepMinutes == 0
                        ? 'sleep timer'
                        : 'Stop after $sleepMinutes minutes',
                    padding: EdgeInsets.zero,
                    iconSize: 22,
                    icon: Icon(
                      sleepMinutes == 0
                          ? Icons.bedtime_outlined
                          : Icons.bedtime,
                    ),
                    onSelected: _setSleepTimer,
                    itemBuilder: (_) => [
                      for (final value in [0, 15, 30, 45, 60])
                        CheckedPopupMenuItem<int>(
                          value: value,
                          checked: sleepMinutes == value,
                          child: Text(value == 0 ? 'Off' : '$value minutes'),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class AudioMiniPlayer extends StatefulWidget {
  const AudioMiniPlayer({
    super.key,
    required this.player,
    required this.title,
    required this.storageKey,
    required this.onProgress,
    required this.onOpen,
    required this.onClose,
  });

  final AudioPlayer player;
  final String title, storageKey;
  final Future<void> Function(double) onProgress;
  final Future<void> Function() onOpen;
  final VoidCallback onClose;

  @override
  State<AudioMiniPlayer> createState() => _AudioMiniPlayerState();
}

class _AudioMiniPlayerState extends State<AudioMiniPlayer> {
  final subscriptions = <StreamSubscription<dynamic>>[];
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  double speed = 1;
  int sleepMinutes = 0;
  bool dragging = false;
  Timer? checkpoint;
  Timer? sleepTimer;
  SharedPreferences? prefs;
  bool persisting = false;

  @override
  void initState() {
    super.initState();
    AudioNotification.attach(widget.player);
    subscriptions.add(
      widget.player.onPositionChanged.listen((value) {
        if (mounted && !dragging) {
          setState(() => position = value);
          _updateNotification();
        }
      }),
    );
    subscriptions.add(
      widget.player.onDurationChanged.listen((value) {
        if (mounted) {
          setState(() => duration = value);
          _updateNotification(force: true);
        }
      }),
    );
    subscriptions.add(
      widget.player.onPlayerStateChanged.listen((_) {
        if (mounted) {
          setState(() {});
          _updateNotification(force: true);
        }
      }),
    );
    subscriptions.add(
      widget.player.onPlayerComplete.listen((_) {
        if (mounted) {
          setState(() => position = duration);
          _updateNotification(force: true);
        }
        unawaited(_persist());
      }),
    );
    unawaited(_loadPosition());
    checkpoint = Timer.periodic(
      const Duration(seconds: 10),
      (_) => unawaited(_persist()),
    );
  }

  void _updateNotification({bool force = false}) => unawaited(
    AudioNotification.update(
      title: widget.title,
      position: position,
      duration: duration,
      speed: speed,
      playing: widget.player.state == PlayerState.playing,
      force: force,
    ),
  );

  Future<void> _loadPosition() async {
    try {
      final nextDuration = await widget.player.getDuration();
      final nextPosition = await widget.player.getCurrentPosition();
      prefs ??= await SharedPreferences.getInstance();
      final nextSpeed = (prefs!.getDouble('${widget.storageKey}.speed') ?? 1)
          .clamp(.5, 2)
          .toDouble();
      await widget.player.setPlaybackRate(nextSpeed);
      if (!mounted) return;
      setState(() {
        duration = nextDuration ?? Duration.zero;
        position = nextPosition ?? Duration.zero;
        speed = nextSpeed;
      });
      _updateNotification(force: true);
    } catch (_) {
      // The full player displays detailed playback errors.
    }
  }

  Future<void> _persist() async {
    if (persisting || duration.inMilliseconds <= 0) return;
    persisting = true;
    try {
      prefs ??= await SharedPreferences.getInstance();
      await prefs!.setInt(
        '${widget.storageKey}.position',
        position.inMilliseconds,
      );
      await widget.onProgress(
        (position.inMilliseconds / duration.inMilliseconds).clamp(0, 1),
      );
    } catch (_) {
      // The full player will retry while it is open.
    } finally {
      persisting = false;
    }
  }

  Future<void> _seek(Duration value) async {
    try {
      final target = Duration(
        milliseconds: value.inMilliseconds.clamp(0, duration.inMilliseconds),
      );
      await widget.player.seek(target);
      if (mounted) {
        setState(() => position = target);
        _updateNotification(force: true);
      }
      await _persist();
    } catch (_) {
      // The full player displays detailed playback errors.
    }
  }

  Future<void> _finishSeek(double value) async {
    try {
      await _seek(Duration(milliseconds: value.round()));
    } finally {
      if (mounted) setState(() => dragging = false);
    }
  }

  Future<void> _setSpeed(double value) async {
    try {
      await widget.player.setPlaybackRate(value);
      prefs ??= await SharedPreferences.getInstance();
      await prefs!.setDouble('${widget.storageKey}.speed', value);
      if (mounted) {
        setState(() => speed = value);
        _updateNotification(force: true);
      }
    } catch (_) {
      // The full player displays detailed playback errors.
    }
  }

  void _setSleepTimer(int minutes) {
    sleepTimer?.cancel();
    if (mounted) setState(() => sleepMinutes = minutes);
    if (minutes > 0) {
      sleepTimer = Timer(
        Duration(minutes: minutes),
        () => unawaited(_pauseForSleep()),
      );
    }
  }

  Future<void> _pauseForSleep() async {
    try {
      await widget.player.pause();
      _updateNotification(force: true);
      await _persist();
      if (mounted) setState(() => sleepMinutes = 0);
    } catch (_) {
      // The full player displays detailed playback errors.
    }
  }

  Future<void> _toggle() async {
    try {
      if (widget.player.state == PlayerState.playing) {
        await widget.player.pause();
        _updateNotification(force: true);
        await _persist();
        return;
      }
      if (position >= duration) await widget.player.seek(Duration.zero);
      await widget.player.resume();
      await widget.player.setPlaybackRate(speed);
      _updateNotification(force: true);
    } catch (_) {
      // The full player displays detailed playback errors.
    }
  }

  @override
  void dispose() {
    checkpoint?.cancel();
    sleepTimer?.cancel();
    for (final subscription in subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_persist());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final max = duration.inMilliseconds.toDouble();
    final canSeek = max > 0;
    final sliderValue = canSeek
        ? position.inMilliseconds.toDouble().clamp(0, max).toDouble()
        : 0.0;
    final playing = widget.player.state == PlayerState.playing;
    return Material(
      elevation: 8,
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.headphones_rounded, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: () => unawaited(widget.onOpen()),
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                PopupMenuButton<double>(
                  tooltip: 'Listening speed',
                  onSelected: (value) => unawaited(_setSpeed(value)),
                  itemBuilder: (_) => [
                    for (final value in [.5, .75, 1.0, 1.25, 1.5, 1.75, 2.0])
                      CheckedPopupMenuItem<double>(
                        value: value,
                        checked: speed == value,
                        child: Text('${value}x'),
                      ),
                  ],
                  icon: const Icon(Icons.speed),
                ),
                PopupMenuButton<int>(
                  tooltip: sleepMinutes == 0
                      ? 'sleep timer'
                      : 'Stop after $sleepMinutes minutes',
                  onSelected: _setSleepTimer,
                  itemBuilder: (_) => [
                    for (final value in [0, 15, 30, 45, 60])
                      CheckedPopupMenuItem<int>(
                        value: value,
                        checked: sleepMinutes == value,
                        child: Text(value == 0 ? 'Off' : '$value minutes'),
                      ),
                  ],
                  icon: const Icon(Icons.bedtime_outlined),
                ),
                IconButton(
                  tooltip: playing ? 'Pause' : 'Listen',
                  onPressed: canSeek ? () => unawaited(_toggle()) : null,
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                ),
                IconButton(
                  tooltip: 'Close mini player',
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            Row(
              children: [
                IconButton(
                  tooltip: 'Back 5 seconds',
                  onPressed: canSeek
                      ? () => unawaited(
                          _seek(position - const Duration(seconds: 5)),
                        )
                      : null,
                  icon: const Icon(Icons.replay_5),
                ),
                Expanded(
                  child: Slider(
                    value: sliderValue,
                    max: canSeek ? max : 1,
                    onChanged: canSeek
                        ? (value) => setState(() {
                            dragging = true;
                            position = Duration(milliseconds: value.round());
                          })
                        : null,
                    onChangeEnd: canSeek
                        ? (value) => unawaited(_finishSeek(value))
                        : null,
                  ),
                ),
                IconButton(
                  tooltip: 'Forward 5 seconds',
                  onPressed: canSeek
                      ? () => unawaited(
                          _seek(position + const Duration(seconds: 5)),
                        )
                      : null,
                  icon: const Icon(Icons.forward_5),
                ),
              ],
            ),
            Text(
              '${audioPlaybackTimestamp(position, speed)} / ${audioPlaybackTimestamp(duration, speed)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
