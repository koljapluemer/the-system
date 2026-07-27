import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/note_file.dart';
import '../services/frog_service.dart' as frog_service;
import 'note_index_notifier.dart';
import 'providers.dart';

class FrogState {
  final bool loading;
  final String? currentFilename;
  final NoteFile? currentNote;

  /// Whether any action has already been recorded today — once true, the
  /// Frog flow stops offering [currentNote] for the rest of the day,
  /// regardless of which action produced it.
  final bool actedToday;

  /// Whether there are no `frog` notes at all.
  final bool poolEmpty;

  const FrogState({
    this.loading = true,
    this.currentFilename,
    this.currentNote,
    this.actedToday = false,
    this.poolEmpty = false,
  });

  FrogState copyWith({
    bool? loading,
    String? currentFilename,
    NoteFile? currentNote,
    bool? actedToday,
    bool? poolEmpty,
    bool clearCurrent = false,
  }) {
    return FrogState(
      loading: loading ?? this.loading,
      currentFilename: clearCurrent ? null : (currentFilename ?? this.currentFilename),
      currentNote: clearCurrent ? null : (currentNote ?? this.currentNote),
      actedToday: actedToday ?? this.actedToday,
      poolEmpty: poolEmpty ?? this.poolEmpty,
    );
  }
}

/// Drives the Frog flow: each logical day (see [frog_service.dayKeyFor]),
/// surfaces exactly one random `frog` note, avoiding a repeat of the
/// previous day's pick when another candidate exists, and gates further
/// action once anything has been recorded for the day. Mirrors
/// [PromptNotifier]'s convention of recomputing from the current index
/// rather than snapshotting a queue up front, but the "due" pool for Frog
/// is pool-level and day-scoped rather than per-note, so the pick and the
/// "acted today" gate are persisted via [FrogStateService] instead of on
/// individual notes — see frog_state_service.dart for why.
class FrogNotifier extends Notifier<FrogState> {
  int _generation = 0;

  @override
  FrogState build() {
    ref.watch(dataFolderProvider);
    final generation = ++_generation;
    Future.microtask(() => _load(generation));
    return const FrogState();
  }

  List<MapEntry<String, NoteFile>> _frogEntries() {
    final index = ref.read(noteIndexProvider).value;
    if (index == null) return [];
    return [
      for (final e in index.entries.entries)
        if (e.value['primaryType'] == 'frog') e,
    ];
  }

  Future<void> _load(int generation) async {
    await ref.read(noteIndexProvider.future);
    if (!ref.mounted || generation != _generation) return;

    final stateService = ref.read(frogStateServiceProvider);
    final now = DateTime.now();
    final dayKey = frog_service.dayKeyFor(now);
    final actedToday = await stateService.getActedDayKey() == dayKey;

    final entries = _frogEntries();
    if (entries.isEmpty) {
      state = state.copyWith(
        loading: false,
        actedToday: actedToday,
        poolEmpty: true,
        clearCurrent: true,
      );
      return;
    }

    final pickedDayKey = await stateService.getPickedDayKey();
    final pickedFilename = await stateService.getPickedFilename();

    MapEntry<String, NoteFile>? picked;
    if (pickedDayKey == dayKey && pickedFilename != null) {
      for (final e in entries) {
        if (e.key == pickedFilename) {
          picked = e;
          break;
        }
      }
    }

    if (picked == null) {
      // Rolling over to a new pick: snapshot whatever was picked before (if
      // anything) as "previous", so it can be excluded below when it's
      // actually yesterday's pick.
      if (pickedDayKey != null && pickedFilename != null) {
        await stateService.setPrevious(dayKey: pickedDayKey, filename: pickedFilename);
      }

      final previousDayKey = await stateService.getPreviousDayKey();
      final previousFilename = await stateService.getPreviousFilename();
      final yesterdayKey = frog_service.dayKeyFor(now.subtract(const Duration(days: 1)));
      final exclude = previousDayKey == yesterdayKey ? previousFilename : null;

      picked = frog_service.pickFrog(entries, excludeFilename: exclude);
      await stateService.setPicked(dayKey: dayKey, filename: picked.key);
    }

    if (!ref.mounted || generation != _generation) return;
    state = state.copyWith(
      loading: false,
      currentFilename: picked.key,
      currentNote: picked.value,
      actedToday: actedToday,
      poolEmpty: false,
    );
  }

  Future<void> _recordActed() async {
    final dayKey = frog_service.dayKeyFor(DateTime.now());
    await ref.read(frogStateServiceProvider).setActedDayKey(dayKey);
    state = state.copyWith(actedToday: true);
  }

  /// "Done" — the frog stays in the pool.
  Future<void> markDone() => _recordActed();

  /// "Impossible Today" — functionally identical to "Done": the frog stays
  /// in the pool, and today is still gated.
  Future<void> markImpossibleToday() => _recordActed();

  /// "Done & Delete" — the frog is removed from the pool.
  Future<void> markDoneAndDelete() => _deleteCurrentAndRecordActed();

  /// "Just Delete" — the frog is removed from the pool without being
  /// marked done, but today is still gated (matching the source app: any
  /// action counts).
  Future<void> markJustDelete() => _deleteCurrentAndRecordActed();

  Future<void> _deleteCurrentAndRecordActed() async {
    final filename = state.currentFilename;
    if (filename != null) {
      await ref.read(noteIndexProvider.notifier).delete(filename);
    }
    await _recordActed();
  }
}

final frogProvider = NotifierProvider<FrogNotifier, FrogState>(FrogNotifier.new);
