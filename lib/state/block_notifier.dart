import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/sound_service.dart';
import 'note_index_notifier.dart';

enum BlockStep { inputting, timing, finished }

const _blockDuration = Duration(minutes: 25);

class BlockState {
  final BlockStep step;
  final String task;
  final bool visualizationConfirmed;
  final String? currentFilename;
  final Duration remaining;
  final bool markValid;

  const BlockState({
    this.step = BlockStep.inputting,
    this.task = '',
    this.visualizationConfirmed = false,
    this.currentFilename,
    this.remaining = _blockDuration,
    this.markValid = true,
  });

  BlockState copyWith({
    BlockStep? step,
    String? task,
    bool? visualizationConfirmed,
    String? currentFilename,
    Duration? remaining,
    bool? markValid,
    bool clearCurrentFilename = false,
  }) {
    return BlockState(
      step: step ?? this.step,
      task: task ?? this.task,
      visualizationConfirmed: visualizationConfirmed ?? this.visualizationConfirmed,
      currentFilename:
          clearCurrentFilename ? null : (currentFilename ?? this.currentFilename),
      remaining: remaining ?? this.remaining,
      markValid: markValid ?? this.markValid,
    );
  }
}

/// Drives the Make a Block flow: a task-input screen, an auto-started
/// 25-minute countdown tied to a `block` note created up front (so Abort has
/// something to delete), and a completion screen that can loop back into
/// another timed block or return home. Mirrors MemorizeNotifier's
/// single-screen, state-driven step-switching shape.
class BlockNotifier extends Notifier<BlockState> {
  Timer? _ticker;

  @override
  BlockState build() {
    ref.onDispose(() => _ticker?.cancel());
    return const BlockState();
  }

  void setTask(String task) {
    state = state.copyWith(task: task);
  }

  void setVisualizationConfirmed(bool confirmed) {
    state = state.copyWith(visualizationConfirmed: confirmed);
  }

  void setMarkValid(bool markValid) {
    state = state.copyWith(markValid: markValid);
  }

  bool get canStart => state.task.trim().isNotEmpty && state.visualizationConfirmed;

  /// Creates the block note for the current task and starts its timer. Only
  /// valid from the inputting step, once [canStart].
  Future<void> startBlock() async {
    if (!canStart) return;
    final filename = await ref.read(noteIndexProvider.notifier).createBlock(state.task.trim());
    state = state.copyWith(
      step: BlockStep.timing,
      currentFilename: filename,
      remaining: _blockDuration,
      markValid: true,
    );
    _startTicker();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final next = state.remaining - const Duration(seconds: 1);
    if (next <= Duration.zero) {
      _ticker?.cancel();
      state = state.copyWith(remaining: Duration.zero, step: BlockStep.finished);
      unawaited(playBlockDoneSound());
      return;
    }
    state = state.copyWith(remaining: next);
  }

  /// Aborts the in-progress timer: deletes the current block note and
  /// returns to the flow's start screen with a clean slate.
  Future<void> abort() async {
    _ticker?.cancel();
    final filename = state.currentFilename;
    if (filename != null) {
      await ref.read(noteIndexProvider.notifier).delete(filename);
    }
    state = const BlockState();
  }

  /// From the finished screen: deletes the just-finished block if it wasn't
  /// marked valid, then starts a fresh timed block on the same task.
  Future<void> doAnotherBlock() async {
    await _discardIfInvalid();
    final filename = await ref.read(noteIndexProvider.notifier).createBlock(state.task);
    state = state.copyWith(
      step: BlockStep.timing,
      currentFilename: filename,
      remaining: _blockDuration,
      markValid: true,
    );
    _startTicker();
  }

  /// From the finished screen: deletes the just-finished block if it wasn't
  /// marked valid. The caller is responsible for the actual navigation back
  /// to the home screen.
  Future<void> switchTask() async {
    await _discardIfInvalid();
    state = const BlockState();
  }

  Future<void> _discardIfInvalid() async {
    final filename = state.currentFilename;
    if (filename != null && !state.markValid) {
      await ref.read(noteIndexProvider.notifier).delete(filename);
    }
  }
}

final blockProvider = NotifierProvider<BlockNotifier, BlockState>(BlockNotifier.new);
