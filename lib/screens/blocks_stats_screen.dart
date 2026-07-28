import 'package:flutter/material.dart';

import '../widgets/blocks_calendar.dart';

/// Pushed from Home's Stats section: the per-calendar-day view of completed
/// blocks (see BlocksCalendar).
class BlocksStatsScreen extends StatelessWidget {
  const BlocksStatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Blocks')),
      body: const SingleChildScrollView(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: BlocksCalendar(),
      ),
    );
  }
}
