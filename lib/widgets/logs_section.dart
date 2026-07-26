import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/note_file.dart';
import '../state/note_index_notifier.dart';

/// Human-readable, minute-granularity formatting for a log entry's
/// `createdAt`, per Flutter's recommended `intl` `DateFormat` approach
/// rather than hand-rolled string formatting.
final _timestampFormat = DateFormat.yMMMd().add_Hm();

/// Expandable "Logs" section for note types that accumulate timestamped
/// free-text entries directly on themselves (see [NoteTypeSpec.showLogs] —
/// currently milestone): the note's own `logs` array of `{content,
/// createdAt}` objects, shown newest first, plus an inline field that
/// appends a new entry stamped with the current moment.
class LogsSection extends ConsumerStatefulWidget {
  final String filename;
  final NoteFile note;

  const LogsSection({super.key, required this.filename, required this.note});

  @override
  ConsumerState<LogsSection> createState() => _LogsSectionState();
}

class _LogsSectionState extends ConsumerState<LogsSection> {
  final _addController = TextEditingController();

  @override
  void dispose() {
    _addController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _logs {
    final value = widget.note['logs'];
    return value is List
        ? value.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList()
        : [];
  }

  Future<void> _write(List<Map<String, dynamic>> logs) {
    return ref
        .read(noteIndexProvider.notifier)
        .write(widget.filename, {...widget.note, 'logs': logs});
  }

  void _add() {
    final text = _addController.text.trim();
    if (text.isEmpty) return;
    final entry = {'content': text, 'createdAt': DateTime.now().toIso8601String()};
    _write([..._logs, entry]);
    _addController.clear();
  }

  void _delete(int index) {
    final updated = [..._logs]..removeAt(index);
    _write(updated);
  }

  @override
  Widget build(BuildContext context) {
    final entries = _logs.asMap().entries.toList()
      ..sort((a, b) {
        final aTime = DateTime.tryParse(a.value['createdAt'] as String? ?? '');
        final bTime = DateTime.tryParse(b.value['createdAt'] as String? ?? '');
        if (aTime == null || bTime == null) return 0;
        return bTime.compareTo(aTime);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: Text(
              'Logs (${entries.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            children: [
              if (entries.isEmpty) const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('—')),
              for (final entry in entries)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(entry.value['content'] as String? ?? ''),
                  subtitle: Text(_formatTimestamp(entry.value['createdAt'] as String?)),
                  trailing: IconButton(
                    tooltip: 'Delete',
                    icon: const Icon(Icons.delete),
                    onPressed: () => _delete(entry.key),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _addController,
                        decoration: const InputDecoration(labelText: 'Add Log'),
                        onSubmitted: (_) => _add(),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Add',
                      icon: const Icon(Icons.add),
                      onPressed: _add,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _formatTimestamp(String? iso) {
  final parsed = iso == null ? null : DateTime.tryParse(iso);
  return parsed == null ? 'unknown time' : _timestampFormat.format(parsed);
}
