import 'dart:async';

import 'package:attach_model/attach_model.dart';
import 'package:attach_sheet/src/files/intake_items.dart';
import 'package:attach_sheet/src/host/attach_sheet_host.dart';
import 'package:attach_sheet/src/limits/attach_capabilities.dart';
import 'package:attach_sheet/src/panel/attach_send_controller.dart';
import 'package:attach_sheet/src/policy/attach_sheet_policy.dart';
import 'package:attach_sheet/src/policy/confirm_box_style.dart';
import 'package:attach_sheet/src/prepare/attach_preparation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:mpx_library/mpx_library.dart';

/// The state of one **confirm box**: the open's selection, the panel
/// (caption, options, send), and how files get in.
///
/// One box at a time: the host keeps the controller of the box that is
/// open and sends every later route (the dialog again, a drop, a paste) to
/// [addFiles] rather than opening a second box. [isOpen] says whether it is
/// still up.
final class ConfirmBoxController {
  /// A box under [policy] over [selection].
  ConfirmBoxController({
    required this.policy,
    required this.selection,
    required this.intake,
    this.host = const AttachSheetHost(),
    RichText initialCaption = RichText.empty,
    this.store,
    this.preparation,
    bool? asFiles,
    IntakeItems? items,
    AttachCapabilities? capabilities,
  }) : items = items ?? IntakeItems(),
       style =
           policy.confirmBox ?? const AttachSheetPolicy.desktop().confirmBox! {
    panel = AttachSendController(
      selection: selection,
      policy: policy,
      host: host,
      initialCaption: initialCaption,
      initialOptions: SendOptions(asFiles: asFiles ?? false),
      onSend: (request) => _$onSend?.call(request),
      capabilities: capabilities,
    );
    _$initial = panel.options.value;
    if (store case final store?) {
      unawaited(
        store.restore(_$initial).then((restored) {
          // An entry's choice (the "File" menu entry, the drop zone) wins
          // over what was remembered.
          final next = asFiles == null
              ? restored
              : restored.copyWith(asFiles: asFiles);
          _$initial = next;
          panel.options.value = next;
        }),
      );
    }
  }

  /// The family's values.
  final AttachSheetPolicy policy;

  /// The box's values.
  final ConfirmBoxStyle style;

  /// The open's selection (a desktop or web attach policy: no cap).
  final AttachSelection selection;

  /// The file dialog, for Add and Ctrl/Cmd+O.
  final FileIntake intake;

  /// Feedback and pickers.
  final AttachSheetHost host;

  /// Prepares a send before the box closes; null to leave it to the host.
  final AttachPreparation? preparation;

  /// The share of a send prepared so far; null while not preparing.
  final ValueNotifier<double?> preparing = ValueNotifier(null);

  /// Where the options are remembered (desktop: only with "Remember").
  final SendOptionStore? store;

  /// The intake files behind the items.
  final IntakeItems items;

  /// The caption, options and send.
  late final AttachSendController panel;

  SendOptions _$initial = const SendOptions();
  ValueChanged<SendRequest>? _$onSend;

  /// Whether "Remember" is ticked.
  final ValueNotifier<bool> remember = ValueNotifier(false);

  /// Whether the box is up.
  bool get isOpen => _$onSend != null;

  /// The options when the box opened, for "Remember"'s visibility.
  SendOptions get initialOptions => _$initial;

  /// Which options the box shows now.
  SendOptionVisibility get visibility => SendOptionVisibility(
    items: selection.items,
    caption: panel.caption.richText,
    options: panel.options.value,
    initial: _$initial,
    policy: selection.policy,
    limits: selection.limits,
  );

  /// Adds [files] to the box, classified as media or files; each refusal
  /// goes to the host. On the web an item already in the box (same name,
  /// size and modified time) is skipped.
  void addFiles(Iterable<IntakeFile> files) {
    for (final file in files) {
      if (style.dedupesByFacts && _holds(file)) continue;
      final item = items.itemOf(file, asMedia: true);
      if (selection.contains(item.id)) continue;
      // Each file is its own attach: a denied kind is reported per file.
      if (selection.toggle(item) case AttachToggle$Refused(:final reason)) {
        panel.refused(item, reason, guarded: false);
      }
    }
  }

  bool _holds(IntakeFile file) => selection.items.any(
    (item) => switch (items.fileOf(item.id)) {
      final held? => held.dedupKey == file.dedupKey,
      null => false,
    },
  );

  /// Opens the file dialog and adds what comes back.
  Future<void> pickAndAdd() async => addFiles(
    await intake.pickFiles(multiple: !selection.limits.singleSelect),
  );

  /// Reads the clipboard's files and adds them.
  Future<void> paste(ClipboardReader reader) async =>
      addFiles(await reader.readFiles());

  /// Replaces the item [id] with one file from the dialog, in its place.
  Future<void> replace(AttachItemId id) async {
    final picked = await intake.pickFiles(multiple: false);
    if (picked.isEmpty) return;
    final next = items.itemOf(picked.first, asMedia: true);
    selection.restore(
      AttachSelectionSnapshot([
        for (final item in selection.items) item.id == id ? next : item,
      ]),
    );
  }

  /// Ticks or clears "Group items"; nothing where the rights forbid it.
  set grouped(bool grouped) {
    if (!selection.limits.groupingAllowed) return;
    panel.options.value = panel.options.value.copyWith(grouped: grouped);
  }

  /// Ticks or clears "Send as documents"; a choice the rights forbid
  /// reverts.
  set asFiles(bool asFiles) {
    if (asFiles && !selection.limits.sendAsFileAllowed) return;
    panel.options.value = panel.options.value.copyWith(asFiles: asFiles);
  }

  /// Binds the box's close to a send; the box view sets it while it is up.
  @internal
  set sendHandler(ValueChanged<SendRequest>? onSend) => _$onSend = onSend;

  /// Saves the options when "Remember" is ticked, for a send.
  @internal
  void remembered(SendOptions sent) {
    if (store case final store?) {
      unawaited(store.save(sent, remember: remember.value));
    }
  }

  /// Releases the panel.
  void dispose() {
    panel.dispose();
    remember.dispose();
    preparing.dispose();
  }
}
