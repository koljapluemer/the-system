import 'package:chips_input_autocomplete/chips_input_autocomplete.dart';
import 'package:flutter/material.dart';

/// A plaintext input with a smart autocomplete dropdown (sourced from
/// [knownTags]) that adds a removable chip badge for each tag: clicking a
/// suggestion, or typing then pressing space/comma/Enter, commits the
/// current text as a chip. Thin wrapper around the `chips_input_autocomplete`
/// package, reused for both an audio note's own Tags section and the Listen
/// flow's by-tag filter (same widget, different [knownTags]/[onChanged]).
///
/// [tags] only seeds the widget's initial chips — like [ArrayListSection]'s
/// controllers, the chip list is then owned internally and driven purely by
/// user interaction, not re-synced from [tags] on every rebuild. Callers
/// that need to reset the chips externally (e.g. switching to a different
/// note) should give this widget a fresh `key`.
class TagChipInput extends StatefulWidget {
  final List<String> tags;
  final List<String> knownTags;
  final ValueChanged<List<String>> onChanged;

  const TagChipInput({
    super.key,
    required this.tags,
    required this.knownTags,
    required this.onChanged,
  });

  @override
  State<TagChipInput> createState() => _TagChipInputState();
}

class _TagChipInputState extends State<TagChipInput> {
  late final _controller = ChipsAutocompleteController()..options = widget.knownTags;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Commits whatever's currently typed as a chip on Enter — the package
  /// only auto-commits on a `createCharacters` character (space/comma by
  /// default) or on selecting a suggestion, not on Enter with free text.
  void _commitTypedText() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.addChip(text);
    _controller.clearText();
  }

  @override
  Widget build(BuildContext context) {
    return ChipsInputAutocomplete(
      controller: _controller,
      options: widget.knownTags,
      initialChips: widget.tags,
      addChipOnSelection: true,
      onChanged: (chips) => widget.onChanged(chips ?? []),
      onEditingCompleteTextField: _commitTypedText,
      decorationTextField: const InputDecoration(
        border: InputBorder.none,
        contentPadding: EdgeInsets.only(left: 8.0),
        hintText: 'Add tag…',
      ),
    );
  }
}
