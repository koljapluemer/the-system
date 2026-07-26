import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../screens/add_screen.dart';
import '../state/note_index_notifier.dart';

/// Pushes the shared Add form (see `add_screen.dart`) to attach a
/// `[label, filename]` relationship to the note at [filename]: its built-in
/// similar-notes suggestions double as the search for an existing note to
/// attach, and typing a new title falls back to creating one — restricted to
/// [allowedPrimaryTypes] (defaults to every type when omitted), locked to a
/// single type when only one is allowed. Either path writes the relationship
/// and its reciprocal mirror (see [NoteIndexNotifier.attachRelationship]).
///
/// The label/reverse label prompt is rendered inline on the same screen as
/// the note picker (see [_RelationshipAddScreen]) rather than as a separate
/// step — that screen owns the label controllers itself so they're disposed
/// exactly when Flutter removes the route (after its pop transition
/// finishes), instead of racing that transition from an external
/// `dispose()` call.
Future<void> showRelationshipDialog(
  BuildContext context,
  WidgetRef ref, {
  required String filename,
  List<String>? allowedPrimaryTypes,
  required String dialogTitle,
}) {
  return Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => _RelationshipAddScreen(
        filename: filename,
        allowedPrimaryTypes: allowedPrimaryTypes,
        dialogTitle: dialogTitle,
      ),
    ),
  );
}

/// Owns the label/reverse-label controllers for the free-text "Add
/// Relationship" flow, so their lifecycle is tied to this widget's own
/// State (created in field initializers, disposed in [dispose]) rather than
/// to a bare function racing the pushed route's pop-transition animation.
class _RelationshipAddScreen extends ConsumerStatefulWidget {
  final String filename;
  final List<String>? allowedPrimaryTypes;
  final String dialogTitle;

  const _RelationshipAddScreen({
    required this.filename,
    required this.allowedPrimaryTypes,
    required this.dialogTitle,
  });

  @override
  ConsumerState<_RelationshipAddScreen> createState() => _RelationshipAddScreenState();
}

class _RelationshipAddScreenState extends ConsumerState<_RelationshipAddScreen> {
  final _labelController = TextEditingController();
  final _reverseLabelController = TextEditingController();

  @override
  void dispose() {
    _labelController.dispose();
    _reverseLabelController.dispose();
    super.dispose();
  }

  Future<void> _attach(String relatedFilename) {
    final label = _labelController.text.trim();
    final reverseLabel = _reverseLabelController.text.trim();
    return ref.read(noteIndexProvider.notifier).attachRelationship(
          filename: widget.filename,
          label: label,
          reverseLabel: reverseLabel.isEmpty ? null : reverseLabel,
          relatedFilename: relatedFilename,
        );
  }

  @override
  Widget build(BuildContext context) {
    return AddScreen(
      allowedTypes: widget.allowedPrimaryTypes,
      appBarTitle: widget.dialogTitle,
      showBackButton: true,
      relationshipLabelController: _labelController,
      relationshipReverseLabelController: _reverseLabelController,
      onSuggestionSelected: (ctx, ref, relatedFilename) async {
        await _attach(relatedFilename);
        if (ctx.mounted) Navigator.pop(ctx);
      },
      onCreated: (ref, createdFilename) => _attach(createdFilename),
    );
  }
}
