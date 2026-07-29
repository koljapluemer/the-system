import 'package:flutter_test/flutter_test.dart';
import 'package:the_system/models/note_index.dart';
import 'package:the_system/services/json_schema_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const service = JsonSchemaService();

  group('findInvalid', () {
    test('accepts a well-formed activity note with rels and triaged', () async {
      final index = NoteIndex(entries: {
        'b.json': {
          'primaryType': 'activity',
          'title': 'B',
          'content': 'body text',
          'rels': [
            ['inspired by', 'other.json'],
          ],
          'triaged': 'true',
        },
      });
      final result = await service.findInvalid(index);
      expect(result, isNot(contains('b.json')));
    });

    test('accepts a rels entry with a third mirrorLabel element', () async {
      final index = NoteIndex(entries: {
        'b2.json': {
          'primaryType': 'activity',
          'title': 'B2',
          'content': 'body text',
          'rels': [
            ['inspired by', 'other.json', 'inspires'],
          ],
        },
      });
      final result = await service.findInvalid(index);
      expect(result, isNot(contains('b2.json')));
    });

    test('accepts a well-formed art note', () async {
      final index = NoteIndex(entries: {
        'c.json': {
          'primaryType': 'art',
          'title': 'C',
          'content': 'some content',
          'image': 'c.webp',
        },
      });
      final result = await service.findInvalid(index);
      expect(result, isNot(contains('c.json')));
    });

    test('accepts a well-formed milestone note with a valid secondaryType', () async {
      final index = NoteIndex(entries: {
        'm.json': {'primaryType': 'milestone', 'title': 'M', 'content': 'ship it', 'secondaryType': 'open'},
      });
      final result = await service.findInvalid(index);
      expect(result, isNot(contains('m.json')));
    });

    test('flags a milestone note with an invalid secondaryType value', () async {
      final index = NoteIndex(entries: {
        'n.json': {'primaryType': 'milestone', 'title': 'N', 'secondaryType': 'somewhat'},
      });
      final result = await service.findInvalid(index);
      expect(result, contains('n.json'));
    });

    test('flags an art note missing the required content field', () async {
      final index = NoteIndex(entries: {
        'd.json': {'primaryType': 'art', 'title': 'D'},
      });
      final result = await service.findInvalid(index);
      expect(result, contains('d.json'));
    });

    test('accepts a well-formed milestone note with logs entries', () async {
      final index = NoteIndex(entries: {
        'log1.json': {
          'primaryType': 'milestone',
          'title': 'Checked in',
          'logs': [
            {'content': 'still going', 'createdAt': '2026-07-13T10:30:00.000'},
          ],
        },
      });
      final result = await service.findInvalid(index);
      expect(result, isNot(contains('log1.json')));
    });

    test('flags a milestone note with a log entry missing createdAt', () async {
      final index = NoteIndex(entries: {
        'log2.json': {
          'primaryType': 'milestone',
          'title': 'Checked in',
          'logs': [
            {'content': 'still going'},
          ],
        },
      });
      final result = await service.findInvalid(index);
      expect(result, contains('log2.json'));
    });

    test('accepts a well-formed new flashcard note with no fsrs data yet', () async {
      final index = NoteIndex(entries: {
        'fc1.json': {
          'primaryType': 'flashcard',
          'title': 'Capital of France',
          'front': 'What is the capital of France?',
          'back': 'Paris',
        },
      });
      final result = await service.findInvalid(index);
      expect(result, isNot(contains('fc1.json')));
    });

    test('accepts a well-formed flashcard note with fsrs learning data', () async {
      final index = NoteIndex(entries: {
        'fc2.json': {
          'primaryType': 'flashcard',
          'title': 'Capital of Japan',
          'front': 'What is the capital of Japan?',
          'back': 'Tokyo',
          'fsrs': {
            'cardId': 1,
            'state': 2,
            'step': null,
            'stability': 5.2,
            'difficulty': 4.1,
            'due': '2026-07-20T10:30:00.000Z',
            'lastReview': '2026-07-14T10:30:00.000Z',
          },
        },
      });
      final result = await service.findInvalid(index);
      expect(result, isNot(contains('fc2.json')));
    });

    test('flags a flashcard note missing the required back field', () async {
      final index = NoteIndex(entries: {
        'fc3.json': {
          'primaryType': 'flashcard',
          'title': 'Incomplete',
          'front': 'Only a front',
        },
      });
      final result = await service.findInvalid(index);
      expect(result, contains('fc3.json'));
    });

    test('flags a flashcard note with unexpected extra fields', () async {
      final index = NoteIndex(entries: {
        'fc4.json': {
          'primaryType': 'flashcard',
          'title': 'Extra',
          'front': 'front',
          'back': 'back',
          'unexpected': 'field',
        },
      });
      final result = await service.findInvalid(index);
      expect(result, contains('fc4.json'));
    });

    test('accepts a well-formed new prompt note with no interval/answers yet', () async {
      final index = NoteIndex(entries: {
        'p1.json': {'primaryType': 'prompt', 'title': 'Did you stretch today?'},
      });
      final result = await service.findInvalid(index);
      expect(result, isNot(contains('p1.json')));
    });

    test('accepts a well-formed prompt note with interval, lastShownAt, and answers', () async {
      final index = NoteIndex(entries: {
        'p2.json': {
          'primaryType': 'prompt',
          'title': 'Did you stretch today?',
          'interval': '3',
          'lastShownAt': '2026-07-20T10:30:00.000Z',
          'answers': [
            {'text': 'yes', 'createdAt': '2026-07-20T10:30:00.000Z'},
          ],
        },
      });
      final result = await service.findInvalid(index);
      expect(result, isNot(contains('p2.json')));
    });

    test('flags a prompt note with an answer entry missing createdAt', () async {
      final index = NoteIndex(entries: {
        'p3.json': {
          'primaryType': 'prompt',
          'title': 'Did you stretch today?',
          'answers': [
            {'text': 'yes'},
          ],
        },
      });
      final result = await service.findInvalid(index);
      expect(result, contains('p3.json'));
    });

    test('flags a prompt note with unexpected extra fields', () async {
      final index = NoteIndex(entries: {
        'p4.json': {
          'primaryType': 'prompt',
          'title': 'Did you stretch today?',
          'unexpected': 'field',
        },
      });
      final result = await service.findInvalid(index);
      expect(result, contains('p4.json'));
    });

    test('accepts a well-formed block note', () async {
      final index = NoteIndex(entries: {
        'blk1.json': {
          'primaryType': 'block',
          'title': 'Write the report',
          'createdAt': '2026-07-28T10:30:00.000Z',
        },
      });
      final result = await service.findInvalid(index);
      expect(result, isNot(contains('blk1.json')));
    });

    test('flags a block note missing the required createdAt field', () async {
      final index = NoteIndex(entries: {
        'blk2.json': {'primaryType': 'block', 'title': 'Write the report'},
      });
      final result = await service.findInvalid(index);
      expect(result, contains('blk2.json'));
    });

    test('flags a block note with unexpected extra fields', () async {
      final index = NoteIndex(entries: {
        'blk3.json': {
          'primaryType': 'block',
          'title': 'Write the report',
          'createdAt': '2026-07-28T10:30:00.000Z',
          'unexpected': 'field',
        },
      });
      final result = await service.findInvalid(index);
      expect(result, contains('blk3.json'));
    });

    test('accepts a well-formed frog note', () async {
      final index = NoteIndex(entries: {
        'frog1.json': {'primaryType': 'frog', 'title': 'Call the dentist'},
      });
      final result = await service.findInvalid(index);
      expect(result, isNot(contains('frog1.json')));
    });

    test('flags a frog note missing the required title field', () async {
      final index = NoteIndex(entries: {
        'frog2.json': {'primaryType': 'frog'},
      });
      final result = await service.findInvalid(index);
      expect(result, contains('frog2.json'));
    });

    test('accepts a well-formed audio note with tags and an audioFile', () async {
      final index = NoteIndex(entries: {
        'aud1.json': {
          'primaryType': 'audio',
          'title': 'Episode 42',
          'content': 'Notes about the episode',
          'audioFile': 'episode-42-ab12cd.mp3',
          'tags': ['podcast', 'tech'],
          'lastListenedAt': '2026-07-20T10:30:00.000Z',
          'hiddenUntil': null,
          'neverListen': false,
        },
      });
      final result = await service.findInvalid(index);
      expect(result, isNot(contains('aud1.json')));
    });

    test('accepts a well-formed new audio note with none of the flow-managed fields yet', () async {
      final index = NoteIndex(entries: {
        'aud2.json': {'primaryType': 'audio', 'title': 'Episode 43'},
      });
      final result = await service.findInvalid(index);
      expect(result, isNot(contains('aud2.json')));
    });

    test('flags an audio note missing the required title field', () async {
      final index = NoteIndex(entries: {
        'aud3.json': {'primaryType': 'audio', 'content': 'Notes'},
      });
      final result = await service.findInvalid(index);
      expect(result, contains('aud3.json'));
    });

    test('flags an audio note with unexpected extra fields', () async {
      final index = NoteIndex(entries: {
        'aud4.json': {
          'primaryType': 'audio',
          'title': 'Episode 44',
          'unexpected': 'field',
        },
      });
      final result = await service.findInvalid(index);
      expect(result, contains('aud4.json'));
    });

    test('flags an unknown primaryType', () async {
      final index = NoteIndex(entries: {
        'e.json': {'primaryType': 'contact', 'title': 'E'},
      });
      final result = await service.findInvalid(index);
      expect(result, contains('e.json'));
    });

    test('flags unparsable JSON', () async {
      final index = NoteIndex(unparsable: {'broken.json'});
      final result = await service.findInvalid(index);
      expect(result, contains('broken.json'));
    });

    test('flags unexpected extra fields', () async {
      final index = NoteIndex(entries: {
        'f.json': {
          'primaryType': 'activity',
          'title': 'F',
          'content': 'body text',
          'unexpected': 'field',
        },
      });
      final result = await service.findInvalid(index);
      expect(result, contains('f.json'));
    });

    test('empty index has no invalid files', () async {
      final result = await service.findInvalid(const NoteIndex());
      expect(result, isEmpty);
    });

    test('sorts results', () async {
      final index = NoteIndex(entries: {
        'z.json': {'primaryType': 'contact'},
        'a.json': {'primaryType': 'contact'},
      });
      final result = await service.findInvalid(index);
      expect(result, ['a.json', 'z.json']);
    });
  });
}
