import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/note_file.dart';
import '../state/note_index_notifier.dart';

/// Human-readable, minute-granularity formatting for an answer's
/// `createdAt`, matching [LogsSection]'s convention.
final _timestampFormat = DateFormat.yMMMd().add_Hm();

/// Read-only expandable "Answers" section for note types that accumulate
/// timestamped free-text answers via a dedicated flow (see
/// [NoteTypeSpec.showAnswers] — currently prompt): the note's own `answers`
/// array of `{text, createdAt}` objects, shown newest first. Unlike
/// [LogsSection], there's no inline "add" field here — an answer is only
/// ever recorded by completing the Prompts flow, which also needs to stamp
/// `lastShownAt`, so a bare add-field here would leave scheduling
/// inconsistent. Deleting an entry (e.g. to correct a mistake) is still
/// supported.
class AnswersSection extends ConsumerWidget {
  final String filename;
  final NoteFile note;

  const AnswersSection({super.key, required this.filename, required this.note});

  List<Map<String, dynamic>> get _answers {
    final value = note['answers'];
    return value is List
        ? value.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList()
        : [];
  }

  void _delete(WidgetRef ref, int index) {
    final updated = [..._answers]..removeAt(index);
    ref.read(noteIndexProvider.notifier).write(filename, {...note, 'answers': updated});
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = _answers.asMap().entries.toList()
      ..sort((a, b) {
        final aTime = DateTime.tryParse(a.value['createdAt'] as String? ?? '');
        final bTime = DateTime.tryParse(b.value['createdAt'] as String? ?? '');
        if (aTime == null || bTime == null) return 0;
        return bTime.compareTo(aTime);
      });

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: Text(
          'Answers (${entries.length})',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        children: [
          if (entries.isEmpty) const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('—')),
          for (final entry in entries)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(entry.value['text'] as String? ?? ''),
              subtitle: Text(_formatTimestamp(entry.value['createdAt'] as String?)),
              trailing: IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete),
                onPressed: () => _delete(ref, entry.key),
              ),
            ),
        ],
      ),
    );
  }
}

String _formatTimestamp(String? iso) {
  final parsed = iso == null ? null : DateTime.tryParse(iso);
  return parsed == null ? 'unknown time' : _timestampFormat.format(parsed);
}
