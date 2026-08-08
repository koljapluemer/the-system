import 'package:fsrs/fsrs.dart' as fsrs;

import '../models/note_file.dart';

/// Generates the Memorize flow's on-the-fly `quote` flashcards from a
/// `primaryType: "quote"` note's `title` — the note's only free-text field,
/// same convention as `prompt` (see assets/note_schema.json and
/// docs/adding-a-primary-type.md) — and tracks their fsrs progress in that
/// note's `memorizeProgress` map. Unlike `primaryType: "flashcard"`, no
/// flashcard note is ever created on disk — every front/back pair is
/// recomputed from the quote text each time it's needed, keyed by an
/// integer "level" (0 = last word-group removed, counting up).
///
/// Levels are introduced strictly in order: level 0 is the only one ever
/// "new" for a freshly-memorize-flagged quote; level N+1 only becomes
/// introducible once level N has been practiced at least once and its
/// current fsrs retrievability is >=90% (see [nextUnlockableLevel]) — see
/// [Scheduler.getCardRetrievability] in package:fsrs.
final _scheduler = fsrs.Scheduler();

/// Predicted-recall threshold a level must clear (right now) before the next
/// level is allowed to be introduced as a new flashcard.
const unlockRetrievabilityThreshold = 0.9;

/// A word counts toward the removal-step algorithm below only once it has at
/// least this many letters — shorter "words" (e.g. "is", "a") never get
/// their own removal step; they're folded into the group of the next
/// significant word toward the front of the line (see [_keepCounts]).
const _significantLetterCount = 3;

final _letterPattern = RegExp(r'\p{L}', unicode: true);

int _letterCount(String word) => _letterPattern.allMatches(word).length;

/// The first non-empty line of [text], or `''` if it has none.
String firstNonEmptyLine(String text) {
  for (final line in text.split('\n')) {
    if (line.trim().isNotEmpty) return line;
  }
  return '';
}

/// The leading run of non-alphanumeric characters in [line] (e.g. an opening
/// quotation mark before the first word) — preserved verbatim at every
/// removal level, including the final one where every word has been
/// replaced by "...".
String _leadingPrefix(String line) {
  return RegExp(r'^[^A-Za-z0-9]*').firstMatch(line)!.group(0)!;
}

List<String> _words(String line) {
  final prefix = _leadingPrefix(line);
  return line.substring(prefix.length).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
}

/// One entry per generated flashcard level, in introduction order: the
/// number of leading words from [words] still visible at that level. Built
/// by walking [words] from the end, grouping each trailing run of
/// insignificant (<[_significantLetterCount]-letter) words together with the
/// next significant word before it, so a level boundary never falls right
/// after an insignificant filler word. The final entry is always `0` — every
/// word removed, leaving just the line's leading punctuation (if any).
List<int> _keepCounts(List<String> words) {
  bool significant(String w) => _letterCount(w) >= _significantLetterCount;
  final keepCounts = <int>[];
  var i = words.length;
  while (i > 0) {
    var j = i - 1;
    while (j > 0 && !significant(words[j])) {
      j--;
    }
    i = j;
    keepCounts.add(i);
  }
  return keepCounts;
}

/// The number of flashcard levels generatable from [text] — 0 if its first
/// non-empty line has no words at all.
int levelCount(String text) {
  final words = _words(firstNonEmptyLine(text));
  return words.isEmpty ? 0 : _keepCounts(words).length;
}

/// The front/back pair for [text] at [level] (clamped to the last level if
/// out of range). Front replaces everything from [level]'s cut point
/// onward in the first non-empty line with "..."; back is [text] unchanged.
({String front, String back}) render(String text, int level) {
  final lines = text.split('\n');
  final firstIdx = lines.indexWhere((l) => l.trim().isNotEmpty);
  if (firstIdx == -1) return (front: text, back: text);

  final line = lines[firstIdx];
  final prefix = _leadingPrefix(line);
  final words = _words(line);
  if (words.isEmpty) return (front: text, back: text);

  final keepCounts = _keepCounts(words);
  final keep = keepCounts[level.clamp(0, keepCounts.length - 1)];
  final kept = words.take(keep).join(' ');
  final truncated = '$prefix$kept${keep > 0 ? ' ' : ''}...';

  final frontLines = [...lines]..[firstIdx] = truncated;
  return (front: frontLines.join('\n'), back: text);
}

Map<String, dynamic> _progress(NoteFile note) =>
    (note['memorizeProgress'] as Map<String, dynamic>?) ?? const {};

fsrs.Card _cardAt(NoteFile note, int level) =>
    fsrs.Card.fromMap(_progress(note)['$level'] as Map<String, dynamic>);

/// Every level of [note] that has been introduced (has fsrs data) at least
/// once — independent of whether it's currently due.
Iterable<int> introducedLevels(NoteFile note) => _progress(note).keys.map(int.parse);

/// [note]'s next due date for [level], or null if [level] hasn't been
/// introduced yet.
DateTime? dueDateForLevel(NoteFile note, int level) {
  if (!_progress(note).containsKey('$level')) return null;
  return _cardAt(note, level).due;
}

/// The predicted probability [note] would be correctly recalled at [level]
/// right now (0 if [level] hasn't been introduced yet, or was introduced but
/// never actually rated).
double retrievability(NoteFile note, int level, {DateTime? at}) {
  if (!_progress(note).containsKey('$level')) return 0;
  return _scheduler.getCardRetrievability(_cardAt(note, level), currentDateTime: at);
}

/// The next level of [note] eligible to be introduced as a new flashcard:
/// the first level with no fsrs data yet, gated on the level before it (if
/// any) currently having >=[unlockRetrievabilityThreshold] retrievability.
/// Null when [note]'s quote text has no levels at all, every level has
/// already been introduced, or the most recently introduced level hasn't
/// cleared the retrievability gate yet.
int? nextUnlockableLevel(NoteFile note, {DateTime? at}) {
  final total = levelCount(note['title'] as String? ?? '');
  if (total == 0) return null;

  final progress = _progress(note);
  var level = 0;
  while (progress.containsKey('$level')) {
    level++;
  }
  if (level >= total) return null;
  if (level == 0) return 0;
  return retrievability(note, level - 1, at: at) >= unlockRetrievabilityThreshold ? level : null;
}

/// Stamps a freshly-created fsrs card for [level] onto [note], for the "I
/// will remember" action on a brand-new quote-level flashcard. [level] must
/// not already be in [note]'s `memorizeProgress`.
Future<NoteFile> initializeLevel(NoteFile note, int level) async {
  final card = await fsrs.Card.create();
  return {
    ...note,
    'memorizeProgress': {..._progress(note), '$level': card.toMap()},
  };
}

/// Grades [note]'s existing card for [level] with [rating], returning the
/// note with its updated `memorizeProgress`. [level] must already be in
/// [note]'s `memorizeProgress`.
NoteFile reviewLevel(NoteFile note, int level, fsrs.Rating rating) {
  final review = _scheduler.reviewCard(_cardAt(note, level), rating);
  return {
    ...note,
    'memorizeProgress': {..._progress(note), '$level': review.card.toMap()},
  };
}
