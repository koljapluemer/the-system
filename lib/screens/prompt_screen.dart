import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/note_type_spec.dart';
import '../state/prompt_notifier.dart';
import 'note_editor_navigation.dart';

/// The habit-prompter-style flow: repeatedly shows a random due `prompt`
/// note's question and takes a free-text answer, advancing to the next due
/// prompt on submit. Mirrors memorize_screen.dart's structure.
class PromptScreen extends ConsumerStatefulWidget {
  const PromptScreen({super.key});

  @override
  ConsumerState<PromptScreen> createState() => _PromptScreenState();
}

class _PromptScreenState extends ConsumerState<PromptScreen> {
  final _answerController = TextEditingController();

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _answerController.text;
    if (text.trim().isEmpty) return;
    await ref.read(promptProvider.notifier).answer(text);
    _answerController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(promptProvider);
    final notifier = ref.read(promptProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Prompts')),
      body: SafeArea(
        minimum: const EdgeInsets.only(bottom: 88),
        child: _buildBody(context, state, notifier),
      ),
    );
  }

  Widget _buildBody(BuildContext context, PromptState state, PromptNotifier notifier) {
    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.currentNote == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('All caught up — no prompts due.', textAlign: TextAlign.center),
        ),
      );
    }

    final filename = state.currentFilename!;
    final note = state.currentNote!;
    final spec = noteTypeSpecs.firstWhere((s) => s.primaryType == 'prompt');

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
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                            IconButton(
                              tooltip: 'Delete',
                              icon: const Icon(Icons.delete),
                              onPressed: () => notifier.deleteCurrent(context),
                            ),
                          ],
                        ),
                        MarkdownBody(data: note['title'] as String? ?? ''),
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
            child: _buildAnswerInput(),
          ),
        ),
      ],
    );
  }

  Widget _buildAnswerInput() {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _answerController,
      builder: (context, value, _) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _answerController,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Your answer',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: value.text.trim().isEmpty ? null : _submit,
              child: const Text('Submit'),
            ),
          ],
        );
      },
    );
  }
}
