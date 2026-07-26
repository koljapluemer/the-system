import 'package:flutter_test/flutter_test.dart';
import 'package:the_system/models/note_file.dart';
import 'package:the_system/models/note_search.dart';

void main() {
  final entries = <String, NoteFile>{
    'skepticism.json': {'primaryType': 'art', 'title': 'Skepticism'},
    'other-art.json': {'primaryType': 'art', 'title': 'Completely unrelated title'},
    'milestone-note.json': {'primaryType': 'milestone', 'title': 'Skepticism'},
    'aliased.json': {
      'primaryType': 'activity',
      'title': 'Something else entirely',
      'aliases': ['Skepticism'],
    },
  };
  final notes = normalizeNotes(entries);

  test('exact title match ranks first', () {
    final matches = findSimilarNotes(
      notes,
      query: 'Skepticism',
      allowedPrimaryTypes: ['art', 'milestone', 'activity'],
    );

    expect(matches.first.filename, 'skepticism.json');
  });

  test('tolerates a typo via edit-distance similarity', () {
    final matches = findSimilarNotes(
      notes,
      query: 'Scepticism',
      allowedPrimaryTypes: ['art'],
    );

    expect(matches.map((m) => m.filename), contains('skepticism.json'));
  });

  test('matches on aliases, not just title', () {
    final matches = findSimilarNotes(
      notes,
      query: 'Skepticism',
      allowedPrimaryTypes: ['activity'],
    );

    expect(matches.map((m) => m.filename), contains('aliased.json'));
  });

  test('respects allowedPrimaryTypes', () {
    final matches = findSimilarNotes(
      notes,
      query: 'Skepticism',
      allowedPrimaryTypes: ['art'],
    );

    expect(matches.map((m) => m.filename), isNot(contains('milestone-note.json')));
  });

  test('unrelated titles are excluded', () {
    final matches = findSimilarNotes(
      notes,
      query: 'Skepticism',
      allowedPrimaryTypes: ['art'],
    );

    expect(matches.map((m) => m.filename), isNot(contains('other-art.json')));
  });

  test('respects limit', () {
    final manyEntries = <String, NoteFile>{
      for (var i = 0; i < 10; i++) 'note-$i.json': {'primaryType': 'art', 'title': 'Topic $i'},
    };

    final matches = findSimilarNotes(
      normalizeNotes(manyEntries),
      query: 'Topic',
      allowedPrimaryTypes: ['art'],
      limit: 3,
    );

    expect(matches.length, 3);
  });

  test('empty query returns no matches', () {
    final matches = findSimilarNotes(notes, query: '', allowedPrimaryTypes: ['art']);
    expect(matches, isEmpty);
  });
}
