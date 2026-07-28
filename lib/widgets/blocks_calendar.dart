import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/note_file.dart';
import '../state/note_index_notifier.dart';

/// The Stats section's "Blocks" view: every completed block, grouped by the
/// calendar day it was created on, each rendered as nothing but a small
/// colored square — same-task blocks share a color (hue hashed from the task
/// title) so streaks on one task are easy to spot at a glance.
class BlocksCalendar extends ConsumerWidget {
  const BlocksCalendar({super.key});

  static Color _colorForTask(String task) {
    final hue = (task.hashCode.abs() % 360).toDouble();
    return HSVColor.fromAHSV(1.0, hue, 0.55, 0.85).toColor();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(noteIndexProvider).value;
    final blocks = <NoteFile>[
      for (final note in index?.entries.values ?? const <NoteFile>[])
        if (note['primaryType'] == 'block') note,
    ];

    if (blocks.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Text('No blocks yet.'),
      );
    }

    final byDay = <DateTime, List<NoteFile>>{};
    for (final block in blocks) {
      final createdAt = DateTime.parse(block['createdAt'] as String).toLocal();
      final day = DateTime(createdAt.year, createdAt.month, createdAt.day);
      (byDay[day] ??= []).add(block);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final day in days) _buildDayRow(context, day, byDay[day]!)],
      ),
    );
  }

  Widget _buildDayRow(BuildContext context, DateTime day, List<NoteFile> blocks) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              DateFormat.MMMd().format(day),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final block in blocks)
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: _colorForTask(block['title'] as String? ?? ''),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
