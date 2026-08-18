import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:chat_scroll_view_example/src/common/widgets/measure_size.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Max width of the composer content column — the bar background still spans
/// the full width, but the input field / action buttons are centered within.
const double _kComposerMaxWidth = 620;

/// Bottom bar for the widget-based chat demo.
///
/// Idle: a rounded multi-line input field pinned to the bottom.
/// Selection mode: the input field slides down out of view while
/// copy / favorite / share icon buttons fly in from the sides.
class ChatComposer extends StatefulWidget {
  /// Bottom input bar that morphs into selection actions when [selection] is
  /// active.
  const ChatComposer({
    required this.selection,
    required this.dataSource,
    required this.onSend,
    this.onDeleteSelected,
    this.onEditSelected,
    this.onSizeChanged,
    this.bottomInset,
    super.key,
  });

  /// Drives the input ⇄ actions transition.
  final ChatSelectionController selection;

  /// Source for message text when copying a selection to the clipboard.
  final ChatDataSource dataSource;

  /// Persists a trimmed message; throw on failure to retain composer text.
  final Future<void> Function(String text) onSend;

  /// Deletes the currently selected message ids via the data-source CRUD API.
  final void Function(Iterable<int> ids)? onDeleteSelected;

  /// Saves edited content for [messageId]; only invoked for single-message edit.
  final Future<void> Function(int messageId, String text)? onEditSelected;

  /// Safe area bottom inset reserved inside the viewport — kept in sync with the
  /// safe area bottom inset so the composer's measured height clears it.
  final ValueNotifier<double>? bottomInset;

  /// Callback to notify the parent of the composer's measured height.
  final void Function(double height)? onSizeChanged;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer>
    with SingleTickerProviderStateMixin {
  /// 0 → input field shown, 1 → action buttons shown.
  late final AnimationController _t;
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();

  /// Every [CurvedAnimation] built off [_t] — disposed together.
  final List<CurvedAnimation> _curves = <CurvedAnimation>[];

  late final Animation<Offset> _inputSlide;
  late final Animation<double> _inputFade;
  late final Animation<Offset> _copySlide;
  late final Animation<Offset> _shareSlide;
  late final Animation<double> _favScale;
  late final Animation<double> _actionsFade;

  bool _mode = false;
  bool _sending = false;

  /// When set, [onEditSelected] is called instead of [onSend] on submit.
  int? _editingMessageId;

  CurvedAnimation _curve(Curve curve) {
    final ca = CurvedAnimation(parent: _t, curve: curve);
    _curves.add(ca);
    return ca;
  }

  @override
  void initState() {
    super.initState();
    _t = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
    );
    // Input field: drops straight down and fades out early.
    _inputSlide = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, 1.4),
    ).animate(_curve(Curves.easeInCubic));
    _inputFade = Tween<double>(
      begin: 1,
      end: 0,
    ).animate(_curve(const Interval(0, 0.5, curve: Curves.easeIn)));
    // Action buttons: copy from the left, share from the right, favorite pops
    // up in the middle — all slightly staggered with an ease-out overshoot.
    _copySlide = Tween<Offset>(
      begin: const Offset(-2.6, 0),
      end: Offset.zero,
    ).animate(_curve(const Interval(0.15, 0.9, curve: Curves.easeOutBack)));
    _shareSlide = Tween<Offset>(
      begin: const Offset(2.6, 0),
      end: Offset.zero,
    ).animate(_curve(const Interval(0.15, 0.9, curve: Curves.easeOutBack)));
    _favScale = _curve(const Interval(0.3, 1, curve: Curves.easeOutBack));
    _actionsFade = _curve(const Interval(0.28, 0.62));

    _mode = widget.selection.isSelectionMode;
    if (_mode) _t.value = 1.0;
    widget.selection.addListener(_onSelectionChanged);
  }

  @override
  void didUpdateWidget(ChatComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.selection, widget.selection)) {
      oldWidget.selection.removeListener(_onSelectionChanged);
      widget.selection.addListener(_onSelectionChanged);
      _onSelectionChanged();
    }
  }

  @override
  void dispose() {
    widget.selection.removeListener(_onSelectionChanged);
    for (final c in _curves) {
      c.dispose();
    }
    _t.dispose();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onSelectionChanged() {
    final mode = widget.selection.isSelectionMode;
    if (mode && _editingMessageId != null) {
      _text.clear();
      _editingMessageId = null;
    }
    if (mode != _mode) {
      setState(() => _mode = mode);
      if (mode) {
        _focus.unfocus();
        _t.forward();
      } else {
        _t.reverse();
      }
    } else if (mode) {
      setState(() {});
    }
  }

  void _clearEditing() {
    if (_editingMessageId == null) return;
    setState(() => _editingMessageId = null);
  }

  Future<void> _handleSend() async {
    if (_sending) return;
    final text = _text.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      final editingId = _editingMessageId;
      if (editingId != null) {
        await widget.onEditSelected?.call(editingId, text);
        if (!mounted) return;
        _editingMessageId = null;
      } else {
        await widget.onSend(text);
        if (!mounted) return;
      }
      _text.clear();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // --- Selection actions -----------------------------------------------------

  static String? _contentOf(IChatMessage? message) => switch (message) {
    UserChatMessage(:final content) => content,
    SystemChatMessage(:final content) => content,
    _ => null,
  };

  void _copy() {
    final ids = widget.selection.selectedIds.toList()..sort();
    final buffer = StringBuffer();
    for (final id in ids) {
      final text = _contentOf(widget.dataSource.getMessage(id));
      if (text == null) continue;
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.write(text);
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    _finish('Скопировано сообщений: ${ids.length}');
  }

  void _deleteSelected() {
    final ids = widget.selection.selectedIds;
    if (ids.isEmpty) return;
    widget.onDeleteSelected?.call(ids);
    _finish('Удалено сообщений: ${ids.length}');
  }

  void _startEditSelected() {
    if (widget.selection.count != 1) return;
    final id = widget.selection.selectedIds.first;
    final content = _contentOf(widget.dataSource.getMessage(id));
    if (content == null) {
      _finish('Нельзя редактировать это сообщение');
      return;
    }
    widget.selection.clear();
    setState(() {
      _editingMessageId = id;
      _text.text = content;
    });
    _t.reverse();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _cancelEdit() {
    _text.clear();
    _clearEditing();
  }

  void _finish([String? message]) {
    if (message case final message?) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 2),
          ),
        );
    }
    widget.selection.clear();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom;
    final selectionCount = widget.selection.count;
    final canEdit = selectionCount == 1 && widget.onEditSelected != null;
    final canDelete = selectionCount >= 1 && widget.onDeleteSelected != null;
    final isEditing = _editingMessageId != null;

    final child = MeasureSize(
      onChange: (size) => widget.onSizeChanged?.call(size.height),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _kComposerMaxWidth),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: ClipRect(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.3),
                      width: 0.5,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 66),
                      child: Stack(
                        alignment: Alignment.bottomCenter,
                        children: <Widget>[
                          // Input layer — sizes the bar.
                          SlideTransition(
                            position: _inputSlide,
                            child: FadeTransition(
                              opacity: _inputFade,
                              child: IgnorePointer(
                                ignoring: _mode,
                                child: _InputField(
                                  controller: _text,
                                  focusNode: _focus,
                                  onSend: _handleSend,
                                  sending: _sending,
                                  scheme: scheme,
                                  hintText: isEditing
                                      ? 'Редактирование'
                                      : 'Сообщение',
                                  isEditing: isEditing,
                                  onCancelEdit: _cancelEdit,
                                ),
                              ),
                            ),
                          ),
                          // Action layer — overlaid, fades / flies in.
                          Positioned.fill(
                            child: IgnorePointer(
                              ignoring: !_mode,
                              child: FadeTransition(
                                opacity: _actionsFade,
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: <Widget>[
                                    SlideTransition(
                                      position: _copySlide,
                                      child: _ActionButton(
                                        icon: Icons.copy_rounded,
                                        label: 'Копировать',
                                        onTap: _copy,
                                        scheme: scheme,
                                      ),
                                    ),
                                    if (canEdit)
                                      ScaleTransition(
                                        scale: _favScale,
                                        child: _ActionButton(
                                          icon: Icons.edit_rounded,
                                          label: 'Изменить',
                                          onTap: _startEditSelected,
                                          scheme: scheme,
                                        ),
                                      ),
                                    if (canDelete)
                                      SlideTransition(
                                        position: _shareSlide,
                                        child: _ActionButton(
                                          icon: Icons.delete_outline_rounded,
                                          label: 'Удалить',
                                          onTap: _deleteSelected,
                                          scheme: scheme,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final bottomInset = widget.bottomInset;
    if (bottomInset == null) {
      return child;
    }

    return ValueListenableBuilder(
      valueListenable: bottomInset,
      child: child,
      builder: (context, bottomInset, child) => Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: child,
      ),
    );
  }
}

/// The rounded multi-line input pill with a trailing send button.
class _InputField extends StatelessWidget {
  const _InputField({
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.sending,
    required this.scheme,
    required this.isEditing,
    this.hintText = 'Сообщение',
    this.onCancelEdit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final Future<void> Function() onSend;
  final bool sending;
  final ColorScheme scheme;
  final String hintText;
  final bool isEditing;
  final VoidCallback? onCancelEdit;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 6, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          if (isEditing && onCancelEdit != null) ...<Widget>[
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: _CircleButton(
                icon: Icons.close_rounded,
                size: 38,
                background: scheme.surfaceContainerHigh,
                foreground: scheme.onSurfaceVariant,
                onTap: onCancelEdit,
              ),
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                minLines: 1,
                maxLines: 6,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                cursorColor: scheme.primary,
                style: TextStyle(color: scheme.onSurface, fontSize: 15),
                decoration: InputDecoration.collapsed(
                  hintText: hintText,
                  hintStyle: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: _CircleButton(
              icon: isEditing ? Icons.check_rounded : Icons.send_rounded,
              size: 38,
              background: scheme.primary,
              foreground: scheme.onPrimary,
              onTap: sending ? null : onSend,
            ),
          ),
        ],
      ),
    ),
  );
}

/// A labelled circular action button (copy / favorite / share).
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.scheme,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      _CircleButton(
        icon: icon,
        size: 46,
        background: scheme.primary.withValues(alpha: 0.16),
        foreground: scheme.primary,
        onTap: onTap,
      ),
      const SizedBox(height: 4),
      Text(
        label,
        style: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    ],
  );
}

/// A circular icon button with an ink ripple.
class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.size,
    required this.background,
    required this.foreground,
    this.onTap,
  });

  final IconData icon;
  final double size;
  final Color background;
  final Color foreground;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: background,
    shape: const CircleBorder(),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(icon, color: foreground, size: size * 0.5),
      ),
    ),
  );
}
