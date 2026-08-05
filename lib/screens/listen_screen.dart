import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../services/audio_listen_service.dart';
import '../state/listen_notifier.dart';
import '../state/note_index_notifier.dart';
import '../state/providers.dart';
import '../widgets/audio_player_widget.dart';
import '../widgets/tag_chip_input.dart';

/// The Listen flow: an and/or/not by-tag filter above a random `audio`
/// note's player, with an end-of-track action selector and manual Next button
/// below. One
/// route, rebuilding purely off [ListenState], matching [MemorizeScreen]'s
/// shape.
class ListenScreen extends ConsumerWidget {
  const ListenScreen({super.key});

  Widget _filterBar(BuildContext context, WidgetRef ref, ListenState state, ListenNotifier notifier) {
    final knownTags = ref.watch(knownAudioTagsProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: DropdownButtonFormField<TagFilterMode>(
              initialValue: state.tagFilterMode,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
              items: [
                for (final mode in TagFilterMode.values)
                  DropdownMenuItem(value: mode, child: Text(mode.name)),
              ],
              onChanged: (mode) => mode == null ? null : notifier.setTagFilterMode(mode),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TagChipInput(
              tags: state.filterTags.toList(),
              knownTags: knownTags,
              onChanged: (tags) => notifier.setFilterTags(tags.toSet()),
            ),
          ),
        ],
      ),
    );
  }

  static const _actionLabels = {
    ListenAction.next: "Don't Hide",
    ListenAction.hideForWeek: 'Hide for 1 Week',
    ListenAction.hideForTwoMonths: 'Hide for 2 Months',
    ListenAction.hideForYear: 'Hide for 1 Year',
    ListenAction.neverListenAgain: 'Never Listen Again',
  };

  Widget _actionRadioGroup(ListenState state, ListenNotifier notifier) {
    return RadioGroup<ListenAction>(
      groupValue: state.selectedAction,
      onChanged: (value) => value == null ? null : notifier.setSelectedAction(value),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final action in ListenAction.values)
            RadioListTile<ListenAction>(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(_actionLabels[action]!),
              value: action,
            ),
        ],
      ),
    );
  }

  Widget _controls(ListenState state, ListenNotifier notifier) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _actionRadioGroup(state, notifier),
        const SizedBox(height: 12),
        SizedBox(
          height: 56,
          child: FilledButton(
            onPressed: notifier.next,
            child: const Text('Next'),
          ),
        ),
      ],
    );
  }

  Widget _content(BuildContext context, ListenState state, String? folder, ListenNotifier notifier) {
    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.allCaughtUp) {
      return const Center(child: Text('No audio notes are eligible right now.'));
    }
    final note = state.currentNote;
    if (note == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final title = note['title'] as String? ?? '(untitled)';
    final content = note['content'] as String? ?? '';
    final audioFile = note['audioFile'] as String?;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
          if (content.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(content, textAlign: TextAlign.center),
          ],
          const SizedBox(height: 16),
          if (audioFile != null && folder != null)
            AudioPlayerWidget(
              key: ValueKey(state.currentFilename),
              file: File(p.join(folder, 'audio', audioFile)),
              autoPlay: true,
              onEnded: notifier.onAudioEnded,
            )
          else
            const Text('No audio file attached.'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(listenProvider);
    final notifier = ref.read(listenProvider.notifier);
    final folder = ref.watch(dataFolderProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Listen')),
      body: SafeArea(
        minimum: const EdgeInsets.only(bottom: 24),
        child: Column(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: _filterBar(context, ref, state, notifier),
            ),
            const Divider(height: 1),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: _content(context, state, folder, notifier),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: _controls(state, notifier),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
