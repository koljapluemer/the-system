import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../models/note_file.dart';
import '../models/note_type_spec.dart';
import '../screens/note_editor_navigation.dart';

/// Renders one flashcard for the Memorize flow: front (and, once revealed,
/// a separator plus back) as markdown, with small top-right icon buttons to
/// jump to its edit view or delete it — mirroring art_triage_body.dart's
/// Card layout/max-width convention and note_detail_screen.dart's
/// trailing-icon-row convention.
class FlashcardCard extends StatelessWidget {
  final String filename;
  final NoteFile note;
  final bool revealed;
  final VoidCallback onDelete;

  const FlashcardCard({
    super.key,
    required this.filename,
    required this.note,
    required this.revealed,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final front = note['front'] as String? ?? '';
    final back = note['back'] as String? ?? '';
    final spec = noteTypeSpecs.firstWhere((s) => s.primaryType == 'flashcard');

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Edit',
                    icon: const Icon(Icons.edit),
                    onPressed: () => pushNoteEditor(context, spec: spec, filename: filename),
                  ),
                  IconButton(
                    tooltip: 'Delete',
                    icon: const Icon(Icons.delete),
                    onPressed: onDelete,
                  ),
                ],
              ),
              MarkdownBody(data: front),
              if (revealed) ...[
                const Divider(height: 32),
                MarkdownBody(data: back),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
