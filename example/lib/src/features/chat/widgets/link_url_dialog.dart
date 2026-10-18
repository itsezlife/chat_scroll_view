import 'dart:async';

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/material.dart';

/// Asks for a link's URL in the shape of the reference mobile client's
/// "Create Link" dialog: one URL field, prefilled and selected, and a Paste
/// chip over the field while it holds nothing worth keeping.
///
/// Completes with the trimmed URL, or null when the user cancelled or left the
/// field blank.
///
/// - [currentUrl] is the target of the link being edited; the field starts
///   with it and the title says "edit". Without it the field starts with the
///   clipboard's text ([clipboardText], selected, so typing replaces it) or
///   with `http://`.
/// - [clipboardText] is read once, before the dialog opens: the field's first
///   frame already holds what it will hold. A clipboard that fails reads as
///   empty, and the dialog still opens.
Future<String?> showLinkUrlDialog(
  BuildContext context, {
  required Future<String?> Function() clipboardText,
  String? currentUrl,
}) async {
  final clipboard = await _readClipboard(clipboardText);
  if (!context.mounted) return null;
  return showDialog<String>(
    context: context,
    builder: (context) =>
        _LinkUrlDialog(currentUrl: currentUrl, clipboard: clipboard),
  );
}

Future<String?> _readClipboard(Future<String?> Function() read) async {
  try {
    final text = await read();
    return text == null || text.trim().isEmpty ? null : text;
  } on Object catch (error, stackTrace) {
    // No clipboard is no Paste chip, not a dialog that never opens.
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'chat_scroll_view_example',
        context: ErrorDescription('while reading the clipboard for a link'),
      ),
    );
    return null;
  }
}

/// The field's text when the user has typed nothing.
const String _scheme = 'http://';

class _LinkUrlDialog extends StatefulWidget {
  const _LinkUrlDialog({required this.currentUrl, required this.clipboard});

  final String? currentUrl;
  final String? clipboard;

  @override
  State<_LinkUrlDialog> createState() => _LinkUrlDialogState();
}

class _LinkUrlDialogState extends State<_LinkUrlDialog>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _url;

  // 0 hidden, 1 shown: the chip's alpha, and its scale from 0.7.
  late final AnimationController _chip;

  @override
  void initState() {
    super.initState();
    final initial = widget.currentUrl ?? widget.clipboard ?? _scheme;
    _url = TextEditingController(text: initial)
      ..selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
    _chip = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: _chipWanted ? 1 : 0,
    );
    _url.addListener(_onChanged);
  }

  @override
  void dispose() {
    _url.dispose();
    _chip.dispose();
    super.dispose();
  }

  // The chip offers the clipboard while there is nothing in the field but the
  // scheme it started with.
  bool get _chipWanted =>
      widget.clipboard != null && (_url.text.isEmpty || _url.text == _scheme);

  void _onChanged() {
    if (_chipWanted) {
      unawaited(_chip.forward());
    } else {
      unawaited(_chip.reverse());
    }
  }

  void _paste() {
    final text = widget.clipboard;
    if (text == null) return;
    _url.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _submit() {
    final url = _url.text.trim();
    Navigator.of(context).pop(url.isEmpty ? null : url);
  }

  @override
  Widget build(BuildContext context) {
    final strings = ChromeStringsScope.of(context);
    final theme = Theme.of(context);
    final editing = widget.currentUrl != null;
    return AlertDialog(
      title: Text(
        editing
            ? strings.formatting.editLinkAction
            : strings.formatting.createLinkAction,
      ),
      content: SizedBox(
        height: _fieldHeight,
        child: Stack(
          alignment: AlignmentDirectional.centerEnd,
          children: [
            TextField(
              controller: _url,
              autofocus: true,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              style: const TextStyle(fontSize: _fieldText),
              decoration: const InputDecoration(labelText: 'URL'),
              onSubmitted: (_) => _submit(),
            ),
            Positioned.directional(
              textDirection: Directionality.of(context),
              end: 0,
              bottom: _chipBottom,
              child: _PasteChip(
                progress: _chip,
                color: theme.colorScheme.primary,
                onTap: _paste,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.panel.cancelAction),
        ),
        TextButton(onPressed: _submit, child: const Text('OK')),
      ],
    );
  }

  static const double _fieldHeight = 64;
  static const double _fieldText = 18;
  static const double _chipBottom = 10;
}

/// The Paste chip: 12 dp bold text on a 26 dp rounded tint, fading in and
/// growing from 0.7 on the ease-out-quint curve the reference client uses.
class _PasteChip extends StatelessWidget {
  const _PasteChip({
    required this.progress,
    required this.color,
    required this.onTap,
  });

  final Animation<double> progress;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: progress,
      curve: Curves.easeOutQuint,
    );
    return AnimatedBuilder(
      animation: curved,
      builder: (context, child) => IgnorePointer(
        ignoring: progress.value == 0,
        child: Opacity(
          opacity: curved.value.clamp(0.0, 1.0),
          child: Transform.scale(scale: 0.7 + 0.3 * curved.value, child: child),
        ),
      ),
      child: Material(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: SizedBox(
            height: 26,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Center(
                widthFactor: 1,
                child: Text(
                  'Paste',
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
