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

  /// Size of the text in the [AttachDeniedForm.text] form.
  static const double textSize = 15;

  /// Size of the text in the [AttachDeniedForm.emptyState] form.
  static const double emptyStateSize = 16;

  /// Space around the text in the [AttachDeniedForm.text] form: the page's
  /// side gutter, and room above and below.
  static const EdgeInsetsDirectional textPadding =
      EdgeInsetsDirectional.fromSTEB(16, 24, 16, 24);

  /// Space beside the centred text of the [AttachDeniedForm.emptyState]
  /// form.
  static const EdgeInsets emptyStatePadding = EdgeInsets.symmetric(
    horizontal: 32,
  );

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
              AttachDeniedForm.text => textSize,
              AttachDeniedForm.emptyState => emptyStateSize,
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
              padding: textPadding,
              child: Align(
                alignment: AlignmentDirectional.topStart,
                child: label,
              ),
            ),
            AttachDeniedForm.emptyState => Padding(
              padding: emptyStatePadding,
              child: Center(child: label),
            ),
          },
        ),
      ),
    );
  }
}
