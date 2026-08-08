import 'package:flutter_test/flutter_test.dart';
import 'package:the_system/services/quote_flashcard_service.dart' as quote_service;

void main() {
  group('levelCount / render', () {
    // This is what lives in a quote note's `title` — quote text on the
    // first line, attribution below (see docs/adding-a-primary-type.md).
    const text = 'Everything worth doing is worth doing well.\n\n'
        '— proverb about effort and devotion';

    test('groups the short "is" with the significant word before it', () {
      // Everything(sig) worth(sig) doing(sig) is(short) worth(sig) doing(sig) well.(sig)
      // -> 6 levels, not 7: "is" never gets its own removal step.
      expect(quote_service.levelCount(text), 6);
    });

    test('level 0 removes just the last word', () {
      final result = quote_service.render(text, 0);
      expect(
        result.front,
        'Everything worth doing is worth doing ...\n\n— proverb about effort and devotion',
      );
      expect(result.back, text);
    });

    test('level 1 removes the last two words', () {
      final result = quote_service.render(text, 1);
      expect(
        result.front,
        'Everything worth doing is worth ...\n\n— proverb about effort and devotion',
      );
    });

    test('level 2 removes the last two words (leaving "is" still hanging off the end)', () {
      final result = quote_service.render(text, 2);
      expect(result.front.split('\n').first, 'Everything worth doing is ...');
    });

    test('level 3 removes "doing is" together (short word folded into its neighbor)', () {
      final result = quote_service.render(text, 3);
      expect(result.front.split('\n').first, 'Everything worth ...');
    });

    test('level 4 keeps only the first word', () {
      final result = quote_service.render(text, 4);
      expect(result.front.split('\n').first, 'Everything ...');
    });

    test('final level keeps only leading punctuation before "..."', () {
      final result = quote_service.render(text, 5);
      expect(result.front.split('\n').first, '...');
    });

    test('preserves a leading non-alphanumeric prefix through every level', () {
      const prefixed = '> Everything worth doing well.';
      expect(quote_service.render(prefixed, 0).front, '> Everything worth doing ...');
      final lastLevel = quote_service.levelCount(prefixed) - 1;
      expect(quote_service.render(prefixed, lastLevel).front, '> ...');
    });

    test('a first line with no words at all has zero levels', () {
      expect(quote_service.levelCount('...\n\nattribution'), 0);
    });
  });

  group('nextUnlockableLevel', () {
    Map<String, dynamic> noteWithProgress(Map<String, Map<String, dynamic>> progress) => {
          'primaryType': 'quote',
          'title': 'Everything worth doing is worth doing well.',
          'memorize': true,
          if (progress.isNotEmpty) 'memorizeProgress': progress,
        };

    fsrsCard({required String due, String? lastReview, double? stability}) => {
          'cardId': 1,
          'state': 2,
          'step': null,
          'stability': stability,
          'difficulty': 4.1,
          'due': due,
          'lastReview': lastReview,
        };

    test('level 0 is unlockable for a freshly memorize-flagged quote', () {
      final note = noteWithProgress({});
      expect(quote_service.nextUnlockableLevel(note), 0);
    });

    test('level 1 is locked while level 0 has never been reviewed', () {
      final note = noteWithProgress({
        '0': fsrsCard(due: '2026-08-08T00:00:00.000Z'),
      });
      expect(quote_service.nextUnlockableLevel(note), isNull);
    });

    test('level 1 unlocks once level 0 has high current retrievability', () {
      final now = DateTime.parse('2026-08-08T00:00:05.000Z');
      final note = noteWithProgress({
        '0': fsrsCard(
          due: '2026-08-09T00:00:00.000Z',
          lastReview: '2026-08-08T00:00:00.000Z',
          stability: 10.0,
        ),
      });
      expect(quote_service.nextUnlockableLevel(note, at: now), 1);
    });

    test('level 1 stays locked once level 0 has decayed below the threshold', () {
      final farFuture = DateTime.parse('2026-09-08T00:00:00.000Z');
      final note = noteWithProgress({
        '0': fsrsCard(
          due: '2026-08-09T00:00:00.000Z',
          lastReview: '2026-08-08T00:00:00.000Z',
          stability: 10.0,
        ),
      });
      expect(quote_service.nextUnlockableLevel(note, at: farFuture), isNull);
    });

    test('no further level is offered once every level has been introduced', () {
      final total = quote_service.levelCount(noteWithProgress({})['title'] as String);
      final progress = {
        for (var i = 0; i < total; i++)
          '$i': fsrsCard(
            due: '2026-08-09T00:00:00.000Z',
            lastReview: '2026-08-08T00:00:00.000Z',
            stability: 10.0,
          ),
      };
      final note = noteWithProgress(progress);
      expect(quote_service.nextUnlockableLevel(note), isNull);
    });
  });
}
