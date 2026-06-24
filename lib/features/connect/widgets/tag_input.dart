import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/context_ext.dart';

/// Chip/token tag editor (ADR 0031, D6). Replaces the old comma-separated text
/// field + "Virgülle ayırın" helper. Tags commit on Enter or comma; each chip
/// is removable via its × button or Backspace on an empty field.
///
/// IMPORTANT: a tag still being typed (not yet committed) is NOT lost on submit
/// — the parent reads [TagInputController.tags], which folds the pending text
/// into the list. Reusable so the edit dialog (ADR 0025) can adopt it later.
class TagInputController extends ChangeNotifier {
  final List<String> _tags;
  final TextEditingController text = TextEditingController();

  TagInputController({List<String> initial = const []}) : _tags = [...initial] {
    text.addListener(notifyListeners);
  }

  List<String> get committed => List.unmodifiable(_tags);

  /// The committed tags PLUS any non-empty pending input, deduplicated. This is
  /// what the form should persist so a half-typed tag isn't dropped on submit.
  List<String> get tags {
    final out = [..._tags];
    final pending = text.text.trim();
    if (pending.isNotEmpty && !out.contains(pending)) out.add(pending);
    return out;
  }

  void add(String raw) {
    final t = raw.trim();
    if (t.isEmpty || _tags.contains(t)) return;
    _tags.add(t);
    notifyListeners();
  }

  void remove(String tag) {
    if (_tags.remove(tag)) notifyListeners();
  }

  /// Commits the current pending text as a tag (Enter/comma path).
  void commitPending() {
    final t = text.text.trim();
    if (t.isNotEmpty) add(t);
    text.clear();
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }
}

class TagInput extends StatefulWidget {
  final TagInputController controller;
  final String? helperText;

  const TagInput({
    super.key,
    required this.controller,
    this.helperText = 'Enter veya virgül ile ekleyin (örn. prod, db)',
  });

  @override
  State<TagInput> createState() => _TagInputState();
}

class _TagInputState extends State<TagInput> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    _focus.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  void _onTextChanged(String v) {
    // Commit on a typed comma (paste of "a,b" also splits).
    if (v.contains(',')) {
      final parts = v.split(',');
      // Last part remains pending; everything before a comma commits.
      for (var i = 0; i < parts.length - 1; i++) {
        widget.controller.add(parts[i]);
      }
      widget.controller.text.text = parts.last.trimLeft();
      widget.controller.text.selection = TextSelection.collapsed(
        offset: widget.controller.text.text.length,
      );
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // Backspace on an empty field removes the last chip.
    if (event.logicalKey == LogicalKeyboardKey.backspace &&
        widget.controller.text.text.isEmpty &&
        widget.controller.committed.isNotEmpty) {
      widget.controller.remove(widget.controller.committed.last);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tags = widget.controller.committed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            'Etiketler',
            style: context.ui(
              size: 12,
              weight: FontWeight.w600,
              color: c.textMuted,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: c.bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.border),
          ),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final t in tags) _chip(context, t),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 90, maxWidth: 240),
                child: Focus(
                  focusNode: _focus,
                  onKeyEvent: _onKey,
                  child: TextField(
                    key: const Key('tagInput'),
                    controller: widget.controller.text,
                    style: context.ui(size: 14),
                    cursorColor: c.accent,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: tags.isEmpty ? 'etiket ekle…' : null,
                      hintStyle: context.ui(size: 14, color: c.textDim),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 2,
                      ),
                    ),
                    onChanged: _onTextChanged,
                    onSubmitted: (_) => widget.controller.commitPending(),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (widget.helperText != null) ...[
          const SizedBox(height: 6),
          Text(
            widget.helperText!,
            style: context.ui(size: 11.5, color: c.textDim),
          ),
        ],
      ],
    );
  }

  Widget _chip(BuildContext context, String tag) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.only(left: 10, right: 4, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(tag, style: context.ui(size: 12.5)),
          const SizedBox(width: 2),
          Semantics(
            button: true,
            label: '$tag etiketini kaldır',
            child: Tooltip(
              message: 'Kaldır',
              child: InkWell(
                key: Key('removeTag-$tag'),
                onTap: () => widget.controller.remove(tag),
                child: Icon(Icons.close, size: 14, color: c.textMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
