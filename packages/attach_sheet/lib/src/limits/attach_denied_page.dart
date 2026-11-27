import 'package:attach_sheet/src/policy/attach_sheet_policy.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';

/// A page's content in place of a kind the chat denies: the host's denial
/// [text], drawn in the policy's [form].
///
/// The text is one focusable text node, so a screen reader stops on it,
/// and it starts on the reading side (it mirrors in a right-to-left chat).
/// A null [text] is the silent form: the page stays empty. The content
/// scrolls on [controller] (the page's), so a drag on it still moves the
/// sheet.
class AttachDeniedPage extends StatelessWidget {
  /// The denied page of [text] in [form].
  const AttachDeniedPage({
    required this.text,
    required this.form,
    this.controller,
    super.key,
  });

  /// The host's denial text; null for the silent form.
  final String? text;

  /// How the text stands in the page.
  final AttachDeniedForm form;

  /// The page's scroll controller.
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final palette = ChromeThemeScope.paletteOf(context);
    final label = switch (text) {
      final text? => Semantics(
        container: true,
        focusable: true,
        child: Text(
          text,
          key: const ValueKey('attach-denied-text'),
          textAlign: switch (form) {
            AttachDeniedForm.text => TextAlign.start,
            AttachDeniedForm.emptyState => TextAlign.center,
          },
          style: ChromeTypography.of(context).copyWith(
            color: palette.onSurfaceMuted,
            fontSize: switch (form) {
              AttachDeniedForm.text => 15,
              AttachDeniedForm.emptyState => 16,
            },
          ),
        ),
      ),
      null => null,
    };
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        controller: controller,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: constraints.maxWidth,
            minHeight: constraints.maxHeight,
          ),
          child: switch (form) {
            AttachDeniedForm.text => Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 24, 16, 24),
              child: Align(
                alignment: AlignmentDirectional.topStart,
                child: label,
              ),
            ),
            AttachDeniedForm.emptyState => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Center(child: label),
            ),
          },
        ),
      ),
    );
  }
}
