import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/recent_history_notifier.dart';
import 'frog_screen.dart';
import 'memorize_screen.dart';
import 'prompt_screen.dart';
import 'search_screen.dart';

/// Describes one top-level flow, reachable from [HomeScreen]'s link list and
/// from the recent-history bar (see RecentBar). Data-driven on purpose: this
/// app is meant to grow into a suite of flows, so new ones just get added
/// here.
class FlowSpec {
  final String id;
  final String label;
  final IconData icon;
  final WidgetBuilder builder;

  const FlowSpec({
    required this.id,
    required this.label,
    required this.icon,
    required this.builder,
  });
}

final flowSpecs = [
  FlowSpec(
    id: 'memorize',
    label: 'Memorize',
    icon: Icons.school_outlined,
    builder: (_) => const MemorizeScreen(),
  ),
  FlowSpec(
    id: 'prompts',
    label: 'Prompts',
    icon: Icons.chat_bubble_outline,
    builder: (_) => const PromptScreen(),
  ),
  FlowSpec(
    id: 'search',
    label: 'Search',
    icon: Icons.search,
    builder: (_) => const SearchScreen(),
  ),
  FlowSpec(
    id: 'frog',
    label: 'Frog',
    icon: Icons.pets,
    builder: (_) => const FrogScreen(),
  ),
];

/// Pushes the flow identified by [id] and records it in [recentHistoryProvider]
/// — the single chokepoint for entering a flow, mirroring [pushNoteEditor]'s
/// role for notes, so the recent-history bar stays accurate no matter how a
/// flow is reached.
void pushFlow(BuildContext context, WidgetRef ref, String id) {
  final spec = flowSpecs.firstWhere((s) => s.id == id);
  ref
      .read(recentHistoryProvider.notifier)
      .record(RecentEntry(kind: RecentEntryKind.flow, id: spec.id, label: spec.label));
  Navigator.push(context, MaterialPageRoute(builder: spec.builder));
}
