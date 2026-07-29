import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

String _formatDuration(Duration d) {
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

/// A minimal audio player: play/pause plus a draggable playback-position
/// slider, for the Listen flow and the Audio File section's inline preview.
/// Owns one [AudioPlayer] for [file]'s lifetime, loading a new source
/// whenever [file] changes. Loading only prepares the source — it never
/// starts playback on its own unless [autoPlay] is set, so e.g. just opening
/// a note's detail view doesn't start audio playing behind your back.
class AudioPlayerWidget extends StatefulWidget {
  final File file;
  final bool autoPlay;
  final VoidCallback? onEnded;

  const AudioPlayerWidget({super.key, required this.file, this.autoPlay = false, this.onEnded});

  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  final _player = AudioPlayer();
  PlayerState _playerState = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<void>? _completeSub;

  @override
  void initState() {
    super.initState();
    _stateSub = _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _playerState = state);
    });
    _positionSub = _player.onPositionChanged.listen((position) {
      if (mounted) setState(() => _position = position);
    });
    _durationSub = _player.onDurationChanged.listen((duration) {
      if (mounted) setState(() => _duration = duration);
    });
    _completeSub = _player.onPlayerComplete.listen((_) {
      widget.onEnded?.call();
    });
    _load(widget.file);
  }

  @override
  void didUpdateWidget(AudioPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path) {
      _position = Duration.zero;
      _duration = Duration.zero;
      _load(widget.file);
    }
  }

  Future<void> _load(File file) async {
    await _player.setSource(DeviceFileSource(file.path));
    if (widget.autoPlay && mounted) {
      await _player.resume();
    }
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _completeSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    if (_playerState == PlayerState.playing) {
      _player.pause();
    } else {
      _player.resume();
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxMillis = _duration.inMilliseconds > 0 ? _duration.inMilliseconds.toDouble() : 1.0;
    final positionMillis = _position.inMilliseconds.clamp(0, maxMillis.toInt()).toDouble();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              iconSize: 40,
              icon: Icon(_playerState == PlayerState.playing
                  ? Icons.pause_circle_filled
                  : Icons.play_circle_filled),
              onPressed: _togglePlayPause,
            ),
            Expanded(
              child: Slider(
                value: positionMillis,
                max: maxMillis,
                onChanged: (value) {
                  setState(() => _position = Duration(milliseconds: value.toInt()));
                },
                onChangeEnd: (value) => _player.seek(Duration(milliseconds: value.toInt())),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatDuration(_position), style: Theme.of(context).textTheme.bodySmall),
              Text(_formatDuration(_duration), style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}
