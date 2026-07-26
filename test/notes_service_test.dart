import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:the_system/services/notes_service.dart';

void main() {
  late Directory tempDir;
  const service = NotesService();

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('notes_service_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> writeFixture(String filename, Map<String, dynamic> content) async {
    await File('${tempDir.path}/$filename').writeAsString(jsonEncode(content));
  }

  group('scanNotes', () {
    test('yields decoded content for a well-formed note', () async {
      await writeFixture('a.json', {'primaryType': 'activity', 'title': 'A'});
      final result = await service.scanNotes(tempDir.path).toList();
      final entry = result.firstWhere((r) => r.filename == 'a.json');
      expect(entry.data, {'primaryType': 'activity', 'title': 'A'});
    });

    test('yields every file regardless of primaryType', () async {
      await writeFixture('b.json', {'primaryType': 'contact'});
      final result = await service.scanNotes(tempDir.path).toList();
      expect(result.map((r) => r.filename), contains('b.json'));
    });

    test('yields null data for unparsable json files, without throwing', () async {
      await File('${tempDir.path}/broken.json').writeAsString('{not json');
      final result = await service.scanNotes(tempDir.path).toList();
      final entry = result.firstWhere((r) => r.filename == 'broken.json');
      expect(entry.data, isNull);
    });

    test('yields null data for json that decodes to a non-object', () async {
      await File('${tempDir.path}/list.json').writeAsString('[1, 2, 3]');
      final result = await service.scanNotes(tempDir.path).toList();
      final entry = result.firstWhere((r) => r.filename == 'list.json');
      expect(entry.data, isNull);
    });

    test('ignores non-json files', () async {
      await File('${tempDir.path}/notes.txt').writeAsString('hello');
      final result = await service.scanNotes(tempDir.path).toList();
      expect(result.map((r) => r.filename), isNot(contains('notes.txt')));
    });

    test('finds every file across multiple concurrency batches, none dropped', () async {
      const total = 90;
      for (var i = 0; i < total; i++) {
        await writeFixture('n$i.json', {'primaryType': 'activity', 'title': 'N$i'});
      }
      // concurrency (32) doesn't evenly divide total, exercising a partial final batch too.
      final result = await service.scanNotes(tempDir.path, concurrency: 32).toList();
      expect(result.length, total);
      expect(
        result.map((r) => r.filename).toSet(),
        {for (var i = 0; i < total; i++) 'n$i.json'},
      );
    });
  });

  group('writeJsonFile', () {
    test('writes triaged as the literal string "true", not a boolean', () async {
      await writeFixture('d.json', {'primaryType': 'activity'});
      final note = await service.readJsonFile(tempDir.path, 'd.json');
      await service.writeJsonFile(tempDir.path, 'd.json', {...note, 'triaged': 'true'});

      final raw = await File('${tempDir.path}/d.json').readAsString();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      expect(decoded['triaged'], 'true');
      expect(decoded['triaged'], isA<String>());
    });

    test('preserves the rels field untouched through a write', () async {
      final rels = [
        ['source', 'some-file.json'],
      ];
      await writeFixture('e.json', {'primaryType': 'activity', 'rels': rels});
      final note = await service.readJsonFile(tempDir.path, 'e.json');
      await service.writeJsonFile(tempDir.path, 'e.json', {...note, 'triaged': 'true'});

      final reloaded = await service.readJsonFile(tempDir.path, 'e.json');
      expect(reloaded['rels'], [
        ['source', 'some-file.json'],
      ]);
    });

    test('preserves a 3-element rels entry (with mirrorLabel) untouched through a write', () async {
      final rels = [
        ['inspired by', 'some-file.json', 'inspires'],
      ];
      await writeFixture('e2.json', {'primaryType': 'activity', 'rels': rels});
      final note = await service.readJsonFile(tempDir.path, 'e2.json');
      await service.writeJsonFile(tempDir.path, 'e2.json', {...note, 'triaged': 'true'});

      final reloaded = await service.readJsonFile(tempDir.path, 'e2.json');
      expect(reloaded['rels'], [
        ['inspired by', 'some-file.json', 'inspires'],
      ]);
    });
  });

  group('createNote', () {
    test('writes the given content under a filename slugified from slugSource', () async {
      final filename = await service.createNote(
        tempDir.path,
        {'primaryType': 'milestone', 'title': 'Something else', 'secondaryType': 'open'},
        slugSource: 'Buy Milk!! 2%',
      );
      expect(filename, matches(RegExp(r'^buy-milk-2-[0-9a-z]{6}\.json$')));
      final note = await service.readJsonFile(tempDir.path, filename);
      expect(note['primaryType'], 'milestone');
      expect(note['title'], 'Something else');
    });

    test('two notes with the same slugSource get different filenames', () async {
      final a = await service.createNote(tempDir.path, {'primaryType': 'milestone'},
          slugSource: 'Same');
      final b = await service.createNote(tempDir.path, {'primaryType': 'milestone'},
          slugSource: 'Same');
      expect(a, isNot(b));
    });

    test('truncates very long slugSource so the filename stays within OS limits', () async {
      final longTitle = List.filled(40, 'word').join(' '); // 199 chars
      final filename =
          await service.createNote(tempDir.path, {'primaryType': 'activity'}, slugSource: longTitle);
      expect(filename.length, lessThan(100));
      expect(filename, matches(RegExp(r'^[a-z0-9-]+-[0-9a-z]{6}\.json$')));
      expect(filename.contains('--'), isFalse);
      final note = await service.readJsonFile(tempDir.path, filename);
      expect(note['primaryType'], 'activity');
    });
  });

  group('deleteJsonFile', () {
    test('removes the file from disk', () async {
      await writeFixture('f.json', {'primaryType': 'activity'});
      await service.deleteJsonFile(tempDir.path, 'f.json');
      expect(await File('${tempDir.path}/f.json').exists(), isFalse);
    });
  });

  group('filename traversal guard', () {
    test('rejects filenames containing ".."', () {
      expect(
        () => service.readJsonFile(tempDir.path, '../evil.json'),
        throwsArgumentError,
      );
    });

    test('rejects filenames containing "/"', () {
      expect(
        () => service.writeJsonFile(tempDir.path, 'sub/file.json', {}),
        throwsArgumentError,
      );
    });

    test(r'rejects filenames containing "\"', () {
      expect(
        () => service.deleteJsonFile(tempDir.path, r'a\b.json'),
        throwsArgumentError,
      );
    });
  });
}
