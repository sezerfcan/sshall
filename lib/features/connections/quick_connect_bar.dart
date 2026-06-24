import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/connection.dart';
import '../../theme/app_colors.dart';
import '../../theme/context_ext.dart';
import '../../widgets/app_text_field.dart';
import '../connect/widgets/host_paste_parser.dart';
import 'quick_suggestions.dart';
import 'quick_suggestions_dropdown.dart';

/// Omnibox-style Quick Connect bar (ADR 0034). Parses a free-form target with
/// the CANONICAL [parseHostPaste] (the old weaker local `parseTarget` is gone),
/// connects valid targets EPHEMERALLY by default (the routing decision lives in
/// the host view, reached via [onConnectTarget]), and offers recents + saved
/// hosts as autocomplete suggestions.
///
/// Affordances (D1/D3/D4/D6): a mono placeholder that teaches the grammar; a
/// low-emphasis help (?) popover listing accepted forms; a trailing clear (x)
/// shown only when non-empty; a leading bolt that swaps to a spinner while a
/// quick-connect is in flight; inline host/port validation; and a sectioned
/// suggestions dropdown with keyboard navigation.
class QuickConnectBar extends StatefulWidget {
  /// Called with a raw/typed target string to connect (the view parses it again
  /// to route ephemeral-saved vs. dialog-fallback — ADR 0034 D2). Returns a
  /// future that completes when the connect attempt finishes, so the bar can
  /// show/hide the leading spinner.
  final Future<void> Function(String target) onConnectTarget;

  /// Recents (most-recent-first `user@host:port` strings) — ADR 0034 D4.
  final List<String> recents;

  /// Saved hosts feeding the "KAYITLI HOSTLAR" suggestions.
  final List<Connection> saved;

  /// Suggestion display/target/host projections for a saved [Connection].
  final String Function(Connection) displayOf;
  final String Function(Connection) targetOf;
  final String Function(Connection) hostOf;

  /// Remove a single recent / clear all recents (D4).
  final ValueChanged<String> onRemoveRecent;
  final VoidCallback onClearHistory;

  const QuickConnectBar({
    super.key,
    required this.onConnectTarget,
    required this.recents,
    required this.saved,
    required this.displayOf,
    required this.targetOf,
    required this.hostOf,
    required this.onRemoveRecent,
    required this.onClearHistory,
  });

  @override
  State<QuickConnectBar> createState() => _QuickConnectBarState();
}

class _QuickConnectBarState extends State<QuickConnectBar> {
  final _controller = TextEditingController();
  late final FocusNode _focusNode;

  /// Inline validation error shown under the bar (D3). Null = no error.
  String? _error;

  /// A brief inline hint shown when submitting an empty bar with no history
  /// (D3) — distinct from [_error] so it is NOT styled as a hard error.
  String? _hint;

  /// Whether the suggestions dropdown is open.
  bool _open = false;

  /// Keyboard highlight index into [_suggestions]; -1 = nothing highlighted.
  int _highlight = -1;

  /// Whether a quick-connect is in flight (leading bolt → spinner).
  bool _inFlight = false;

  /// The single Esc-press already closed the dropdown; a second clears (D4).
  bool _escArmed = false;

  List<Suggestion> _suggestions = const [];

  @override
  void initState() {
    super.initState();
    // Attach the omnibox key handler to the field's own node so arrow/enter/
    // tab/esc are intercepted BEFORE the TextField consumes them (caret moves).
    _focusNode = FocusNode(onKeyEvent: _onKey);
    _focusNode.addListener(_onFocusChange);
    _controller.addListener(_onTextChange);
  }

  @override
  void didUpdateWidget(covariant QuickConnectBar old) {
    super.didUpdateWidget(old);
    // Recents/saved may change under us (a connect just landed); refresh the
    // open dropdown so it stays current.
    if (_open) _recomputeSuggestions();
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChange);
    _focusNode.removeListener(_onFocusChange);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // --- suggestions ----------------------------------------------------------

  void _recomputeSuggestions() {
    _suggestions = buildSuggestions(
      query: _controller.text,
      recents: widget.recents,
      saved: widget.saved,
      displayOf: widget.displayOf,
      targetOf: widget.targetOf,
      hostOf: widget.hostOf,
    );
    if (_highlight >= _suggestions.length) _highlight = -1;
  }

  void _openDropdown() {
    _recomputeSuggestions();
    setState(() {
      _open = _suggestions.isNotEmpty;
      _highlight = -1;
      _escArmed = false;
    });
  }

  void _closeDropdown() {
    if (!_open) return;
    setState(() {
      _open = false;
      _highlight = -1;
    });
  }

  // --- listeners ------------------------------------------------------------

  void _onFocusChange() {
    if (_focusNode.hasFocus && _controller.text.isEmpty) {
      _openDropdown();
    } else if (!_focusNode.hasFocus) {
      _closeDropdown();
    }
  }

  void _onTextChange() {
    // Live-clear a hard error as soon as the input becomes valid again (D3).
    if (_error != null || _hint != null) {
      setState(() {
        _error = null;
        _hint = null;
      });
    }
    _escArmed = false;
    if (_focusNode.hasFocus) {
      _recomputeSuggestions();
      setState(() => _open = _suggestions.isNotEmpty);
    }
    setState(() {}); // refresh the clear (x) visibility
  }

  // --- validation + submit (D3) ---------------------------------------------

  /// Validates a raw target. Returns an error message for a HARD error (no host
  /// or out-of-range port), or null when it is connectable OR merely
  /// "incomplete but valid" (a host with no credential — the view falls back to
  /// the dialog silently, so that is NOT an error here).
  String? _validate(String raw) {
    final parsed = parseHostPaste(raw);
    if (parsed.host == null || parsed.host!.isEmpty) {
      return 'Metinde bir host bulunamadı';
    }
    final port = parsed.port;
    if (port != null && (port < 1 || port > 65535)) {
      return 'Port 1–65535 olmalı';
    }
    return null;
  }

  Future<void> _submit(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) {
      // Empty submit must never be a silent no-op (D3): open recents if any,
      // else show a brief inline hint.
      _recomputeSuggestions();
      if (_suggestions.isNotEmpty) {
        setState(() {
          _open = true;
          _hint = null;
        });
      } else {
        setState(() => _hint = 'Bir host yazın: kullanıcı@host:port');
      }
      return;
    }

    final err = _validate(text);
    if (err != null) {
      // Keep the text + focus on error (D3).
      setState(() {
        _error = err;
        _open = false;
      });
      _focusNode.requestFocus();
      return;
    }

    await _connect(text);
  }

  Future<void> _connect(String target) async {
    setState(() {
      _open = false;
      _inFlight = true;
      _error = null;
      _hint = null;
    });
    try {
      await widget.onConnectTarget(target);
    } finally {
      if (mounted) setState(() => _inFlight = false);
    }
  }

  // --- keyboard model (D4) --------------------------------------------------

  void _moveHighlight(int delta) {
    if (!_open || _suggestions.isEmpty) return;
    setState(() {
      final n = _suggestions.length;
      _highlight = (_highlight + delta) % n;
      if (_highlight < 0) _highlight += n;
    });
  }

  /// Tab / Right: accept the highlighted suggestion into the field (D4).
  void _acceptHighlightedIntoField() {
    if (!_open || _highlight < 0 || _highlight >= _suggestions.length) return;
    final s = _suggestions[_highlight];
    _controller.text = s.target;
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
    setState(() {});
  }

  void _onEscape() {
    if (_open) {
      _closeDropdown();
      _escArmed = true;
    } else if (_escArmed && _controller.text.isNotEmpty) {
      _controller.clear();
      _escArmed = false;
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      if (!_open) {
        _openDropdown();
      } else {
        _moveHighlight(1);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveHighlight(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      _onEscape();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab || key == LogicalKeyboardKey.arrowRight) {
      // Only intercept when a suggestion is highlighted; otherwise let Tab move
      // focus / Right move the caret normally.
      if (_open && _highlight >= 0) {
        _acceptHighlightedIntoField();
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (_open && _highlight >= 0 && _highlight < _suggestions.length) {
        // Connect the highlighted suggestion (saved → ephemeral via the view).
        _connect(_suggestions[_highlight].target);
      } else {
        _submit(_controller.text);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // --- clear (x) ------------------------------------------------------------

  void _clear() {
    _controller.clear();
    _error = null;
    _hint = null;
    _focusNode.requestFocus(); // keep focus (D1)
    _openDropdown(); // reopen recents
  }

  // --- help popover (D1/§9) -------------------------------------------------

  void _showHelp() {
    final c = context.c;
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: c.elevated,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Kabul edilen biçimler',
                  style: context.ui(size: 14, weight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                for (final line in const [
                  'host',
                  'kullanıcı@host',
                  'kullanıcı@host:port',
                  'ssh user@host -p N',
                  '[2001:db8::1]  (IPv6)',
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(line, style: context.mono(size: 12.5)),
                  ),
                const SizedBox(height: 8),
                Text(
                  'Kayıtlı bir host yazarsanız doğrudan (geçici) bağlanır; '
                  'yeni bir host için form açılır.',
                  style: context.ui(size: 11.5, color: c.textMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final hasText = _controller.text.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: 'Hızlı bağlan: kullanıcı@host:port veya ssh komutu yazın',
          textField: true,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.bg,
              borderRadius: _open
                  ? const BorderRadius.vertical(top: Radius.circular(10))
                  : BorderRadius.circular(10),
              border: Border.all(color: _error != null ? c.red : c.border),
            ),
            child: Row(
              children: [
                _leadingIcon(c),
                const SizedBox(width: 12),
                Expanded(
                  child: AppTextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    mono: true,
                    fieldKey: const Key('quickConnectInput'),
                    hintText: 'kullanıcı@host:port · ssh user@host -p 22',
                    onSubmitted: _submit,
                    suffixIcon: hasText
                        ? Tooltip(
                            message: 'Temizle',
                            child: GestureDetector(
                              key: const Key('quickConnectClear'),
                              behavior: HitTestBehavior.opaque,
                              onTap: _clear,
                              child: Icon(
                                Icons.close,
                                size: 16,
                                color: c.textMuted,
                              ),
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Kabul edilen biçimler',
                  child: GestureDetector(
                    key: const Key('quickConnectHelp'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _showHelp,
                    child: Icon(Icons.help_outline, size: 17, color: c.textDim),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_open)
          QuickSuggestionsDropdown(
            suggestions: _suggestions,
            highlightedIndex: _highlight,
            onSelect: (s) => _connect(s.target),
            onRemoveRecent: widget.onRemoveRecent,
            onClearHistory: widget.onClearHistory,
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              _error!,
              key: const Key('quickConnectError'),
              style: context.ui(size: 11.5, color: c.red),
            ),
          ),
        if (_hint != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              _hint!,
              key: const Key('quickConnectHint'),
              style: context.ui(size: 11.5, color: c.textMuted),
            ),
          ),
      ],
    );
  }

  Widget _leadingIcon(AppColors c) => Container(
    width: 34,
    height: 34,
    decoration: BoxDecoration(
      color: c.accentSoft,
      borderRadius: BorderRadius.circular(8),
    ),
    child: _inFlight
        ? Padding(
            key: const Key('quickConnectSpinner'),
            padding: const EdgeInsets.all(9),
            child: CircularProgressIndicator(strokeWidth: 2, color: c.accent),
          )
        : Icon(Icons.bolt, size: 17, color: c.accent),
  );
}
