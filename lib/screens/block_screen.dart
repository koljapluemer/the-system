import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/block_notifier.dart';

/// The Make a Block flow: a task-input screen, an auto-started 25-minute
/// countdown, and a completion screen that can loop into another block or
/// return home. One route, step-switching on BlockState, matching
/// MemorizeScreen's shape.
class BlockScreen extends ConsumerStatefulWidget {
  const BlockScreen({super.key});

  @override
  ConsumerState<BlockScreen> createState() => _BlockScreenState();
}

class _BlockScreenState extends ConsumerState<BlockScreen> {
  late final _taskController = TextEditingController(text: ref.read(blockProvider).task);

  @override
  void dispose() {
    _taskController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Abort resets BlockState back to a blank task, but the controller's own
    // text doesn't follow state automatically — clear it to match.
    ref.listen<BlockState>(blockProvider, (previous, next) {
      if (next.step == BlockStep.inputting &&
          next.task.isEmpty &&
          _taskController.text.isNotEmpty) {
        _taskController.clear();
      }
    });

    final state = ref.watch(blockProvider);
    final notifier = ref.read(blockProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Make a Block')),
      body: SafeArea(
        minimum: const EdgeInsets.only(bottom: 24),
        child: switch (state.step) {
          BlockStep.inputting => _buildInputting(state, notifier),
          BlockStep.timing => _buildTiming(state, notifier),
          BlockStep.finished => _buildFinished(context, state, notifier),
        },
      ),
    );
  }

  Widget _buildInputting(BlockState state, BlockNotifier notifier) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _taskController,
            decoration: const InputDecoration(
              labelText: 'Task',
              border: OutlineInputBorder(),
            ),
            onChanged: notifier.setTask,
          ),
          const SizedBox(height: 16),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: state.visualizationConfirmed,
            onChanged: (checked) => notifier.setVisualizationConfirmed(checked ?? false),
            title: const Text('I have visualized finishing the task'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: notifier.canStart ? notifier.startBlock : null,
            child: const Text('Go'),
          ),
        ],
      ),
    );
  }

  Widget _buildTiming(BlockState state, BlockNotifier notifier) {
    final minutes = state.remaining.inMinutes;
    final seconds = state.remaining.inSeconds % 60;
    final display = '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    return Column(
      children: [
        Expanded(
          child: Center(
            child: Text(display, style: Theme.of(context).textTheme.displayLarge),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: OutlinedButton(
            onPressed: notifier.abort,
            child: const Text('Abort'),
          ),
        ),
      ],
    );
  }

  Widget _buildFinished(BuildContext context, BlockState state, BlockNotifier notifier) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Block finished for task:\n${state.task}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: state.markValid,
            onChanged: (checked) => notifier.setMarkValid(checked ?? false),
            title: const Text('Mark block as valid'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: notifier.doAnotherBlock,
            child: const Text('Do another block on this task'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () async {
              await notifier.switchTask();
              if (context.mounted) {
                Navigator.popUntil(context, (route) => route.isFirst);
              }
            },
            child: const Text('Switch task'),
          ),
        ],
      ),
    );
  }
}
