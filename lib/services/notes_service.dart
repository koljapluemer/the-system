import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../models/note_file.dart';
import '../models/note_scan_result.dart';

/// Reads/writes/lists/deletes note files that live as flat JSON files
/// directly inside a single data folder.
class NotesService {
  const NotesService();

  static const _forbiddenTokens = ['/', '\\', '..'];

  void _assertSafeFilename(String filename) {
    for (final token in _forbiddenTokens) {
      if (filename.contains(token)) {
        throw ArgumentError('invalid filename: $filename');
      }
    }
  }

  File _notePath(String folder, String filename) {
    _assertSafeFilename(filename);
    return File(p.join(folder, filename));
  }

  /// Scans the data folder once, decoding every `.json` file. Reads happen
  /// [concurrency]-wide instead of one file at a time, so the wall-clock cost
  /// of scanning a folder with tens of thousands of files is dominated by
  /// per-file I/O latency in parallel rather than in series (this matters
  /// most on Android, where each file read on MANAGE_EXTERNAL_STORAGE-backed
  /// paths carries real per-call overhead). Every `.json` file is yielded
  /// exactly once, with `data` null for anything that isn't parsable as a
  /// JSON object — callers that care about invalid files (e.g. the
  /// invalid-JSON checker) can still see them.
  Stream<NoteScanResult> scanNotes(String folder, {int concurrency = 32}) async* {
    final dir = Directory(folder);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
      return;
    }

    final jsonFiles = <File>[];
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.json')) {
        jsonFiles.add(entity);
      }
    }

    for (var i = 0; i < jsonFiles.length; i += concurrency) {
      final batch = jsonFiles.skip(i).take(concurrency);
      final results = await Future.wait(batch.map(_readScanResult));
      for (final result in results) {
        yield result;
      }
    }
  }

  Future<NoteScanResult> _readScanResult(File file) async {
    final filename = p.basename(file.path);
    try {
      final data = jsonDecode(await file.readAsString());
      if (data is! Map<String, dynamic>) return NoteScanResult(filename: filename);
      return NoteScanResult(filename: filename, data: data);
    } catch (_) {
      return NoteScanResult(filename: filename);
    }
  }

  Future<NoteFile> readJsonFile(String folder, String filename) async {
    final file = _notePath(folder, filename);
    return jsonDecode(await file.readAsString()) as NoteFile;
  }

  Future<void> writeJsonFile(
    String folder,
    String filename,
    NoteFile content,
  ) async {
    final file = _notePath(folder, filename);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(content));
  }

  Future<void> deleteJsonFile(String folder, String filename) async {
    final file = _notePath(folder, filename);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Creates a new note file with an arbitrary [content] map. The filename is
  /// a slug of [slugSource] plus a random 6-character alphanumeric suffix, so
  /// titles can repeat without colliding on disk.
  Future<String> createNote(
    String folder,
    NoteFile content, {
    required String slugSource,
  }) async {
    final filename = '${_slugify(slugSource)}-${_randomSuffix6()}.json';
    await writeJsonFile(folder, filename, content);
    return filename;
  }

  /// Copies [source] into `<folder>/<subfolder>/`, creating that folder if
  /// needed, under a collision-safe generated filename that preserves
  /// [source]'s extension. Used for the Attach Audio File action so imported
  /// media lives in its own parallel folder (e.g. `audio/`), mirroring how
  /// [createNote] generates a collision-safe name for note JSON files.
  /// Throws an [ArgumentError] if [source]'s extension (case-insensitively)
  /// isn't in [allowedExtensions] — the only place in this app that enforces
  /// a file-format allowlist for attached media.
  Future<String> importMediaFile({
    required String folder,
    required String subfolder,
    required File source,
    required List<String> allowedExtensions,
  }) async {
    final ext = p.extension(source.path).replaceFirst('.', '').toLowerCase();
    if (!allowedExtensions.contains(ext)) {
      throw ArgumentError('unsupported file extension: .$ext');
    }
    final dir = Directory(p.join(folder, subfolder));
    await dir.create(recursive: true);
    final filename =
        '${_slugify(p.basenameWithoutExtension(source.path))}-${_randomSuffix6()}.$ext';
    await source.copy(p.join(dir.path, filename));
    return filename;
  }

  /// Most filesystems cap a filename at 255 bytes; long titles (e.g. a story
  /// note whose title is a whole paragraph) would otherwise blow past that
  /// once slugified, so this is capped well under the limit even after the
  /// `-xxxxxx.json` suffix is appended.
  static const _maxSlugLength = 80;

  String _slugify(String title) {
    var slug = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (slug.length > _maxSlugLength) {
      slug = slug.substring(0, _maxSlugLength).replaceAll(RegExp(r'-+$'), '');
    }
    return slug.isEmpty ? 'note' : slug;
  }

  static const _suffixAlphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';

  /// A wider alphabet than a hex suffix (36 vs. 16 options per character)
  /// for a much larger collision space at the same length.
  String _randomSuffix6() {
    final random = Random();
    return List.generate(6, (_) => _suffixAlphabet[random.nextInt(_suffixAlphabet.length)]).join();
  }
}
