import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/note_file.dart';
import '../models/note_index.dart';
import '../models/note_type_spec.dart';
import '../state/note_index_notifier.dart';
import '../state/secondary_type_session.dart';
import '../widgets/answers_section.dart';
import '../widgets/array_list_section.dart';
import '../widgets/change_type_dialog.dart';
import '../widgets/inline_editable_text.dart';
import '../widgets/logs_section.dart';
import '../widgets/obsidian_import_dialog.dart';
import '../widgets/relationship_dialog.dart';
import '../widgets/undo_snackbar.dart';
import 'note_editor_navigation.dart';

/// The universal note view/edit UI: title/content are shown read-only with a
/// pencil button to inline-edit each, aliases likewise behind a pencil
/// toggle, plus a unified relationship list (any `[label, filename]` rel,
/// labeled by whatever free-text label was typed when it was attached) with
/// a single "Add Relationship" button that prompts for a forward label and
/// an optional reverse label. Attaching a relationship always mirrors it
/// onto the related note (reverse label defaults to "backlink"); detaching
/// removes both sides too (see
/// [NoteIndexNotifier.attachRelationship]/`detachRelationship`). Reached
/// from every type's Lists screen via [pushNoteEditor], and as the Import
/// Obs Flow's post-create screen.
class NoteDetailScreen extends ConsumerStatefulWidget {
  final NoteTypeSpec spec;
  final String filename;

  const NoteDetailScreen({super.key, required this.spec, required this.filename});

  @override
  ConsumerState<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends ConsumerState<NoteDetailScreen> {
  bool _editingAliases = false;

  Future<void> _saveField(NoteFile note, String key, String value) {
    return ref.read(noteIndexProvider.notifier).write(widget.filename, {...note, key: value});
  }

  Future<void> _saveSecondaryType(NoteFile note, String? value) {
    final updated = {...note};
    if (value == null) {
      updated.remove('secondaryType');
    } else {
      updated['secondaryType'] = value;
      ref.read(lastSecondaryTypeProvider.notifier).record(widget.spec.primaryType, value);
    }
    return ref.read(noteIndexProvider.notifier).write(widget.filename, updated);
  }

  Future<void> _saveAliases(NoteFile note, List<String> aliases) {
    return ref
        .read(noteIndexProvider.notifier)
        .write(widget.filename, {...note, 'aliases': aliases});
  }

  /// Removes [rel] from the note's `rels`, also removing the mirrored rel
  /// from the related note if [rel] carries a recorded mirror label (see
  /// [NoteIndexNotifier.detachRelationship]), offering an Undo that
  /// re-attaches both sides.
  Future<void> _detachRel(
    BuildContext context,
    List<String> rel,
    String relatedTitle,
  ) async {
    final notifier = ref.read(noteIndexProvider.notifier);
    await notifier.detachRelationship(filename: widget.filename, rel: rel);
    if (!context.mounted) return;
    showUndoSnackBar(
      context,
      message: 'Detached "$relatedTitle"',
      onUndo: () => notifier.attachRelationship(
        filename: widget.filename,
        label: rel[0],
        reverseLabel: rel.length > 2 ? rel[2] : null,
        relatedFilename: rel[1],
      ),
    );
  }

  /// Deletes the related note itself (not just the link) and detaches [rel]
  /// so it doesn't dangle, offering an Undo that recreates the note and
  /// re-attaches it.
  Future<void> _deleteRelated(
    BuildContext context,
    List<String> rel,
    String relatedTitle,
  ) async {
    final notifier = ref.read(noteIndexProvider.notifier);
    final relatedFilename = rel[1];
    final relatedNote = ref.read(noteIndexProvider).value?.entries[relatedFilename];
    await notifier.detachRelationship(filename: widget.filename, rel: rel);
    await notifier.delete(relatedFilename);
    if (!context.mounted) return;
    showUndoSnackBar(
      context,
      message: 'Deleted "$relatedTitle"',
      onUndo: () async {
        if (relatedNote != null) {
          await notifier.write(relatedFilename, relatedNote);
        }
        final current = ref.read(noteIndexProvider).value?.entries[widget.filename];
        if (current == null) return;
        await notifier.write(widget.filename, {
          ...current,
          'rels': [...current.relList('rels'), rel],
        });
      },
    );
  }

  Future<void> _renameRelated(String relatedFilename, String newTitle) async {
    final notifier = ref.read(noteIndexProvider.notifier);
    final relatedNote = ref.read(noteIndexProvider).value?.entries[relatedFilename];
    if (relatedNote == null) return;
    await notifier.write(relatedFilename, {...relatedNote, 'title': newTitle});
  }

  void _jumpTo(BuildContext context, NoteIndex index, String relatedFilename) {
    final relatedNote = index.entries[relatedFilename];
    if (relatedNote == null) return;
    final relatedSpec =
        noteTypeSpecs.firstWhere((s) => s.primaryType == relatedNote['primaryType']);
    pushNoteEditor(context, spec: relatedSpec, filename: relatedFilename);
  }

  /// The unified relationship list: every `[label, filename]` rel, in `rels`
  /// array order, each row labeled by its free-text label. Followed by a
  /// single "Add Relationship" button that prompts for a label and an
  /// optional reverse label.
  Widget _relationshipsSection(BuildContext context, NoteFile note, NoteIndex index) {
    final rels = note.relList('rels');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Relationships', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        if (rels.isEmpty) const Text('—'),
        for (final rel in rels)
          _RelationshipRow(
            relTypeLabel: rel[0],
            title: index.entries[rel[1]]?['title'] as String? ?? rel[1],
            targetExists: index.entries.containsKey(rel[1]),
            onSaveTitle: (newTitle) => _renameRelated(rel[1], newTitle),
            onJumpTo: index.entries.containsKey(rel[1]) ? () => _jumpTo(context, index, rel[1]) : null,
            onDetach: () => _detachRel(
              context,
              rel,
              index.entries[rel[1]]?['title'] as String? ?? rel[1],
            ),
            onDelete: index.entries.containsKey(rel[1])
                ? () => _deleteRelated(
                      context,
                      rel,
                      index.entries[rel[1]]?['title'] as String? ?? rel[1],
                    )
                : null,
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.add_link),
            label: const Text('Add Relationship'),
            onPressed: () => showRelationshipDialog(
              context,
              ref,
              filename: widget.filename,
              dialogTitle: 'Add Relationship',
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final asyncIndex = ref.watch(noteIndexProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.spec.label),
        actions: [
          IconButton(
            tooltip: 'Change Type',
            icon: const Icon(Icons.swap_horiz),
            onPressed: () => showChangeTypeDialog(
              context,
              ref,
              filename: widget.filename,
              currentSpec: widget.spec,
            ),
          ),
          IconButton(
            tooltip: 'Add props from Obsidian',
            icon: const Icon(Icons.data_object),
            onPressed: () => showObsidianImportDialog(context, ref, filename: widget.filename),
          ),
        ],
      ),
      body: asyncIndex.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Failed to load note: $error')),
        data: (index) {
          final note = index.entries[widget.filename];
          if (note == null) {
            return const Center(child: Text('This note no longer exists.'));
          }
          final aliases = note.stringList('aliases');

          return ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final field in widget.spec.fields)
                    InlineEditableText(
                      label: field.label,
                      value: note[field.key] as String? ?? '',
                      multiline: field.multiline,
                      onSave: (value) => _saveField(note, field.key, value),
                    ),
                  if (widget.spec.secondaryTypes.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: DropdownButtonFormField<String?>(
                        initialValue: note['secondaryType'] as String?,
                        decoration: const InputDecoration(
                          labelText: 'Secondary Type',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('None')),
                          for (final type in widget.spec.secondaryTypes)
                            DropdownMenuItem<String?>(value: type, child: Text(type)),
                        ],
                        onChanged: (value) => _saveSecondaryType(note, value),
                      ),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _editingAliases
                            ? ArrayListSection(
                                label: 'Aliases',
                                items: aliases,
                                onChanged: (items) => _saveAliases(note, items),
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Aliases', style: Theme.of(context).textTheme.titleMedium),
                                  const SizedBox(height: 4),
                                  aliases.isEmpty
                                      ? const Text('—')
                                      : Wrap(
                                          spacing: 8,
                                          runSpacing: 4,
                                          children: [
                                            for (final alias in aliases) Chip(label: Text(alias)),
                                          ],
                                        ),
                                ],
                              ),
                      ),
                      IconButton(
                        tooltip: _editingAliases ? 'Done' : 'Edit Aliases',
                        icon: Icon(_editingAliases ? Icons.check : Icons.edit),
                        onPressed: () => setState(() => _editingAliases = !_editingAliases),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (widget.spec.showLogs) ...[
                    LogsSection(filename: widget.filename, note: note),
                    const SizedBox(height: 16),
                  ],
                  if (widget.spec.showAnswers) ...[
                    AnswersSection(filename: widget.filename, note: note),
                    const SizedBox(height: 16),
                  ],
                  _relationshipsSection(context, note, index),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One relationship link: title with an inline rename (pencil → TextField
/// with confirm/cancel, mirroring [ArrayListSection]'s per-item edit), plus
/// jump-to/detach/delete actions. Jump-to, edit, and delete are disabled
/// when the related note no longer exists (a dangling rel) — detach stays
/// enabled so a dangling rel can still be cleaned up.
class _RelationshipRow extends StatefulWidget {
  final String relTypeLabel;
  final String title;
  final bool targetExists;
  final ValueChanged<String> onSaveTitle;
  final VoidCallback? onJumpTo;
  final VoidCallback onDetach;
  final VoidCallback? onDelete;

  const _RelationshipRow({
    required this.relTypeLabel,
    required this.title,
    required this.targetExists,
    required this.onSaveTitle,
    required this.onJumpTo,
    required this.onDetach,
    required this.onDelete,
  });

  @override
  State<_RelationshipRow> createState() => _RelationshipRowState();
}

class _RelationshipRowState extends State<_RelationshipRow> {
  bool _editing = false;
  // A title can contain embedded newlines (markdown), which breaks caret
  // positioning/scrolling in a maxLines: 1 TextField, so switch to multi-line
  // rendering whenever the text actually has one.
  bool _multiline = false;
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _startEdit() {
    _controller.text = widget.title;
    _multiline = widget.title.contains('\n');
    setState(() => _editing = true);
  }

  void _onChanged(String text) {
    final multiline = text.contains('\n');
    if (multiline != _multiline) setState(() => _multiline = multiline);
  }

  void _confirmEdit() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) widget.onSaveTitle(text);
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_editing) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                autofocus: true,
                minLines: _multiline ? 3 : null,
                maxLines: _multiline ? 8 : 1,
                onChanged: _onChanged,
                onSubmitted: _multiline ? null : (_) => _confirmEdit(),
              ),
            ),
            IconButton(
              tooltip: 'Save',
              icon: const Icon(Icons.check),
              onPressed: _confirmEdit,
            ),
            IconButton(
              tooltip: 'Cancel',
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => _editing = false),
            ),
          ],
        ),
      );
    }
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(widget.title),
      subtitle: Text(widget.relTypeLabel),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Jump to',
            icon: const Icon(Icons.open_in_new),
            onPressed: widget.onJumpTo,
          ),
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit),
            onPressed: widget.targetExists ? _startEdit : null,
          ),
          IconButton(
            tooltip: 'Detach',
            icon: const Icon(Icons.link_off),
            onPressed: widget.onDetach,
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete),
            onPressed: widget.onDelete,
          ),
        ],
      ),
    );
  }
}
