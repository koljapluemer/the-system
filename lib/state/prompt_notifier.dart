import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/note_file.dart';
import '../services/prompt_service.dart' as prompt_service;
import '../widgets/undo_snackbar.dart';
import 'note_index_notifier.dart';
import 'providers.dart';

class PromptState {
  final bool loading;
  final String? currentFilename;
  final NoteFile? currentNote;

  const PromptState({this.loading = true, this.currentFilename, this.currentNote});

  PromptState copyWith({
    bool? loading,
    String? currentFilename,
    NoteFile? currentNote,
    bool clearCurrent = false,
  }) {
    return PromptState(
      loading: loading ?? this.loading,
      currentFilename: clearCurrent ? null : (currentFilename ?? this.currentFilename),
      currentNote: clearCurrent ? null : (currentNote ?? this.currentNote),
    );
  }
}

/// Drives the Prompts flow: repeatedly picks a random due `prompt` note
/// (see [prompt_service.isDuePrompt]), and applies [prompt_service.recordAnswer]
/// on answer. Mirrors [MemorizeNotifier]'s convention of recomputing the due
/// pool fresh from the current index on every [_loadNext] rather than
/// snapshotting a queue up front — a just-answered prompt naturally drops
/// out of the due pool once its new `lastShownAt` makes it not-due.
class PromptNotifier extends Notifier<PromptState> {
  final _random = Random();
  int _generation = 0;

  /// The most recently shown prompt's filename, excluded from the next pick
  /// (when another candidate exists) so the same prompt never comes up
  /// twice in a row.
  String? _lastShownFilename;

  @override
  PromptState build() {
    ref.watch(dataFolderProvider);
    final generation = ++_generation;
    Future.microtask(() => _loadNext(generation));
    return const PromptState();
  }

  List<MapEntry<String, NoteFile>> _promptEntries() {
    final index = ref.read(noteIndexProvider).value;
    if (index == null) return [];
    return [
      for (final e in index.entries.entries)
        if (e.value['primaryType'] == 'prompt') e,
    ];
  }

  Future<void> _loadNext(int generation) async {
    await ref.read(noteIndexProvider.future);
    if (!ref.mounted || generation != _generation) return;

    final entries = _promptEntries();
    final now = DateTime.now();
    final due = [
      for (final e in entries)
        if (prompt_service.isDuePrompt(e.value, now)) e,
    ];

    if (due.isEmpty) {
      state = state.copyWith(loading: false, clearCurrent: true);
      return;
    }

    final withoutLast = [for (final e in due) if (e.key != _lastShownFilename) e];
    final pool = withoutLast.isNotEmpty ? withoutLast : due;

    final picked = pool[_random.nextInt(pool.length)];
    _lastShownFilename = picked.key;
    state = state.copyWith(
      loading: false,
      currentFilename: picked.key,
      currentNote: picked.value,
    );
  }

  /// Records [text] as the current prompt's answer and advances to the next
  /// due prompt.
  Future<void> answer(String text) async {
    final filename = state.currentFilename;
    final note = state.currentNote;
    if (filename == null || note == null || text.trim().isEmpty) return;
    final updated = prompt_service.recordAnswer(note, text.trim(), DateTime.now());
    await ref.read(noteIndexProvider.notifier).write(filename, updated);
    await _loadNext(_generation);
  }

  /// Deletes the current prompt immediately, offers Undo, and advances
  /// regardless — matching MemorizeNotifier.deleteCurrent's convention.
  Future<void> deleteCurrent(BuildContext context) async {
    final filename = state.currentFilename;
    final note = state.currentNote;
    if (filename == null || note == null) return;
    final indexNotifier = ref.read(noteIndexProvider.notifier);
    await indexNotifier.delete(filename);
    final title = note['title'] as String? ?? filename;
    if (context.mounted) {
      showUndoSnackBar(
        context,
        message: 'Deleted "$title"',
        onUndo: () => indexNotifier.write(filename, note),
      );
    }
    await _loadNext(_generation);
  }
}

final promptProvider = NotifierProvider<PromptNotifier, PromptState>(PromptNotifier.new);
