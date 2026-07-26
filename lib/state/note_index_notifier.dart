import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/note_file.dart';
import '../models/note_index.dart';
import '../models/note_search.dart';
import '../models/note_type_spec.dart';
import 'providers.dart';

/// Properties allowed by assets/note_schema.json for a primaryType that
/// aren't already covered by [NoteTypeSpec.fields], because they're managed
/// by a dedicated flow rather than the generic edit form (see the
/// `milestone`/`flashcard` entries in note_type_spec.dart). Consulted by
/// [NoteIndexNotifier.changePrimaryType] to know what to keep.
const _extraKeysOutsideFields = <String, List<String>>{
  'milestone': ['logs'],
  'flashcard': ['fsrs'],
};

/// The app-wide cache of every note in the data folder. Built once per
/// folder by scanning disk (see [NotesService.scanNotes]), then kept in sync
/// in memory as the app itself writes/deletes/creates notes — this app is
/// the only writer to the folder, so no external-change staleness handling
/// is needed. All triage/list flows read from this instead of each
/// re-scanning disk independently.
class NoteIndexNotifier extends AsyncNotifier<NoteIndex> {
  @override
  Future<NoteIndex> build() async {
    // Await rather than read-and-bang: if dataFolderProvider hasn't resolved
    // yet, watching its raw AsyncValue and racing a null .value would throw,
    // and the resulting rebuild-on-settle would abandon this build's Future
    // — orphaning anyone already awaiting it. Awaiting .future here instead
    // suspends properly until it settles.
    final folder = (await ref.watch(dataFolderProvider.future))!;
    final entries = <String, NoteFile>{};
    final unparsable = <String>{};
    await for (final result in ref.read(notesServiceProvider).scanNotes(folder)) {
      if (result.data != null) {
        entries[result.filename] = result.data!;
      } else {
        unparsable.add(result.filename);
      }
    }
    return NoteIndex(entries: entries, unparsable: unparsable);
  }

  Future<void> write(String filename, NoteFile content) async {
    final folder = (await ref.read(dataFolderProvider.future))!;
    await ref.read(notesServiceProvider).writeJsonFile(folder, filename, content);
    await update((index) => index.copyWith(entries: {...index.entries, filename: content}));
  }

  Future<void> delete(String filename) async {
    final folder = (await ref.read(dataFolderProvider.future))!;
    await ref.read(notesServiceProvider).deleteJsonFile(folder, filename);
    await update((index) => index.copyWith(entries: {...index.entries}..remove(filename)));
  }

  /// Attaches `[label, relatedFilename, reverseLabel]` to `filename`'s
  /// `rels`, and always attaches the mirror `[reverseLabel, filename, label]`
  /// to the related note too — e.g. adding "inspired by" to a note also adds
  /// "backlink" (or a caller-supplied [reverseLabel]) back to the related
  /// one. Every relationship is reciprocal now; [reverseLabel] defaults to
  /// `'backlink'` when not given. Idempotent: a pair already present on
  /// either side is not duplicated (needed so `_deleteRelated`'s Undo, which
  /// restores the related note's full pre-delete content and then
  /// re-attaches, doesn't double the mirror).
  Future<void> attachRelationship({
    required String filename,
    required String label,
    String? reverseLabel,
    required String relatedFilename,
  }) async {
    final effectiveReverseLabel = reverseLabel ?? 'backlink';

    final index = await future;
    final note = index.entries[filename];
    if (note == null) return;
    final rel = [label, relatedFilename, effectiveReverseLabel];
    if (!note.relList('rels').any((r) => r[0] == label && r[1] == relatedFilename)) {
      await write(filename, {
        ...note,
        'rels': [...note.relList('rels'), rel],
      });
    }

    final related = (await future).entries[relatedFilename];
    if (related == null) return;
    final mirrorRel = [effectiveReverseLabel, filename, label];
    if (!related.relList('rels').any((r) => r[0] == effectiveReverseLabel && r[1] == filename)) {
      await write(relatedFilename, {
        ...related,
        'rels': [...related.relList('rels'), mirrorRel],
      });
    }
  }

  /// Removes [rel] from `filename`'s `rels`, then — if [rel] carries its
  /// recorded mirror label (a 3-element entry, `rel[2]`) — also removes the
  /// mirrored `[rel[2], filename]` pair from the related note. A legacy
  /// 2-element entry (predating this format, or hand-edited) has no known
  /// mirror to remove, so only the local side is detached.
  Future<void> detachRelationship({required String filename, required List<String> rel}) async {
    final index = await future;
    final note = index.entries[filename];
    if (note != null) {
      final rels = note.relList('rels').where((r) => r[0] != rel[0] || r[1] != rel[1]);
      await write(filename, {...note, 'rels': rels.toList()});
    }

    if (rel.length < 3) return;
    final mirrorLabel = rel[2];
    final relatedFilename = rel[1];
    final related = (await future).entries[relatedFilename];
    if (related == null) return;
    final mirrorRels =
        related.relList('rels').where((r) => !(r[0] == mirrorLabel && r[1] == filename));
    await write(relatedFilename, {...related, 'rels': mirrorRels.toList()});
  }

  /// Creates a new note of [spec]'s primaryType with [title] and an empty
  /// string for every other field in [spec.fields] (e.g. `content`), for the
  /// "new note" action on a type's Lists screen. [secondaryType], when
  /// given, is stamped onto the note too (the Add screen's secondaryType
  /// picker, when [spec.secondaryTypes] is non-empty).
  Future<String> createFromSpec(
    NoteTypeSpec spec, {
    required String title,
    String? secondaryType,
  }) async {
    final folder = (await ref.read(dataFolderProvider.future))!;
    final content = <String, dynamic>{'primaryType': spec.primaryType, 'title': title};
    for (final field in spec.fields) {
      if (field.key == 'title') continue;
      content[field.key] = '';
    }
    if (secondaryType != null) content['secondaryType'] = secondaryType;
    final filename =
        await ref.read(notesServiceProvider).createNote(folder, content, slugSource: title);
    await update((index) => index.copyWith(entries: {...index.entries, filename: content}));
    return filename;
  }

  /// Forces a fresh full-folder rescan, e.g. as a manual escape hatch if the
  /// in-memory index is ever suspected to have drifted from disk.
  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  /// Converts `filename`'s note to [newSpec]'s primaryType in place, so it
  /// keeps matching assets/note_schema.json (`additionalProperties: false`)
  /// for its new shape: keeps fields common to every type (title, aliases,
  /// rels, extraData) plus any field whose key exists in both the old and
  /// new type (e.g. `content` surviving an art→activity switch), drops
  /// everything else unique to the old type, and fills any of [newSpec]'s
  /// fields still missing with `''`. `secondaryType` and `triaged` are kept
  /// only when the new type still allows them (dropped, not remapped, if the
  /// old value isn't one of [newSpec.secondaryTypes]). A few types carry
  /// fields outside [NoteTypeSpec.fields] by design (see the
  /// `milestone`/`flashcard` entries in note_type_spec.dart and
  /// [_extraKeysOutsideFields]) — those are preserved the same way.
  Future<void> changePrimaryType({required String filename, required NoteTypeSpec newSpec}) async {
    final index = await future;
    final note = index.entries[filename];
    if (note == null) return;

    final allowedKeys = {
      'primaryType', 'title', 'aliases', 'rels', 'extraData',
      if (newSpec.primaryType != 'flashcard') 'triaged',
      if (newSpec.secondaryTypes.isNotEmpty) 'secondaryType',
      for (final field in newSpec.fields) field.key,
      ...?_extraKeysOutsideFields[newSpec.primaryType],
    };

    final updated = <String, dynamic>{...note}
      ..removeWhere((key, _) => !allowedKeys.contains(key));
    updated['primaryType'] = newSpec.primaryType;
    if (updated['secondaryType'] is String &&
        !newSpec.secondaryTypes.contains(updated['secondaryType'])) {
      updated.remove('secondaryType');
    }
    for (final field in newSpec.fields) {
      updated[field.key] ??= '';
    }

    await write(filename, updated);
  }
}

final noteIndexProvider = AsyncNotifierProvider<NoteIndexNotifier, NoteIndex>(NoteIndexNotifier.new);

/// [noteIndexProvider]'s entries pre-lowered/pre-tokenized for similar-notes
/// search (see `NormalizedNote`), recomputed only when the index itself
/// changes rather than per keystroke — fed to [NoteSearchWorker] by
/// `add_screen.dart`.
final normalizedNotesProvider = Provider<List<NormalizedNote>>((ref) {
  final index = ref.watch(noteIndexProvider).value;
  return index == null ? const [] : normalizeNotes(index.entries);
});
