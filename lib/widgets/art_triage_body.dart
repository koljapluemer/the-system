import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../state/art_triage_notifier.dart';
import '../state/providers.dart';

/// Renders exactly one art-triage decision for the Memorize flow's "1/6 of
/// turns are a triage break" mechanic. This is a single trial, symmetric
/// with a flashcard turn: the user picks keep/delete/defer exactly once,
/// and that single tap both acts on [artTriageProvider] (which manages its
/// own queue) and calls [onDecided] to roll the *next* Memorize turn — never
/// looping to show a second art note without an independent re-roll, and
/// never needing a manual "done" exit.
///
/// [MemorizeNotifier] only shows this turn type when it has already
/// confirmed at least one art note exists, so `currentNote == null` here is
/// treated as a transient loading state, not a dead end.
class ArtTriageBody extends ConsumerWidget {
  final Future<void> Function() onDecided;

  const ArtTriageBody({super.key, required this.onDecided});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(artTriageProvider);
    final notifier = ref.read(artTriageProvider.notifier);
    final folder = ref.watch(dataFolderProvider).value;

    if (state.loading || state.currentNote == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final note = state.currentNote!;
    final title = note['title'] as String? ?? '(untitled)';
    final content = note['content'] as String? ?? '';
    final image = note['image'] as String?;
    // Cap extreme-portrait images so they can't push the action buttons
    // off-screen; the surrounding scroll view is a safety net for anything
    // still too tall (e.g. very long markdown).
    final maxImageHeight = MediaQuery.sizeOf(context).height * 0.5;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Text('Art triage', style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: Theme.of(context).textTheme.titleMedium),
                        if (image != null && folder != null) ...[
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(maxHeight: maxImageHeight),
                              child: Image.file(
                                File(p.join(folder, 'media', image)),
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        MarkdownBody(data: content),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () async {
                      await notifier.keep();
                      await onDecided();
                    },
                    icon: const Icon(Icons.check),
                    label: const Text('Keep'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
                    onPressed: () async {
                      await notifier.delete(context);
                      await onDecided();
                    },
                    icon: const Icon(Icons.delete),
                    label: const Text('Delete'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await notifier.defer();
                      await onDecided();
                    },
                    icon: const Icon(Icons.skip_next),
                    label: const Text('Defer'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
