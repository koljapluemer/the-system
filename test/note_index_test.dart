import 'package:flutter_test/flutter_test.dart';
import 'package:the_system/models/note_index.dart';

void main() {
  group('untriagedOfType', () {
    test('includes notes matching primaryType with no triaged field', () {
      final index = NoteIndex(entries: {
        'a.json': {'primaryType': 'activity', 'title': 'A'},
      });
      expect(index.untriagedOfType('activity'), contains('a.json'));
    });

    test('excludes notes already triaged "true"', () {
      final index = NoteIndex(entries: {
        'b.json': {'primaryType': 'activity', 'triaged': 'true'},
      });
      expect(index.untriagedOfType('activity'), isNot(contains('b.json')));
    });

    test('excludes notes with a different primaryType', () {
      final index = NoteIndex(entries: {
        'c.json': {'primaryType': 'art'},
      });
      expect(index.untriagedOfType('activity'), isNot(contains('c.json')));
    });
  });

  group('summariesOfType', () {
    test('includes notes matching primaryType regardless of triaged status', () {
      final index = NoteIndex(entries: {
        's1.json': {'primaryType': 'activity', 'triaged': 'true', 'title': 'S1'},
        's2.json': {'primaryType': 'activity', 'title': 'S2'},
      });
      final filenames = index.summariesOfType('activity').map((s) => s.filename);
      expect(filenames, containsAll(['s1.json', 's2.json']));
    });

    test('excludes notes with a different primaryType', () {
      final index = NoteIndex(entries: {
        'd.json': {'primaryType': 'art', 'title': 'D'},
      });
      expect(index.summariesOfType('activity'), isEmpty);
    });

    test('carries filename and title through', () {
      final index = NoteIndex(entries: {
        's.json': {'primaryType': 'activity', 'title': 'Some Title'},
      });
      final summary = index.summariesOfType('activity').first;
      expect(summary.filename, 's.json');
      expect(summary.title, 'Some Title');
    });

    test('defaults title to empty string when missing', () {
      final index = NoteIndex(entries: {
        'notitle.json': {'primaryType': 'activity'},
      });
      expect(index.summariesOfType('activity').first.title, '');
    });

    test('carries secondaryType through', () {
      final index = NoteIndex(entries: {
        'h1.json': {'primaryType': 'milestone', 'title': 'H1', 'secondaryType': 'open'},
      });
      expect(index.summariesOfType('milestone').first.secondaryType, 'open');
    });

    test('defaults secondaryType to null when missing', () {
      final index = NoteIndex(entries: {
        'h2.json': {'primaryType': 'milestone', 'title': 'H2'},
      });
      expect(index.summariesOfType('milestone').first.secondaryType, isNull);
    });
  });
}
