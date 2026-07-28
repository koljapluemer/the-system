import 'dart:math';

import 'package:intl/intl.dart';

import '../models/note_file.dart';

/// The only file that knows the Frog flow's day-boundary and pick-selection
/// rules — everything else works with plain [NoteFile] maps. Ports the
/// `frog` app's daily-single-pick algorithm: a "day" runs from 4am to 4am
/// (so a late-night session still counts as the same day), and each day
/// surfaces one random frog from the pool, avoiding a repeat of the
/// previous day's pick when another candidate exists.

final _dayKeyFormat = DateFormat('yyyy-MM-dd');

/// The logical day key for [now], shifted back 4 hours so the calendar day
/// rolls over at 4am rather than midnight — e.g. 3:59am is still
/// "yesterday", 4:00am is already "today".
String dayKeyFor(DateTime now) {
  final shifted = now.subtract(const Duration(hours: 4));
  return _dayKeyFormat.format(shifted);
}

/// Picks a uniformly random entry from [pool], excluding [excludeFilename]
/// when doing so would still leave at least one candidate — falling back to
/// the full [pool] otherwise (e.g. when it's the only frog left). [pool]
/// must be non-empty.
MapEntry<String, NoteFile> pickFrog(
  List<MapEntry<String, NoteFile>> pool, {
  String? excludeFilename,
  Random? random,
}) {
  final withoutExcluded = excludeFilename == null
      ? pool
      : [for (final e in pool) if (e.key != excludeFilename) e];
  final candidates = withoutExcluded.isNotEmpty ? withoutExcluded : pool;
  final rng = random ?? Random();
  return candidates[rng.nextInt(candidates.length)];
}
