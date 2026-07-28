import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'add_screen.dart';
import 'blocks_stats_screen.dart';
import 'flow_navigation.dart';
import 'folder_setup_screen.dart';
import 'invalid_json_screen.dart';
import 'note_type_list_screen.dart';
import '../models/note_type_spec.dart';
import '../state/note_index_notifier.dart';
import '../state/providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _checkForInvalidJson(BuildContext context, WidgetRef ref) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final index = await ref.read(noteIndexProvider.future);
    final invalid = await ref.read(jsonSchemaServiceProvider).findInvalid(index);
    if (!context.mounted) return;
    Navigator.pop(context); // dismiss the progress dialog

    if (invalid.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Nothing found')));
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => InvalidJsonScreen(filenames: invalid)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          IconButton(
            tooltip: 'Change data folder',
            icon: const Icon(Icons.folder_open),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FolderSetupScreen()),
            ),
          ),
        ],
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Add'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AddScreen()),
            ),
          ),
          const Divider(height: 1),
          for (final flow in flowSpecs)
            ListTile(
              title: Text(flow.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => pushFlow(context, ref, flow.id),
            ),
          const Divider(height: 1),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Lists'),
          ),
          for (final spec in noteTypeSpecs)
            ListTile(
              title: Text(spec.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => NoteTypeListScreen(spec: spec)),
              ),
            ),
          const Divider(height: 1),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Stats'),
          ),
          ListTile(
            title: const Text('Blocks'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BlocksStatsScreen()),
            ),
          ),
          const Divider(height: 1),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Maintenance'),
          ),
          ListTile(
            leading: const Icon(Icons.rule_folder),
            title: const Text('Check for invalid JSON files'),
            onTap: () => _checkForInvalidJson(context, ref),
          ),
        ],
      ),
    );
  }
}
