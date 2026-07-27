import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/note_type_spec.dart';
import '../state/frog_notifier.dart';
import 'note_editor_navigation.dart';

/// The Frog flow: shows the day's single randomly-picked `frog` note (see
/// [FrogNotifier]) and four actions mirroring the source app's "eat the
/// frog" mechanic — Done and Impossible Today leave the frog in the pool,
/// Done & Delete and Just Delete remove it. Any one action gates the rest
/// of the day.
class FrogScreen extends ConsumerWidget {
  const FrogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(frogProvider);
    final notifier = ref.read(frogProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Frog')),
      body: SafeArea(child: _buildBody(context, state, notifier)),
    );
  }

  Widget _buildBody(BuildContext context, FrogState state, FrogNotifier notifier) {
    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.poolEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('Add some frogs in the Frog list.', textAlign: TextAlign.center),
        ),
      );
    }

    if (state.actedToday) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('Nothing more to do today.', textAlign: TextAlign.center),
        ),
      );
    }

    final filename = state.currentFilename!;
    final note = state.currentNote!;
    final spec = noteTypeSpecs.firstWhere((s) => s.primaryType == 'frog');

    return Column(
      children: [
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
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              tooltip: 'Edit',
                              icon: const Icon(Icons.edit),
                              onPressed: () =>
                                  pushNoteEditor(context, spec: spec, filename: filename),
                            ),
                          ],
                        ),
                        Text(
                          note['title'] as String? ?? '',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _buildActions(context, notifier),
          ),
        ),
      ],
    );
  }

  Widget _buildActions(BuildContext context, FrogNotifier notifier) {
    final errorColor = Theme.of(context).colorScheme.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(onPressed: notifier.markDone, child: const Text('Done')),
        const SizedBox(height: 8),
        OutlinedButton(
          style: OutlinedButton.styleFrom(foregroundColor: errorColor),
          onPressed: notifier.markDoneAndDelete,
          child: const Text('Done & Delete'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          style: OutlinedButton.styleFrom(foregroundColor: errorColor),
          onPressed: notifier.markJustDelete,
          child: const Text('Just Delete'),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: notifier.markImpossibleToday, child: const Text('Impossible Today')),
      ],
    );
  }
}
