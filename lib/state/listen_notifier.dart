import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/note_file.dart';
import '../services/audio_listen_service.dart';
import 'note_index_notifier.dart';
import 'providers.dart';

/// The actions available for the just-played note once it finishes.
enum ListenAction { next, hideForWeek, hideForTwoMonths, hideForYear, neverListenAgain }

class ListenState {
  final bool loading;
  final String? currentFilename;
  final NoteFile? currentNote;

  /// True when no `audio` note passes the hidden/never-listen/tag-filter
  /// gate at all — distinct from the day-based "everything eligible was
  /// already listened to today" case, which falls back to repeats instead of
  /// this state.
  final bool allCaughtUp;

  final TagFilterMode tagFilterMode;
  final Set<String> filterTags;

  /// Which action fires when the audio ends.
  /// Persisted for the app session (not to disk) by living on this state.
  final ListenAction selectedAction;

  const ListenState({
    this.loading = true,
    this.currentFilename,
    this.currentNote,
    this.allCaughtUp = false,
    this.tagFilterMode = TagFilterMode.or,
    this.filterTags = const {},
    this.selectedAction = ListenAction.next,
  });

  ListenState copyWith({
    bool? loading,
    String? currentFilename,
    NoteFile? currentNote,
    bool? allCaughtUp,
    TagFilterMode? tagFilterMode,
    Set<String>? filterTags,
    ListenAction? selectedAction,
    bool clearCurrent = false,
  }) {
    return ListenState(
      loading: loading ?? this.loading,
      currentFilename: clearCurrent ? null : (currentFilename ?? this.currentFilename),
      currentNote: clearCurrent ? null : (currentNote ?? this.currentNote),
      allCaughtUp: allCaughtUp ?? this.allCaughtUp,
      tagFilterMode: tagFilterMode ?? this.tagFilterMode,
      filterTags: filterTags ?? this.filterTags,
      selectedAction: selectedAction ?? this.selectedAction,
    );
  }
}

/// Drives the Listen flow: repeatedly picks a random `audio` note that
/// passes the hidden/never-listen/tag-filter gate and, preferring notes not
/// already listened to today, falling back to a same-day repeat only once
/// every eligible note has been. Pools are recomputed fresh from the current
/// index on every [_pickNext] rather than snapshotted into a queue up front,
/// matching [MemorizeNotifier].
class ListenNotifier extends Notifier<ListenState> {
  final _random = Random();
  int _generation = 0;

  @override
  ListenState build() {
    // Watched purely as a rebuild trigger: if the data folder is switched
    // mid-session, the flow must restart against the new folder's index
    // rather than keep showing a stale note.
    ref.watch(dataFolderProvider);
    final generation = ++_generation;
    Future.microtask(() => _pickNext(generation));
    return const ListenState();
  }

  List<MapEntry<String, NoteFile>> _audioEntries() {
    final index = ref.read(noteIndexProvider).value;
    if (index == null) return [];
    return [
      for (final e in index.entries.entries)
        if (e.value['primaryType'] == 'audio') e,
    ];
  }

  Future<void> _pickNext(int generation) async {
    // Await the index once so the very first pick (before noteIndexProvider
    // has resolved) doesn't race an empty snapshot.
    await ref.read(noteIndexProvider.future);
    if (!ref.mounted || generation != _generation) return;

    final now = DateTime.now();
    final hardPool = [
      for (final e in _audioEntries())
        if (!isHidden(e.value, now) && matchesTagFilter(e.value, state.tagFilterMode, state.filterTags))
          e,
    ];

    if (hardPool.isEmpty) {
      state = state.copyWith(loading: false, allCaughtUp: true, clearCurrent: true);
      return;
    }

    // Prefer notes not already listened to today, but fall back to
    // repeating one of today's if that's genuinely everything eligible.
    final notListenedToday = [for (final e in hardPool) if (!listenedToday(e.value, now)) e];
    final pool = notListenedToday.isNotEmpty ? notListenedToday : hardPool;

    // Within that pool, never repeat the note that was just current if any
    // other candidate exists.
    final currentFilename = state.currentFilename;
    final withoutCurrent = [for (final e in pool) if (e.key != currentFilename) e];
    final effectivePool = withoutCurrent.isNotEmpty ? withoutCurrent : pool;

    final picked = effectivePool[_random.nextInt(effectivePool.length)];
    final updated = markListenedNow(picked.value, now);
    await ref.read(noteIndexProvider.notifier).write(picked.key, updated);
    if (!ref.mounted || generation != _generation) return;
    state = state.copyWith(
      loading: false,
      allCaughtUp: false,
      currentFilename: picked.key,
      currentNote: updated,
    );
  }

  Future<void> next() => _pickNext(_generation);

  Future<void> _hideCurrent(NoteFile Function(NoteFile note, DateTime now) hide) async {
    final filename = state.currentFilename;
    final note = state.currentNote;
    if (filename == null || note == null) return;
    await ref.read(noteIndexProvider.notifier).write(filename, hide(note, DateTime.now()));
    await _pickNext(_generation);
  }

  Future<void> hideForWeek() => _hideCurrent((note, now) => hideForDays(note, now, 7));

  Future<void> hideForTwoMonths() => _hideCurrent((note, now) => hideForMonths(note, now, 2));

  Future<void> hideForYear() => _hideCurrent((note, now) => hideForYears(note, now, 1));

  Future<void> neverListenAgain() async {
    final filename = state.currentFilename;
    final note = state.currentNote;
    if (filename == null || note == null) return;
    await ref.read(noteIndexProvider.notifier).write(filename, markNeverListen(note));
    await _pickNext(_generation);
  }

  /// Updates the filter and, only if the current note no longer passes it,
  /// rolls a new pick — so tweaking the filter doesn't interrupt playback of
  /// a note that's still eligible.
  void _applyFilterChange(ListenState newState) {
    state = newState;
    final note = state.currentNote;
    if (note == null || !matchesTagFilter(note, state.tagFilterMode, state.filterTags)) {
      _pickNext(_generation);
    }
  }

  void setTagFilterMode(TagFilterMode mode) => _applyFilterChange(state.copyWith(tagFilterMode: mode));

  void setFilterTags(Set<String> tags) => _applyFilterChange(state.copyWith(filterTags: tags));

  void setSelectedAction(ListenAction action) => state = state.copyWith(selectedAction: action);

  Future<void> performAction(ListenAction action) {
    switch (action) {
      case ListenAction.next:
        return next();
      case ListenAction.hideForWeek:
        return hideForWeek();
      case ListenAction.hideForTwoMonths:
        return hideForTwoMonths();
      case ListenAction.hideForYear:
        return hideForYear();
      case ListenAction.neverListenAgain:
        return neverListenAgain();
    }
  }

  /// Applies [ListenState.selectedAction] to the completed note and loads the
  /// next one.
  Future<void> onAudioEnded() => performAction(state.selectedAction);
}

final listenProvider = NotifierProvider<ListenNotifier, ListenState>(ListenNotifier.new);
