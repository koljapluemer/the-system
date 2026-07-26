Internal checklist for adding a new note `primaryType`. Brief — for contributors, not end users.

## Must touch

- `assets/note_schema.json` — add a `oneOf` entry (properties + `required` +
  `additionalProperties: false`). This is the source of truth the app validates against;
  nothing else auto-derives from it.
- `lib/models/note_type_spec.dart` — add a `NoteTypeSpec` entry: `fields` (kept in sync
  with the schema properties above). Every type's Lists screen gets a "new note" FAB
  automatically (`NoteTypeListScreen` isn't gated by any flag) — if the type has state a
  title-only `createFromSpec` create can't set up (e.g. something needing a timestamp
  stamped at creation time), special-case creation in `_AddScreenState._createNote`
  instead.

## Must decide

- **Generic `NoteDetailScreen` vs. a bespoke screen**: `NoteDetailScreen` (inline
  pencil-edit per `fields` entry, plus a unified relationship list) is the default for
  every type, reached via `pushNoteEditor`. No primaryType currently needs more than
  this. Only build a bespoke screen if a future type has state/logic `NoteDetailScreen`
  truly can't express (e.g. a form that isn't a flat set of fields). A bespoke screen
  bypasses `pushNoteEditor` entirely and any fields it manages itself should generally
  be left out of `NoteTypeSpec.fields`, since that list is what the generic form/detail
  screen merges on save — the way `milestone`'s `logs` array and `flashcard`'s `fsrs`
  data are.
- **`secondaryTypes`**: does this type need a constrained sub-type (e.g. `milestone`'s
  `secondaryType` of `open`/`failed`/`soso`/etc.)? If so, add the allowed values to both
  the schema (an `enum` on that type's `secondaryType` property in `note_schema.json`) and
  `NoteTypeSpec.secondaryTypes` here — `NoteDetailScreen` renders a dropdown automatically
  whenever `secondaryTypes` is non-empty. Leave it `[]` (the default) if this type has no
  such concept. Order matters: the **first entry is this type's default** — the value
  stamped onto a newly created note (via `AddScreen`'s secondaryType picker, or
  `NoteIndexNotifier.createFromSpec`'s `secondaryType` param) unless the user picks a
  different value, and unless a value was already chosen this session (see
  `LastSecondaryTypeNotifier` in `lib/state/secondary_type_session.dart`).
  Any type with a non-empty `secondaryTypes` automatically gets a `SecondaryTypeFilterBar`
  (`lib/widgets/secondary_type_filter_bar.dart`) on its list view (`NoteTypeListScreen`)
  for free — no per-type wiring needed beyond this declaration.
- **`defaultVisibleSecondaryTypes`**: which of this type's `secondaryTypes` should be
  visible by default in that filter bar (session-only — see
  `SecondaryTypeFilterNotifier`)? Mirror it in the schema as a `defaultVisible` array
  sibling next to that type's `secondaryType` `enum` (e.g. `milestone`'s
  `"defaultVisible": ["open"]`). Leave both the schema annotation and this Dart field
  omitted/`[]` (the default) if every value should be visible without filtering.
- **Relationships**: nothing to do here — every primaryType automatically gets the
  generic "Add Relationship" button on `NoteDetailScreen` (free-text label, optional
  reverse label, any primaryType as target), with no per-type wiring needed.

## Don't need to touch

- `add_screen.dart` — its type dropdown iterates `noteTypeSpecs` directly, so new types
  appear there automatically, and every type shows up in the Home Lists section the same
  way.
- `note_editor_navigation.dart`, `relationship_dialog.dart` — both generic over any
  `NoteTypeSpec`/relType already.
- Any test file, unless the new type has validation edge cases worth covering in
  `test/json_schema_service_test.dart`.
