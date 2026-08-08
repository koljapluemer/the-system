import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fsrs/fsrs.dart' as fsrs;

import '../models/note_file.dart';
import '../services/fsrs_service.dart' as fsrs_service;
import '../services/quote_flashcard_service.dart' as quote_service;
import '../widgets/undo_snackbar.dart';
import 'note_index_notifier.dart';
import 'providers.dart';

/// Quote-based turns above this share of shown flashcard turns in the
/// current session are throttled — see [MemorizeNotifier._quoteShareTooHigh].
const _maxQuoteShare = 0.3;

/// Quote-based turns below this share of shown flashcard turns in the
/// current session are favored — see [MemorizeNotifier._quoteShareTooLow].
const _minQuoteShare = 0.1;

/// One candidate flashcard turn in the pool [MemorizeNotifier._loadNext]
/// picks from: either a literal `flashcard` note ([level] null) or one
/// removal level of a `quote` note's on-the-fly generated flashcards
/// ([level] non-null) — see lib/services/quote_flashcard_service.dart.
class _Candidate {
  final String filename;
  final int? level;
  final bool isNew;

  /// Null exactly when [isNew] is true.
  final DateTime? due;

  const _Candidate({required this.filename, this.level, required this.isNew, this.due});

  bool get isQuote => level != null;

  /// Unique across every candidate, including multiple levels of the same
  /// quote — used for the "never repeat the same card twice in a row" rule.
  String get id => isQuote ? '$filename#$level' : filename;
}

class MemorizeState {
  final bool loading;
  final String? currentFilename;
  final NoteFile? currentNote;

  /// Non-null when [currentNote] is a `quote` note and this turn is one of
  /// its generated levels rather than the note's literal fields.
  final int? currentLevel;

  /// Resolved display text for the current turn — for a `quote` turn this is
  /// generated from [currentLevel] rather than read off [currentNote]
  /// directly (see lib/services/quote_flashcard_service.dart).
  final String displayFront;
  final String displayBack;

  /// True when the current turn has never been practiced (no fsrs data yet
  /// for [currentNote], or for [currentLevel] when it's a quote turn) — such
  /// a card opens already revealed, with only "I will remember" offered
  /// instead of the four grading buttons.
  final bool isNew;
  final bool revealed;

  /// True when this "turn" is an art-triage interstitial instead of a
  /// flashcard — [currentNote] is null in that case. Rendered inline by
  /// [MemorizeScreen] as a third turn type (alongside "flashcard" and "all
  /// caught up"), purely as a function of this flag — no imperative
  /// navigation involved, so there's nothing to lose track of across
  /// consecutive art-triage turns.
  final bool showArtTriage;

  const MemorizeState({
    this.loading = true,
    this.currentFilename,
    this.currentNote,
    this.currentLevel,
    this.displayFront = '',
    this.displayBack = '',
    this.isNew = false,
    this.revealed = false,
    this.showArtTriage = false,
  });

  MemorizeState copyWith({
    bool? loading,
    String? currentFilename,
    NoteFile? currentNote,
    int? currentLevel,
    String? displayFront,
    String? displayBack,
    bool? isNew,
    bool? revealed,
    bool? showArtTriage,
    bool clearCurrent = false,
  }) {
    return MemorizeState(
      loading: loading ?? this.loading,
      currentFilename: clearCurrent ? null : (currentFilename ?? this.currentFilename),
      currentNote: clearCurrent ? null : (currentNote ?? this.currentNote),
      currentLevel: clearCurrent ? null : (currentLevel ?? this.currentLevel),
      displayFront: clearCurrent ? '' : (displayFront ?? this.displayFront),
      displayBack: clearCurrent ? '' : (displayBack ?? this.displayBack),
      isNew: isNew ?? this.isNew,
      revealed: revealed ?? this.revealed,
      showArtTriage: showArtTriage ?? this.showArtTriage,
    );
  }
}

/// Drives the Memorize flow: repeatedly picks a random due (or, failing
/// that, brand-new) flashcard turn — either a literal `flashcard` note or
/// one level of a `quote` note's on-the-fly generated flashcards — tracks
/// reveal state, and applies fsrs grading on review. Unlike [TriageNotifier],
/// pools are recomputed fresh from the current index on every [_loadNext]
/// rather than snapshotted into a queue up front — a just-reviewed card
/// naturally drops out of the due pool once its new due date is in the
/// future, so no manual bookkeeping is needed.
class MemorizeNotifier extends Notifier<MemorizeState> {
  final _random = Random();
  int _generation = 0;

  /// The most recently shown turn's [_Candidate.id], excluded from the next
  /// pick (when another candidate exists) so the same card never comes up
  /// twice in a row.
  String? _lastShownId;

  /// Session-only (not persisted) counts backing [_quoteShareTooHigh]/
  /// [_quoteShareTooLow] — reset whenever the notifier itself is rebuilt
  /// (e.g. data folder switch), same as [_lastShownId].
  int _flashcardTurnsShown = 0;
  int _quoteTurnsShown = 0;

  @override
  MemorizeState build() {
    // Watched purely as a rebuild trigger, matching TriageNotifier: if the
    // data folder is switched mid-session, the flow must restart against
    // the new folder's index rather than keep showing stale notes.
    ref.watch(dataFolderProvider);
    final generation = ++_generation;
    Future.microtask(() => _loadNext(generation));
    return const MemorizeState();
  }

  /// `quote`-based turns' share of this session's shown turns so far, or `0`
  /// before anything has been shown.
  double get _quoteShare => _flashcardTurnsShown == 0 ? 0 : _quoteTurnsShown / _flashcardTurnsShown;

  /// True once [_quoteShare] exceeds [_maxQuoteShare] — [_loadNext] then
  /// prefers a non-quote candidate if the current pool has one, so a
  /// heavily-memorized quote can't crowd out literal flashcards.
  bool get _quoteShareTooHigh => _quoteShare > _maxQuoteShare;

  /// True while [_quoteShare] is under [_minQuoteShare] — [_loadNext] then
  /// prefers a quote candidate if the current pool has one, so quotes still
  /// get a foothold rather than being starved by a large flashcard deck.
  bool get _quoteShareTooLow => _quoteShare < _minQuoteShare;

  List<_Candidate> _candidates(DateTime now) {
    final index = ref.read(noteIndexProvider).value;
    if (index == null) return [];
    final candidates = <_Candidate>[];
    for (final entry in index.entries.entries) {
      final filename = entry.key;
      final note = entry.value;
      if (note['primaryType'] == 'flashcard') {
        final isNew = fsrs_service.isNewFlashcard(note);
        if (isNew) {
          candidates.add(_Candidate(filename: filename, isNew: true));
        } else {
          final due = fsrs_service.dueDate(note)!;
          if (!due.isAfter(now)) {
            candidates.add(_Candidate(filename: filename, isNew: false, due: due));
          }
        }
      } else if (note['primaryType'] == 'quote' && note['memorize'] == true) {
        for (final level in quote_service.introducedLevels(note)) {
          final due = quote_service.dueDateForLevel(note, level)!;
          if (!due.isAfter(now)) {
            candidates.add(_Candidate(filename: filename, level: level, isNew: false, due: due));
          }
        }
        final nextLevel = quote_service.nextUnlockableLevel(note, at: now);
        if (nextLevel != null) {
          candidates.add(_Candidate(filename: filename, level: nextLevel, isNew: true));
        }
      }
    }
    return candidates;
  }

  bool _hasArtNotes() {
    final index = ref.read(noteIndexProvider).value;
    if (index == null) return false;
    return index.entries.values.any((n) => n['primaryType'] == 'art');
  }

  Future<void> _loadNext(int generation) async {
    // Await the index once so the very first load (before noteIndexProvider
    // has resolved) doesn't race an empty snapshot.
    await ref.read(noteIndexProvider.future);
    if (!ref.mounted || generation != _generation) return;

    // Every turn is independently 1/6 art-triage, 5/6 flashcard — gated on
    // there being at least one art note so this can't roll into a dead end.
    // A turn is exactly one decision: [ArtTriageBody] shows a single note
    // and immediately calls back into this same _loadNext once the user
    // keeps/deletes/defers it, so this branch can never chain into a second
    // art note without an independent re-roll.
    if (_hasArtNotes() && _random.nextInt(6) == 0) {
      state = state.copyWith(loading: false, showArtTriage: true, clearCurrent: true);
      return;
    }

    final now = DateTime.now().toUtc();
    final candidates = _candidates(now);
    final due = [for (final c in candidates) if (!c.isNew) c];
    final fresh = [for (final c in candidates) if (c.isNew) c];

    if (due.isEmpty && fresh.isEmpty) {
      state = state.copyWith(loading: false, showArtTriage: false, clearCurrent: true);
      return;
    }

    // Keep quote-based turns within [_minQuoteShare, _maxQuoteShare] of the
    // session so far: restrict the pool to non-quote (resp. quote-only)
    // candidates when over (resp. under) budget — but only when that leaves
    // at least one, so neither kind is ever withheld when it's the only
    // thing available.
    var pool = candidates;
    if (_quoteShareTooHigh) {
      final nonQuote = [for (final c in candidates) if (!c.isQuote) c];
      if (nonQuote.isNotEmpty) pool = nonQuote;
    } else if (_quoteShareTooLow) {
      final quoteOnly = [for (final c in candidates) if (c.isQuote) c];
      if (quoteOnly.isNotEmpty) pool = quoteOnly;
    }
    final poolDue = [for (final c in pool) if (!c.isNew) c];
    final poolFresh = [for (final c in pool) if (c.isNew) c];

    // Prefer due cards over new ones, but never repeat the card just shown
    // if any other candidate exists anywhere — falling back from due to
    // fresh (or vice versa) rather than re-showing it. Throttling (above)
    // is a preference, not a hard partition: if it restricted the pool down
    // to nothing but the card just shown, that must not force a repeat when
    // an otherwise-throttled candidate (e.g. a quote, filtered out for
    // being over its share) is available — so the search widens back out to
    // the full (untimed) due/fresh sets before conceding an unavoidable
    // repeat.
    final dueWithoutLast = [for (final c in poolDue) if (c.id != _lastShownId) c];
    final freshWithoutLast = [for (final c in poolFresh) if (c.id != _lastShownId) c];
    final anyDueWithoutLast = [for (final c in due) if (c.id != _lastShownId) c];
    final anyFreshWithoutLast = [for (final c in fresh) if (c.id != _lastShownId) c];

    final List<_Candidate> pickedFrom;
    if (dueWithoutLast.isNotEmpty) {
      pickedFrom = dueWithoutLast;
    } else if (freshWithoutLast.isNotEmpty) {
      pickedFrom = freshWithoutLast;
    } else if (anyDueWithoutLast.isNotEmpty) {
      pickedFrom = anyDueWithoutLast;
    } else if (anyFreshWithoutLast.isNotEmpty) {
      pickedFrom = anyFreshWithoutLast;
    } else if (due.isNotEmpty) {
      // Only candidate left anywhere is the card just shown — unavoidable.
      pickedFrom = due;
    } else {
      pickedFrom = fresh;
    }

    final picked = pickedFrom[_random.nextInt(pickedFrom.length)];
    _lastShownId = picked.id;
    _flashcardTurnsShown++;
    if (picked.isQuote) _quoteTurnsShown++;

    final index = ref.read(noteIndexProvider).value!;
    final note = index.entries[picked.filename]!;
    final display = picked.isQuote
        ? quote_service.render(note['title'] as String? ?? '', picked.level!)
        : (front: note['front'] as String? ?? '', back: note['back'] as String? ?? '');

    state = state.copyWith(
      loading: false,
      showArtTriage: false,
      currentFilename: picked.filename,
      currentNote: note,
      currentLevel: picked.level,
      displayFront: display.front,
      displayBack: display.back,
      isNew: picked.isNew,
      revealed: picked.isNew,
    );
  }

  void reveal() {
    if (state.currentNote == null) return;
    state = state.copyWith(revealed: true);
  }

  /// Creates the initial fsrs card for the current (new) turn. Only valid
  /// when [MemorizeState.isNew].
  Future<void> rememberNew() async {
    final filename = state.currentFilename;
    final note = state.currentNote;
    if (filename == null || note == null) return;
    final level = state.currentLevel;
    final updated =
        level == null ? await fsrs_service.initializeFlashcard(note) : await quote_service.initializeLevel(note, level);
    await ref.read(noteIndexProvider.notifier).write(filename, updated);
    await _loadNext(_generation);
  }

  /// Grades the current (already-practiced) turn. Only valid when
  /// `!MemorizeState.isNew`.
  Future<void> rate(fsrs.Rating rating) async {
    final filename = state.currentFilename;
    final note = state.currentNote;
    if (filename == null || note == null) return;
    final level = state.currentLevel;
    final updated = level == null
        ? fsrs_service.reviewFlashcard(note, rating)
        : quote_service.reviewLevel(note, level, rating);
    await ref.read(noteIndexProvider.notifier).write(filename, updated);
    await _loadNext(_generation);
  }

  /// Deletes the current note immediately (for a quote turn, the whole
  /// quote — not just [MemorizeState.currentLevel]), offers Undo, and
  /// advances regardless — matching TriageNotifier.delete's convention.
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

  /// Rolls the next turn after the current art-triage turn's single
  /// keep/delete/defer decision has been made — the art-triage equivalent of
  /// [rate]/[rememberNew] advancing after a flashcard's single grade.
  Future<void> continueAfterArtTriage() async {
    await _loadNext(_generation);
  }
}

final memorizeProvider = NotifierProvider<MemorizeNotifier, MemorizeState>(MemorizeNotifier.new);
