import '../models/note_file.dart';

/// The only file that knows the raw field shapes behind an `audio` note's
/// Listen-flow scheduling — everything else works with plain [NoteFile] maps.
/// Mirrors `lib/services/prompt_service.dart`'s shape: plain functions over a
/// note and the current time, no shared state.

/// Whether [note] is permanently or temporarily excluded from the Listen
/// flow at [now]: `neverListen` is true, or `hiddenUntil` parses and is still
/// in the future. Unlike [listenedToday], this is never relaxed by a
/// fallback — a hidden note stays hidden even if nothing else is eligible.
bool isHidden(NoteFile note, DateTime now) {
  if (note['neverListen'] == true) return true;
  final hiddenUntil = DateTime.tryParse((note['hiddenUntil'] as String?) ?? '');
  return hiddenUntil != null && hiddenUntil.isAfter(now);
}

/// Whether [note] was last played on the same calendar day as [now].
bool listenedToday(NoteFile note, DateTime now) {
  final last = DateTime.tryParse((note['lastListenedAt'] as String?) ?? '');
  if (last == null) return false;
  return last.year == now.year && last.month == now.month && last.day == now.day;
}

/// Stamps [note] as having just become the current track.
NoteFile markListenedNow(NoteFile note, DateTime now) {
  return {...note, 'lastListenedAt': now.toIso8601String()};
}

/// Hides [note] from the Listen flow until [days] days from [now].
NoteFile hideForDays(NoteFile note, DateTime now, int days) {
  return {...note, 'hiddenUntil': now.add(Duration(days: days)).toIso8601String()};
}

/// Hides [note] from the Listen flow until [months] months from [now],
/// following Dart's normal month/year rollover (e.g. October + 2 -> December,
/// November + 2 -> next January).
NoteFile hideForMonths(NoteFile note, DateTime now, int months) {
  final until = DateTime(now.year, now.month + months, now.day, now.hour, now.minute, now.second);
  return {...note, 'hiddenUntil': until.toIso8601String()};
}

/// Hides [note] from the Listen flow until [years] years from [now].
NoteFile hideForYears(NoteFile note, DateTime now, int years) {
  final until = DateTime(now.year + years, now.month, now.day, now.hour, now.minute, now.second);
  return {...note, 'hiddenUntil': until.toIso8601String()};
}

/// Permanently excludes [note] from the Listen flow.
NoteFile markNeverListen(NoteFile note) {
  return {...note, 'neverListen': true};
}

/// The by-tag filter's combinator, matching the audio spec's dropdown.
enum TagFilterMode { or, and, not }

/// Whether [note] passes the by-tag filter: [filterTags] empty means no
/// restriction (matches everything) regardless of [mode] — otherwise, `or`
/// matches a note with any of [filterTags], `and` matches a note with all of
/// them, `not` matches a note with none of them.
bool matchesTagFilter(NoteFile note, TagFilterMode mode, Set<String> filterTags) {
  if (filterTags.isEmpty) return true;
  final tags = note.stringList('tags').toSet();
  return switch (mode) {
    TagFilterMode.or => tags.intersection(filterTags).isNotEmpty,
    TagFilterMode.and => filterTags.every(tags.contains),
    TagFilterMode.not => tags.intersection(filterTags).isEmpty,
  };
}
