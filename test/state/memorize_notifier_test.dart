import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:the_system/state/memorize_notifier.dart';
import 'package:the_system/state/note_index_notifier.dart';
import 'package:the_system/state/providers.dart';

/// Returns a fixed folder path immediately, so tests don't need a real
/// SharedPreferences platform channel — mirrors note_index_notifier_test.dart.
class _FixedFolderNotifier extends DataFolderNotifier {
  final String folder;
  _FixedFolderNotifier(this.folder);

  @override
  Future<String?> build() async => folder;
}

Map<String, dynamic> fsrsCard({
  required String due,
  String? lastReview,
  double? stability,
  double? difficulty,
  int state = 2, // review
}) =>
    {
      'cardId': 1,
      'state': state,
      'step': null,
      'stability': stability,
      'difficulty': difficulty,
      'due': due,
      'lastReview': lastReview,
    };

void main() {
  late Directory tempDir;
  late ProviderContainer container;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('memorize_notifier_test_');
    container = ProviderContainer(
      overrides: [
        dataFolderProvider.overrideWith(() => _FixedFolderNotifier(tempDir.path)),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> writeFixture(String filename, Map<String, dynamic> content) async {
    await File('${tempDir.path}/$filename').writeAsString(jsonEncode(content));
  }

  /// Loads the index, builds [memorizeProvider], and pumps until its
  /// microtask-scheduled `_loadNext` has settled (loading: false or
  /// something is showing).
  Future<MemorizeState> settle() async {
    await container.read(noteIndexProvider.future);
    container.read(memorizeProvider);
    await pumpEventQueue();
    return container.read(memorizeProvider);
  }

  final past = DateTime.now().toUtc().subtract(const Duration(days: 1)).toIso8601String();
  final farFuture = DateTime.now().toUtc().add(const Duration(days: 30)).toIso8601String();

  test('a flashcard whose fsrs due date is in the future is not offered as due', () async {
    await writeFixture('not-due.json', {
      'primaryType': 'flashcard',
      'title': 'Not due yet',
      'front': 'f',
      'back': 'b',
      'fsrs': fsrsCard(due: farFuture, lastReview: past, stability: 20, difficulty: 3),
    });

    final state = await settle();

    // Nothing due, nothing new, no art notes -> "all caught up", not the
    // not-yet-due card.
    expect(state.loading, isFalse);
    expect(state.currentNote, isNull);
    expect(state.showArtTriage, isFalse);
  });

  test('only the actually-due flashcard is picked when another is not due', () async {
    await writeFixture('due-now.json', {
      'primaryType': 'flashcard',
      'title': 'Due now',
      'front': 'f1',
      'back': 'b1',
      'fsrs': fsrsCard(due: past, lastReview: past, stability: 5, difficulty: 4),
    });
    await writeFixture('not-due.json', {
      'primaryType': 'flashcard',
      'title': 'Not due yet',
      'front': 'f2',
      'back': 'b2',
      'fsrs': fsrsCard(due: farFuture, lastReview: past, stability: 20, difficulty: 3),
    });

    final state = await settle();

    expect(state.currentFilename, 'due-now.json');
  });

  test('grading a due flashcard "easy" pushes its due date out and removes it from the pool', () async {
    await writeFixture('only.json', {
      'primaryType': 'flashcard',
      'title': 'Only',
      'front': 'f',
      'back': 'b',
      'fsrs': fsrsCard(due: past, lastReview: past, stability: 5, difficulty: 4),
    });

    await settle();
    final notifier = container.read(memorizeProvider.notifier);
    expect(container.read(memorizeProvider).currentFilename, 'only.json');

    notifier.reveal();
    await notifier.rate(fsrs.Rating.easy);
    await pumpEventQueue();

    final state = container.read(memorizeProvider);
    // The just-graded card must not immediately reappear.
    expect(state.currentNote, isNull);
    expect(state.loading, isFalse);

    final updated = container.read(noteIndexProvider).value!.entries['only.json']!;
    final newDue = DateTime.parse((updated['fsrs'] as Map)['due'] as String);
    expect(newDue.isAfter(DateTime.now().toUtc().add(const Duration(days: 1))), isTrue);
  });

  test('a fresh memorize-flagged quote surfaces its level-0 flashcard as new', () async {
    await writeFixture('q.json', {
      'primaryType': 'quote',
      'title': 'Everything worth doing is worth doing well.',
      'memorize': true,
      'isCommonplace': false,
    });

    final state = await settle();

    expect(state.currentFilename, 'q.json');
    expect(state.currentLevel, 0);
    expect(state.isNew, isTrue);
    expect(state.revealed, isTrue);
    expect(state.displayFront, 'Everything worth doing is worth doing ...');
  });

  test('a memorize-flagged quote with an empty title never produces a candidate', () async {
    await writeFixture('empty.json', {
      'primaryType': 'quote',
      'title': '',
      'memorize': true,
      'isCommonplace': false,
    });

    final state = await settle();

    expect(state.currentNote, isNull);
    expect(state.loading, isFalse);
  });

  test('a quote with memorize=false never produces a candidate', () async {
    await writeFixture('off.json', {
      'primaryType': 'quote',
      'title': 'Everything worth doing is worth doing well.',
      'memorize': false,
      'isCommonplace': false,
    });

    final state = await settle();

    expect(state.currentNote, isNull);
    expect(state.loading, isFalse);
  });

  test('a fresh quote is preferred over a due flashcard while under the 10% floor', () async {
    await writeFixture('fc.json', {
      'primaryType': 'flashcard',
      'title': 'FC',
      'front': 'f',
      'back': 'b',
      'fsrs': fsrsCard(due: past, lastReview: past, stability: 5, difficulty: 4),
    });
    await writeFixture('q.json', {
      'primaryType': 'quote',
      'title': 'Everything worth doing is worth doing well.',
      'memorize': true,
    });

    final state = await settle();

    expect(state.currentFilename, 'q.json');
    expect(state.currentLevel, 0);
  });

  test('level 1 of a quote is not offered until level 0 has been graded', () async {
    await writeFixture('q.json', {
      'primaryType': 'quote',
      'title': 'Everything worth doing is worth doing well.',
      'memorize': true,
      'memorizeProgress': {
        '0': fsrsCard(due: farFuture, lastReview: null, stability: null, difficulty: null, state: 1),
      },
    });

    final state = await settle();

    // Level 0 was introduced but never actually rated (lastReview null ->
    // retrievability 0), so level 1 must stay locked and nothing is due.
    expect(state.currentNote, isNull);
    expect(state.loading, isFalse);
  });

  test('level 1 of a quote becomes available once level 0 is well-retained', () async {
    final justNow = DateTime.now().toUtc().subtract(const Duration(seconds: 1)).toIso8601String();
    await writeFixture('q.json', {
      'primaryType': 'quote',
      'title': 'Everything worth doing is worth doing well.',
      'memorize': true,
      'memorizeProgress': {
        '0': fsrsCard(due: farFuture, lastReview: justNow, stability: 20, difficulty: 4),
      },
    });

    final state = await settle();

    expect(state.currentFilename, 'q.json');
    expect(state.currentLevel, 1);
    expect(state.isNew, isTrue);
  });

  test('the repeat-avoidance fallback widens past a throttled-out pool instead of forcing a repeat', () async {
    // Turn 1: nothing shown yet (share 0% < 10% floor) -> the single-level
    // quote (already due) is preferred over the brand-new flashcard.
    await writeFixture('fc-repeat.json', {
      'primaryType': 'flashcard',
      'title': 'Repeat-prone',
      'front': 'f',
      'back': 'b',
    });
    await writeFixture('q-a.json', {
      'primaryType': 'quote',
      'title': 'Persist.',
      'memorize': true,
      'memorizeProgress': {
        '0': fsrsCard(due: past, lastReview: past, stability: 5, difficulty: 4),
      },
    });

    await settle();
    final notifier = container.read(memorizeProvider.notifier);
    expect(container.read(memorizeProvider).currentFilename, 'q-a.json');

    // Grade it -> its single level graduates and is retired for good (its
    // due date moves days out, and it has no level 1 to offer).
    notifier.reveal();
    await notifier.rate(fsrs.Rating.good);
    await pumpEventQueue();

    // Turn 2: only the brand-new flashcard is a candidate at all -> it gets
    // shown next.
    expect(container.read(memorizeProvider).currentFilename, 'fc-repeat.json');

    // Before remembering it (which triggers turn 3), introduce a second,
    // untouched due quote. Session share so far is 1 quote / 2 shown = 50%
    // > the 30% ceiling, so quote-based turns are throttled: turn 3's pool
    // restricts to non-quote candidates. fc-repeat is about to get a fresh
    // fsrs card due immediately (a brand-new card's due date defaults to
    // "now"), making it the *only* non-quote candidate — and also the card
    // that was just shown. The picker must widen back out to the full
    // candidate set and pick q-b instead of force-repeating fc-repeat.
    await container.read(noteIndexProvider.notifier).write('q-b.json', {
      'primaryType': 'quote',
      'title': 'Endure.',
      'memorize': true,
      'memorizeProgress': {
        '0': fsrsCard(due: past, lastReview: past, stability: 5, difficulty: 4),
      },
    });
    await notifier.rememberNew();

    final state = container.read(memorizeProvider);
    expect(state.currentFilename, 'q-b.json');
    expect(state.currentLevel, 0);
  });
}
