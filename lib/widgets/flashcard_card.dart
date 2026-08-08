import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

/// Renders one flashcard for the Memorize flow: front (and, once revealed,
/// a thin rule plus back) as centered markdown, sized up since a card's
/// content here is usually a single short line — no border or elevation, so
/// the text reads as the screen rather than a box floating on it. Edit/
/// delete live in the screen's AppBar instead of overlaid on the content.
/// [front]/[back] are pre-resolved strings rather than a raw note, since a
/// `quote` turn's text is generated on the fly (see
/// lib/services/quote_flashcard_service.dart) rather than read straight off
/// a note's own fields the way a `flashcard` note's are.
class FlashcardCard extends StatelessWidget {
  final String front;
  final String back;
  final bool revealed;

  const FlashcardCard({super.key, required this.front, required this.back, required this.revealed});

  @override
  Widget build(BuildContext context) {
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
