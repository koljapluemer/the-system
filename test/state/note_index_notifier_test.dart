import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:the_system/models/note_type_spec.dart';
import 'package:the_system/state/note_index_notifier.dart';
import 'package:the_system/state/providers.dart';

/// Returns a fixed folder path immediately, so tests don't need a real
/// SharedPreferences platform channel.
class _FixedFolderNotifier extends DataFolderNotifier {
  final String folder;
  _FixedFolderNotifier(this.folder);

  @override
  Future<String?> build() async => folder;
}

void main() {
  late Directory tempDir;
  late ProviderContainer container;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('note_index_notifier_test_');
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

  test('build scans the folder into entries and unparsable', () async {
    await writeFixture('a.json', {'primaryType': 'activity', 'title': 'A'});
    await File('${tempDir.path}/broken.json').writeAsString('{not json');

    final index = await container.read(noteIndexProvider.future);
    expect(index.entries['a.json'], {'primaryType': 'activity', 'title': 'A'});
    expect(index.unparsable, contains('broken.json'));
  });

  test('write updates both the in-memory entry and the file on disk', () async {
    await container.read(noteIndexProvider.future);
    await container
        .read(noteIndexProvider.notifier)
        .write('new.json', {'primaryType': 'activity', 'title': 'New'});

    final index = container.read(noteIndexProvider).value!;
    expect(index.entries['new.json'], {'primaryType': 'activity', 'title': 'New'});

    final onDisk = jsonDecode(await File('${tempDir.path}/new.json').readAsString());
    expect(onDisk['title'], 'New');
  });

  test('delete removes both the in-memory entry and the file on disk', () async {
    await writeFixture('gone.json', {'primaryType': 'activity', 'title': 'Gone'});
    await container.read(noteIndexProvider.future);

    await container.read(noteIndexProvider.notifier).delete('gone.json');

    final index = container.read(noteIndexProvider).value!;
    expect(index.entries.containsKey('gone.json'), isFalse);
    expect(await File('${tempDir.path}/gone.json').exists(), isFalse);
  });

  test('createFromSpec creates an open milestone', () async {
    await container.read(noteIndexProvider.future);
    final milestoneSpec = noteTypeSpecs.firstWhere((s) => s.primaryType == 'milestone');

    final filename = await container.read(noteIndexProvider.notifier).createFromSpec(
          milestoneSpec,
          title: 'My Milestone',
          secondaryType: milestoneSpec.defaultSecondaryType,
        );

    final index = container.read(noteIndexProvider).value!;
    expect(index.entries[filename]?['primaryType'], 'milestone');
    expect(index.entries[filename]?['title'], 'My Milestone');
    expect(index.entries[filename]?['secondaryType'], 'open');

    final onDisk = jsonDecode(await File('${tempDir.path}/$filename').readAsString());
    expect(onDisk['secondaryType'], 'open');
  });

  group('attachRelationship', () {
    test('writes both sides with an explicit reverse label', () async {
      await writeFixture('a.json', {'primaryType': 'activity', 'title': 'A'});
      await writeFixture('b.json', {'primaryType': 'activity', 'title': 'B'});
      await container.read(noteIndexProvider.future);

      await container.read(noteIndexProvider.notifier).attachRelationship(
            filename: 'a.json',
            label: 'inspired by',
            reverseLabel: 'inspires',
            relatedFilename: 'b.json',
          );

      final index = container.read(noteIndexProvider).value!;
      expect(index.entries['a.json']?['rels'], [
        ['inspired by', 'b.json', 'inspires'],
      ]);
      expect(index.entries['b.json']?['rels'], [
        ['inspires', 'a.json', 'inspired by'],
      ]);
    });

    test('defaults the reverse label to "backlink" when omitted', () async {
      await writeFixture('a.json', {'primaryType': 'activity', 'title': 'A'});
      await writeFixture('b.json', {'primaryType': 'activity', 'title': 'B'});
      await container.read(noteIndexProvider.future);

      await container.read(noteIndexProvider.notifier).attachRelationship(
            filename: 'a.json',
            label: 'seeAlso',
            relatedFilename: 'b.json',
          );

      final index = container.read(noteIndexProvider).value!;
      expect(index.entries['b.json']?['rels'], [
        ['backlink', 'a.json', 'seeAlso'],
      ]);
    });
  });

  group('detachRelationship', () {
    test('removes both sides using the entry\'s recorded mirror label', () async {
      await writeFixture('a.json', {
        'primaryType': 'activity',
        'title': 'A',
        'rels': [
          ['inspired by', 'b.json', 'inspires'],
        ],
      });
      await writeFixture('b.json', {
        'primaryType': 'activity',
        'title': 'B',
        'rels': [
          ['inspires', 'a.json', 'inspired by'],
        ],
      });
      await container.read(noteIndexProvider.future);

      await container.read(noteIndexProvider.notifier).detachRelationship(
            filename: 'a.json',
            rel: ['inspired by', 'b.json', 'inspires'],
          );

      final index = container.read(noteIndexProvider).value!;
      expect(index.entries['a.json']?['rels'], <List<String>>[]);
      expect(index.entries['b.json']?['rels'], <List<String>>[]);
    });

    test('only detaches the local side for a legacy 2-element entry', () async {
      await writeFixture('a.json', {
        'primaryType': 'activity',
        'title': 'A',
        'rels': [
          ['inspired by', 'b.json'],
        ],
      });
      await writeFixture('b.json', {
        'primaryType': 'activity',
        'title': 'B',
        'rels': [
          ['inspires', 'a.json'],
        ],
      });
      await container.read(noteIndexProvider.future);

      await container.read(noteIndexProvider.notifier).detachRelationship(
            filename: 'a.json',
            rel: ['inspired by', 'b.json'],
          );

      final index = container.read(noteIndexProvider).value!;
      expect(index.entries['a.json']?['rels'], <List<String>>[]);
      expect(index.entries['b.json']?['rels'], [
        ['inspires', 'a.json'],
      ]);
    });
  });
}
