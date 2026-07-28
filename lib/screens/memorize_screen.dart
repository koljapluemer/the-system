import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fsrs/fsrs.dart' as fsrs;

import '../models/note_type_spec.dart';
import '../state/memorize_notifier.dart';
import '../widgets/flashcard_card.dart';
import 'art_triage_screen.dart';
import 'note_editor_navigation.dart';

/// The spaced-repetition flashcard flow. Loads a random due (or, failing
/// that, brand-new) `flashcard` note, reveals it on demand, and grades it
/// with fsrs — with a 1/6 chance per turn of instead pushing the (otherwise
/// standalone-retired) ArtTriageScreen as a break.
class MemorizeScreen extends ConsumerWidget {
  const MemorizeScreen({super.key});

  Future<void> _showArtTriage(BuildContext context, WidgetRef ref) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ArtTriageScreen()),
    );
    if (context.mounted) {
      await ref.read(memorizeProvider.notifier).continueAfterArtTriage();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<MemorizeState>(memorizeProvider, (previous, next) {
      if (next.showArtTriage && previous?.showArtTriage != true) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _showArtTriage(context, ref));
      }
    });

    final state = ref.watch(memorizeProvider);
    final notifier = ref.read(memorizeProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Memorize'),
        actions: state.currentNote == null
            ? null
            : [
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => pushNoteEditor(
                    context,
                    spec: noteTypeSpecs.firstWhere((s) => s.primaryType == 'flashcard'),
                    filename: state.currentFilename!,
                  ),
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => notifier.deleteCurrent(context),
                ),
              ],
      ),
      body: SafeArea(
        minimum: const EdgeInsets.only(bottom: 88),
        child: _buildBody(context, state, notifier),
      ),
    );
  }

  Widget _buildBody(BuildContext context, MemorizeState state, MemorizeNotifier notifier) {
    if (state.loading || state.showArtTriage) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.currentNote == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('All caught up — no flashcards due.', textAlign: TextAlign.center),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: FlashcardCard(note: state.currentNote!, revealed: state.revealed),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _buildActions(state, notifier),
          ),
        ),
      ],
    );
  }

  Widget _buildActions(MemorizeState state, MemorizeNotifier notifier) {
    if (!state.revealed) {
      return FilledButton(onPressed: notifier.reveal, child: const Text('Reveal'));
    }
    if (state.isNew) {
      return FilledButton(onPressed: notifier.rememberNew, child: const Text('I will remember'));
    }
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => notifier.rate(fsrs.Rating.again),
            child: const Text('Again'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            onPressed: () => notifier.rate(fsrs.Rating.hard),
            child: const Text('Hard'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton(
            onPressed: () => notifier.rate(fsrs.Rating.good),
            child: const Text('Good'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton(
            onPressed: () => notifier.rate(fsrs.Rating.easy),
            child: const Text('Easy'),
          ),
        ),
      ],
    );
  }
}
