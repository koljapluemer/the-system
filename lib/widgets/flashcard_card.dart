import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../models/note_file.dart';

/// Renders one flashcard for the Memorize flow: front (and, once revealed,
/// a thin rule plus back) as centered markdown, sized up since a card's
/// content here is usually a single short line — no border or elevation, so
/// the text reads as the screen rather than a box floating on it. Edit/
/// delete live in the screen's AppBar instead of overlaid on the content.
class FlashcardCard extends StatelessWidget {
  final NoteFile note;
  final bool revealed;

  const FlashcardCard({super.key, required this.note, required this.revealed});

  @override
  Widget build(BuildContext context) {
    final front = note['front'] as String? ?? '';
    final back = note['back'] as String? ?? '';
    final textTheme = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MarkdownBody(
          data: front,
          styleSheet: MarkdownStyleSheet(
            p: textTheme.headlineSmall,
            textAlign: WrapAlignment.center,
          ),
        ),
        if (revealed) ...[
          const SizedBox(height: 32),
          Container(width: 48, height: 1, color: Theme.of(context).dividerColor),
          const SizedBox(height: 32),
          MarkdownBody(
            data: back,
            styleSheet: MarkdownStyleSheet(
              p: textTheme.titleMedium,
              textAlign: WrapAlignment.center,
            ),
          ),
        ],
      ],
    );
  }
}
