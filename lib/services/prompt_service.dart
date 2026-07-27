import '../models/note_file.dart';

/// The only file that knows the raw field shapes behind a `primaryType:
/// "prompt"` note's scheduling — everything else works with plain [NoteFile]
/// maps. Ports habit-prompter's fixed-interval due-check/answer-recording
/// algorithm: a prompt with no `lastShownAt` is always due; otherwise it's
/// due once at least `interval` calendar days have passed since
/// `lastShownAt`. Answering appends to `answers` and stamps `lastShownAt`.

/// [note]'s configured re-ask interval in days, parsed leniently from its
/// (string) `interval` field. Missing or unparsable values, and values below
/// 1, fall back to 1 — so a freshly created prompt (empty `interval`) is due
/// daily until the user sets a real value.
int intervalDays(NoteFile note) {
  final parsed = int.tryParse((note['interval'] as String?) ?? '');
  return (parsed == null || parsed < 1) ? 1 : parsed;
}

/// The last time [note]'s answer was recorded, or null if it's never been
/// answered.
DateTime? lastShownAt(NoteFile note) {
  final raw = note['lastShownAt'] as String?;
  return raw == null ? null : DateTime.tryParse(raw);
}

/// Whether [note] is due to be shown in the Prompts flow at [now]: never
/// answered, or at least [intervalDays] calendar days have passed since
/// [lastShownAt].
bool isDuePrompt(NoteFile note, DateTime now) {
  final last = lastShownAt(note);
  if (last == null) return true;
  final today = DateTime(now.year, now.month, now.day);
  final lastDay = DateTime(last.year, last.month, last.day);
  return today.difference(lastDay).inDays >= intervalDays(note);
}

/// Records an answer for [note]: appends `{text, createdAt: now}` to
/// `answers` and stamps `lastShownAt = now`, returning the updated note.
NoteFile recordAnswer(NoteFile note, String text, DateTime now) {
  final answers = (note['answers'] as List?)?.whereType<Map>().toList() ?? [];
  return {
    ...note,
    'answers': [
      ...answers,
      {'text': text, 'createdAt': now.toIso8601String()},
    ],
    'lastShownAt': now.toIso8601String(),
  };
}
