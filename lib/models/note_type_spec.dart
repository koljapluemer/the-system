/// Describes one note primaryType's core editable fields, driving the Lists
/// overview, per-type list, and generic edit form. Keep in sync with
/// assets/note_schema.json.
class NoteFieldSpec {
  final String key;
  final String label;
  final bool multiline;
  final bool required;

  const NoteFieldSpec({
    required this.key,
    required this.label,
    this.multiline = false,
    this.required = false,
  });
}

class NoteTypeSpec {
  final String primaryType;
  final String label;
  final List<NoteFieldSpec> fields;

  /// Allowed values for this primaryType's optional `secondaryType` field,
  /// mirrored in this primaryType's `enum` in `note_schema.json`. Empty by
  /// default — this primaryType has no secondaryType concept, and
  /// [NoteDetailScreen] won't render a secondaryType picker for it. Order
  /// matters: the first entry is this type's default secondaryType, assigned
  /// to new notes unless the user picks otherwise.
  final List<String> secondaryTypes;

  /// The secondaryType values shown by default in this type's list-view
  /// filter, mirrored in the `defaultVisible` annotation beside this type's
  /// `secondaryType` property in `note_schema.json`. Empty by default —
  /// meaning "no restriction", i.e. every value in [secondaryTypes] is shown
  /// by default — matching the schema convention of omitting `defaultVisible`
  /// entirely rather than redundantly listing every value.
  final List<String> defaultVisibleSecondaryTypes;

  /// [defaultVisibleSecondaryTypes], resolved against the "empty means show
  /// all" convention above.
  List<String> get effectiveDefaultVisible =>
      defaultVisibleSecondaryTypes.isEmpty ? secondaryTypes : defaultVisibleSecondaryTypes;

  /// The secondaryType assigned to a new note of this type unless the user
  /// picks otherwise — the first entry in [secondaryTypes]. Only call this
  /// when [secondaryTypes] is non-empty.
  String get defaultSecondaryType => secondaryTypes.first;

  /// Whether this type's view screen renders a dedicated expandable "Logs"
  /// section (see `lib/widgets/logs_section.dart`): the note's own `logs`
  /// array (`{content, createdAt}` entries, kept outside [fields] the same
  /// way `flashcard`'s `fsrs` is), newest first, plus an inline "Add Log"
  /// field. False by default — opt in per type.
  final bool showLogs;

  /// Whether this type's view screen renders a read-only expandable
  /// "Answers" section (see `lib/widgets/answers_section.dart`): the note's
  /// own `answers` array (`{text, createdAt}` entries, kept outside [fields]
  /// the same way `flashcard`'s `fsrs` is), newest first. Unlike [showLogs],
  /// there's no inline "add" control — an answer is only ever recorded by
  /// completing the Prompts flow, which also stamps `lastShownAt`. False by
  /// default — opt in per type.
  final bool showAnswers;

  /// Whether this type's view screen renders a "Tags" section (see
  /// `lib/widgets/tag_chip_input.dart`): the note's own `tags` array, edited
  /// via a chip input that autocompletes against every other note of this
  /// type's tags. Kept outside [fields] the same way `flashcard`'s `fsrs` is.
  /// False by default — opt in per type.
  final bool showTags;

  /// Whether this type's view screen renders an "Audio File" section: the
  /// note's own `audioFile` filename (resolved under a parallel `audio/`
  /// folder in the data folder, mirroring `art`'s `image`/`media/`
  /// convention), attached via a file picker rather than typed in directly.
  /// Kept outside [fields] the same way `flashcard`'s `fsrs` is. False by
  /// default — opt in per type.
  final bool showAudioFile;

  const NoteTypeSpec({
    required this.primaryType,
    required this.label,
    required this.fields,
    this.secondaryTypes = const [],
    this.defaultVisibleSecondaryTypes = const [],
    this.showLogs = false,
    this.showAnswers = false,
    this.showTags = false,
    this.showAudioFile = false,
  });
}

const noteTypeSpecs = [
  NoteTypeSpec(
    primaryType: 'art',
    label: 'Art',
    fields: [
      NoteFieldSpec(key: 'title', label: 'Title', required: true),
      NoteFieldSpec(key: 'content', label: 'Content', multiline: true, required: true),
      NoteFieldSpec(key: 'image', label: 'Image (filename)'),
    ],
  ),
  NoteTypeSpec(
    primaryType: 'milestone',
    label: 'Milestone',
    secondaryTypes: ['open', 'failed', 'soso', 'success'],
    defaultVisibleSecondaryTypes: ['open'],
    showLogs: true,
    fields: [
      NoteFieldSpec(key: 'title', label: 'Title', required: true),
      NoteFieldSpec(key: 'content', label: 'Content', multiline: true),
    ],
  ),
  NoteTypeSpec(
    primaryType: 'activity',
    label: 'Activity',
    fields: [
      NoteFieldSpec(key: 'title', label: 'Title', required: true),
      NoteFieldSpec(key: 'content', label: 'Content', multiline: true),
    ],
  ),
  // fsrs learning data (see lib/services/fsrs_service.dart) is deliberately
  // left out of `fields` — it's managed by the Memorize flow directly, not
  // the generic merge-on-save.
  NoteTypeSpec(
    primaryType: 'flashcard',
    label: 'Flashcard',
    fields: [
      NoteFieldSpec(key: 'title', label: 'Title', required: true),
      NoteFieldSpec(key: 'front', label: 'Front', multiline: true, required: true),
      NoteFieldSpec(key: 'back', label: 'Back', multiline: true, required: true),
    ],
  ),
  // lastShownAt/answers (see lib/services/prompt_service.dart) are
  // deliberately left out of `fields` — they're managed by the Prompts flow
  // directly, not the generic merge-on-save.
  NoteTypeSpec(
    primaryType: 'prompt',
    label: 'Prompt',
    showAnswers: true,
    fields: [
      NoteFieldSpec(key: 'title', label: 'Prompt', multiline: true, required: true),
      NoteFieldSpec(key: 'interval', label: 'Interval (days)'),
    ],
  ),
  // createdAt (see lib/state/note_index_notifier.dart's createBlock) is
  // deliberately left out of `fields` — it's stamped once at creation by the
  // Make a Block flow, not managed via the generic merge-on-save.
  NoteTypeSpec(
    primaryType: 'block',
    label: 'Block',
    fields: [
      NoteFieldSpec(key: 'title', label: 'Task', required: true),
    ],
  ),
  NoteTypeSpec(
    primaryType: 'frog',
    label: 'Frog',
    fields: [
      NoteFieldSpec(key: 'title', label: 'Title', required: true),
    ],
  ),
  // audioFile/tags/lastListenedAt/hiddenUntil/neverListen (see
  // lib/services/audio_listen_service.dart and lib/state/listen_notifier.dart)
  // are deliberately left out of `fields` — they're managed by the Attach
  // Audio File/Tags sections and the Listen flow directly, not the generic
  // merge-on-save.
  NoteTypeSpec(
    primaryType: 'audio',
    label: 'Audio',
    showTags: true,
    showAudioFile: true,
    fields: [
      NoteFieldSpec(key: 'title', label: 'Title', required: true),
      NoteFieldSpec(key: 'content', label: 'Content', multiline: true),
    ],
  ),
];
