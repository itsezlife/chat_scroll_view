import 'dart:async';
import 'dart:developer' as dev;

import 'package:attach_model/attach_model.dart' show AttachItemId, PlannedSend;
import 'package:attach_sheet/attach_sheet.dart' show AttachDropOverlay;
import 'package:bulletins/bulletins.dart';
import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:chat_composer/chat_composer.dart' show ComposerBottomFade;
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/app/app_platform_policy.dart';
import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chat_scroll_view_example/src/common/android_clipboard_toast.dart';
import 'package:chat_scroll_view_example/src/common/constant/demo_config.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_kind.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:chat_scroll_view_example/src/common/panel_trace.dart';
import 'package:chat_scroll_view_example/src/common/scroll_lab.dart';
import 'package:chat_scroll_view_example/src/common/soft_keyboard_port.dart';
import 'package:chat_scroll_view_example/src/common/utils/mapped_value_listenable.dart';
import 'package:chat_scroll_view_example/src/common/widgets/measure_size.dart';
import 'package:chat_scroll_view_example/src/features/chat/capabilities/capabilities_switcher.dart';
import 'package:chat_scroll_view_example/src/features/chat/capabilities/capabilities_switcher_sheet.dart';
import 'package:chat_scroll_view_example/src/features/chat/capabilities/chat_capabilities_host.dart';
import 'package:chat_scroll_view_example/src/features/chat/capabilities/chat_protection_host.dart';
import 'package:chat_scroll_view_example/src/features/chat/capabilities/demo_chat_rights.dart';
import 'package:chat_scroll_view_example/src/features/chat/controller/chat_search_controller.dart';
import 'package:chat_scroll_view_example/src/features/chat/controller/chat_search_state.dart';
import 'package:chat_scroll_view_example/src/features/chat/controller/unread_boundary_controller.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/address_link_preview_resolver.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/animated_emoji_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/backend_chat_data_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/comments_data_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/demo_documents.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/demo_media_messages.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/generated_chat_data_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/http_open_graph_resolver.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_attach.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_confirm_box.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_input_set.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_outgoing_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_pack_sheets.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_delivery.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_outbox.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_server_script_sheet.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/outbox_debug_panel.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/source_lost_prompt.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_body_host.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_bulletins.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_copy.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_copy_feedback.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_data_source_extension.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_media_host.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_messages_copy_format.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_pack_targets.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_texture_warmer.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/document_embed.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/large_emoji_policy.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/link_activation.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/message_editability.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/message_emoji_packs.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/message_menu.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/sticker_interaction_stub.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/sticker_message_body.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/unread_boundary_sender_run_layout.dart';
import 'package:chat_scroll_view_example/src/features/chat/wallpaper/demo_wallpaper.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/body_prefill.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/chat_bottom_chrome.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/chat_dialogs.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/chat_draft_preview_bubble.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/chat_search_bar.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/date_separator.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_backend_error.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_row_appearance.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/large_emoji_limit_button.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/notes_dialog.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/scroll_to_bottom_button.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/selection_app_bar.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/side_controls/chat_side_controls.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/unread_separator.dart';
import 'package:chat_scroll_view_example/src/features/logs/model/journal_view.dart';
import 'package:chat_scroll_view_example/src/features/logs/view/journal_page.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart'
    show
        AppliedEdit,
        ChatCorrelation,
        ChatDiagnostics,
        ChatEventCategory,
        ChatEventLevel,
        ContentDescriptor,
        ContentKey,
        LibraryPackEdit,
        LinkPreview,
        LinkPreviewResolver,
        LinkPreviewWire,
        MediaItem,
        MediaItemId,
        PackId,
        PackKind,
        PackInstallState,
        PackLookup$Found,
        PastedMedia,
        SemanticKind;
import 'package:content_model/content_model.dart' as model show RichText;
import 'package:control/control.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsService;
import 'package:flutter/services.dart';
import 'package:flutter_md/flutter_md.dart'
    show
        MarkdownPainterCache,
        MarkdownPainterCacheScope,
        MarkdownSpoilerController;
import 'package:http/http.dart' as http;
import 'package:listen/listen.dart' as listen;
import 'package:message_media/message_media.dart';
import 'package:mpx_core/mpx_core.dart'
    show MediaLoadingStyleScope, MediaStageStyle, PreparedMedia;
import 'package:mpx_library/mpx_library.dart' show PlatformIntake;
import 'package:mpx_transfer/mpx_transfer.dart' show SourceBytes;
import 'package:panel_presentation/panel_presentation.dart';
import 'package:viewport_scroll/viewport_scroll.dart' show ViewportScrollRouter;

/// Supplies the message source of a [WidgetChatScreen].
typedef ChatDataSourceLoader = Future<ChatDataSource> Function();

/// Demo screen for the widget-based [ChatScrollView] — the chat viewport,
/// a bottom composer, the emoji panel and a contextual selection bar, wired
/// together.
///
/// The screen creates one [ChatInputSet] (composer, panel shell, presentation)
/// over the app's [AppServices] and disposes it with itself.
class WidgetChatScreen extends StatefulWidget {
  /// Demo route wiring [ChatScrollView], composer, panel and selection chrome.
  const WidgetChatScreen({
    required this.services,
    this.dataSourceLoader,
    this.softKeyboard = const PlatformSoftKeyboard(),
    this.presentationPolicy,
    this.kind = ChatKind.standard,
    this.title = 'Chat',
    this.chatId = 'chat',
    this.rights,
    super.key,
  });

  /// The app's long-lived services; the screen disposes none of them.
  final AppServices services;

  /// Supplies the message source instead of the bundled comments asset, so a
  /// harness can run the real screen on generated messages with no backend.
  ///
  /// The screen owns the returned source and disposes it. The app leaves this
  /// null.
  final ChatDataSourceLoader? dataSourceLoader;

  /// The soft keyboard's readings and commands.
  final SoftKeyboardPort softKeyboard;

  /// Where the panel appears, or null for the policy of the platform.
  final PanelPresentationPolicy? presentationPolicy;

  /// The class of the conversation: its media attach with its download
  /// context ([ChatKind.downloadContext]).
  final ChatKind kind;

  /// The chat's name: where attached media go (the picker viewer's title).
  final String title;

  /// The chat's id: every capabilities event of the chat carries it.
  final String chatId;

  /// What the user may do in the chat, resolved into its capabilities; null
  /// for the rights of its [kind] (`DemoChatRights.forKind`).
  final DemoChatRights? rights;

  @override
  State<WidgetChatScreen> createState() => _WidgetChatScreenState();
}

class _WidgetChatScreenState extends State<WidgetChatScreen> {
  ChatDataSource? _dataSource;
  late final ChatScrollController _controller;

  /// Stops reporting [_controller]'s motion to the app's scrolling surfaces.
  late final VoidCallback _stopScrollReport;

  /// Laid-out message bodies that scrolled away, for when they scroll back: a
  /// little more than a screen of rows each way.
  final MarkdownPainterCache _bodyPainters = MarkdownPainterCache(capacity: 96);
  late final ChatSelectionController _selection;

  /// Which messages have their spoilers revealed. The screen owns it (the
  /// facade is only given it) to turn the dust's motion off with the
  /// chrome's motion speed.
  final MarkdownSpoilerController _spoilers = MarkdownSpoilerController();

  /// What the chat's media items remember while it is open (a revealed
  /// spoiler, where each item is on screen): one per chat, above the list,
  /// so leaving the chat and coming back hides the spoilers again.
  /// Its outgoing items fly in from the picker's thumbnails: each origin
  /// is the outbox's, taken once.
  late final MessageMediaState _mediaState = MessageMediaState(
    sendOrigin: widget.services.outbox.outbox.takeSendOrigin,
  );

  /// The chat's outbox binding: its sends, the server's messages delivered
  /// into the chat, and the message source it keeps for the app's run.
  /// Null for a chat whose own backend sends.
  DemoOutboxChat? _outboxChat;

  /// The transport the link previews are fetched through; closed with the
  /// screen.
  final http.Client _http = http.Client();

  /// Looks up link previews, for the composer's strip and for a received
  /// message that came without a page: the page's Open Graph tags, fetched
  /// from here. A browser's page may not fetch another site's, so the web
  /// shows the address alone.
  late final LinkPreviewResolver _linkPreviews = kIsWeb
      ? const AddressLinkPreviewResolver()
      : HttpOpenGraphResolver(client: _http, chatId: widget.chatId);

  /// The chat's media seams: the platform's media policy, the link preview
  /// lookups, the viewer, the item menu and the card's taps.
  late final ChatMediaHost _media = ChatMediaHost(
    chatId: widget.chatId,
    resolver: _linkPreviews,
    downloadContext: widget.kind.downloadContext,
    onOpenViewer: _openMediaViewer,
    onItemMenu: _openItemMenu,
    onLinkPreview: _onLinkPreview,
  );

  /// What the message bodies take from this screen: the embeds over the
  /// app's asset cache, the sticker lookup and the stickers already played.
  late final ChatBodyHost _bodies;

  /// Where a tap on an emoji sticker goes: the stand-in for the peer
  /// broadcast. It sends nothing; the screen shows what it would send.
  late final StickerInteractionStub _stickerInteractions;
  late final ValueNotifier<LargeEmojiPolicy> _emojiPolicy;

  /// How the chat's embeds draw an outline preview: the loading style the
  /// screen is under, fed again when it changes (the bodies paint on a
  /// canvas, with no context to resolve it from).
  listen.ValueNotifier<MediaStageStyle>? _stages;

  /// How the chat's document rows are set: the reference's metrics over the
  /// chrome's text root, fed again when the root changes.
  listen.ValueNotifier<DocumentRowStyle>? _documentStyle;

  /// The demo chat's other fact that gates the large emoji: the user is no
  /// admin of it (its stickers right is the capabilities').
  static const bool _isChatAdmin = false;
  static const int _demoEffectCount = 3;
  final GlobalKey _composerGlassKey = GlobalKey(debugLabel: 'ComposerGlass');
  final GlobalKey _presentationSpace = GlobalKey(debugLabel: 'PanelSpace');

  /// The per-chat input set; created with the first dependencies (it needs
  /// the view) and disposed with the screen.
  ChatInputSet? _inputSet;

  /// Logs the panel's signals when `PANEL_TRACE` is defined.
  PanelTrace? _trace;

  bool _loading = true;
  String? _errorMessage;
  MessageMenu? _messageMenu;

  /// Demo settings: message corner radius (0–17).
  double _bubbleRadius = ChatMessageThemeData.fallback.bubbleRadius;

  /// Highest message id counted as read for [ChatScrollToBottomButton]. Seeded
  /// to stored last-read on off-tail open; advanced by the FAB while scrolling.
  final ValueNotifier<int?> _pillLastSeenBaseline = ValueNotifier<int?>(null);

  /// Unread boundary of the current open; `null` until the open resolves.
  /// Independent of [_pillLastSeenBaseline] — reading advances the baseline,
  /// never the boundary.
  UnreadBoundaryController? _unreadBoundary;

  /// Whether the open has resolved, so there is a reading position worth
  /// saving.
  var _readingPositionKnown = false;

  /// Saves or drops this chat's reading position when the app hides.
  late final AppLifecycleListener _lifecycle;

  /// Page-down chrome show-intent — drives [ChatSideControlsBar] stack slot.
  ///
  /// A notifier, not screen state: it flips whenever the viewport leaves or
  /// reaches the tail, and a `setState` there rebuilt the whole screen (every
  /// mounted row with it) in the frame of that scroll.
  final _pageDownChromeVisible = ValueNotifier<bool>(false);

  /// The chat's capabilities, resolved from its rights: the one signal the
  /// composer, the picker, the large-emoji gate and the Logs screen read,
  /// with the denial feedback that shows an attempt as a bulletin.
  late final ChatCapabilitiesHost _rights = ChatCapabilitiesHost.forRights(
    widget.rights ?? DemoChatRights.forKind(widget.kind),
    chatId: widget.chatId,
    bulletins: _bulletins,
  );

  /// The chat's protection over [_selection]: the copy hook, the rows it
  /// takes from the menus and the bar, the desktop selection cleared on a
  /// live change, the capture block.
  late final ChatProtectionHost _protection;

  /// The debug switcher's rows over [_rights].
  late final CapabilitiesSwitcher _switcher = CapabilitiesSwitcher(_rights);

  /// The stickers right, which the large-emoji gate follows.
  late final listen.ValueListenable<Capability> _stickersRight = _rights
      .capabilities
      .select((c) => c.sending.stickers);

  ChatSearchController? _search;

  /// Coalesces progressive baseline bumps while scrolling into a single
  /// `update_read_state` call; tail arrival flushes immediately.
  Timer? _persistLastReadTimer;

  static const Duration _persistLastReadDebounce = Duration(milliseconds: 500);

  int? _pendingLastReadBaseline;

  ChatInputSet get _input => _inputSet!;

  /// The attach host: the sheet, the confirm box and the drop zones.
  late final ChatAttach _attach = ChatAttach(
    services: widget.services,
    composer: _input.composer,
    bulletins: _bulletins,
    send: _sendInChat,
    sendPlanned: _sendPlanned,
    chatTitle: widget.title,
    capabilities: _rights.attach,
    yieldKeyboard: _input.yieldKeyboardToPanel,
    returnKeyboard: _input.handOffToKeyboard,
    holdChatPlayback: () => _input.holdChatPlayback().release,
    keyboardUp: () => _input.keyboardUp,
    ownKeyboard: (owned) => _input.surfaceOwnsKeyboard = owned,
  );

  /// The chat's bulletins: one slot for the screen, on the policy of the
  /// platform. A pack sheet over it shows its own while it is up
  /// (`ChatSheetBulletins`). Mounted over the chat region; disposed with the
  /// screen, which commits an Undo still showing.
  final BulletinController _bulletins = BulletinController();

  /// What covers the chat's bottom for a bulletin: the composer, its safe
  /// inset and the keyboard or panel. Made with the input set.
  MappedValueListenable<double, EdgeInsets>? _bulletinObstruction;

  late final BulletinBuilders _bulletinBuilders = ChatBulletins.buildersFor(
    _bulletins.policy,
  );

  @override
  void initState() {
    super.initState();
    unawaited(
      systemConfirmsCopy().then((confirms) => _systemConfirmsCopy = confirms),
    );
    _controller = ChatScrollController();
    // The texture pool creates nothing while the list moves.
    _stopScrollReport = widget.services.scrolling.followChat(_controller);
    if (DemoConfig.scrollLab) ScrollLab.watch(_controller);
    _selection = ChatSelectionController(
      onInteraction: _onSelectionInteraction,
      chatId: widget.chatId,
      // Selections and code taps keep their formatting on the clipboard.
      copyWriter: (copy) => widget.services.clipboard.write(ChatCopy.of(copy)),
      // A tap on an embed means something here (a pack stub).
      handlesEmbedHits: true,
      spoilers: _spoilers,
      // The dust moves on the asset cache's frames and pause layers.
      spoilerClock: widget.services.assets.clock,
    )..selectionCap = 100;
    _protection = ChatProtectionHost(
      chatId: widget.chatId,
      capabilities: _rights.capabilities,
      feedback: _rights.feedback,
      selection: _selection,
      messageProtected: (id) =>
          _dataSource?.getMessage(id)?.isProtected ?? false,
    );
    _emojiPolicy = ValueNotifier(_currentEmojiPolicy());
    _stickersRight.addListener(_refreshEmojiPolicy);
    widget.services.largeEmoji.enabled.addListener(_refreshEmojiPolicy);
    widget.services.largeEmoji.desktopLimit.addListener(_refreshEmojiPolicy);
    _stickerInteractions = StickerInteractionStub(
      onBroadcast: (broadcast) => _showNotice('Would broadcast $broadcast'),
      // A real host counts the effects the animated-emoji set holds for the
      // emoji; the demo gives every emoji of the pack the same number.
      animationCount: (emoji) =>
          AnimatedEmojiPack.stickerFor(emoji) == null ? 0 : _demoEffectCount,
      // The demo chat stands for a private chat with another user.
      canInteract: () => true,
    );
    _pillLastSeenBaseline.addListener(_onPillBaselineChanged);
    _lifecycle = AppLifecycleListener(
      onHide: () {
        _saveReadingPosition();
        _inputSet?.flushDraft();
      },
    );
    _init();
  }

  /// The chat's emoji decision now: the setting's two choices and the chat's
  /// own facts.
  LargeEmojiPolicy _currentEmojiPolicy() => LargeEmojiPolicy(
    enabled: widget.services.largeEmoji.enabled.value,
    stickers: _stickersRight.value,
    isAdmin: _isChatAdmin,
    desktopRegularLimit: widget.services.largeEmoji.desktopLimit.value,
  );

  // A `ValueNotifier` tells only when the policy (a value) really changed.
  void _refreshEmojiPolicy() => _emojiPolicy.value = _currentEmojiPolicy();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final fresh = _inputSet == null;
    final input = _inputSet ??= ChatInputSet(
      services: widget.services,
      view: View.of(context),
      send: _sendComposed,
      edit: _handleEditSelected,
      confirmClearRecents: _confirmClearRecents,
      keyboard: widget.softKeyboard,
      policy: widget.presentationPolicy,
      selection: _selection,
      onPastedMedia: _onPastedMedia,
      onPackRequested: _openPack,
      onPackEditRequested: _editPack,
      onLibraryEdited: _onLibraryEdited,
      // The composer's length follows the chat's limits.
      messageLengthLimit: null,
      capabilities: _rights.capabilities,
      capabilityFeedback: _rights.feedback,
      panelFeedback: _rights.panelFeedback,
      chatId: _rights.chatId,
      accessAction: _rights.accessAction,
      linkPreviewResolver: _linkPreviews,
      // The strip's draft options preview the draft as this chat draws a
      // message it sent, by its media policy.
      mediaPolicy: _media.policy,
      draftBubble: (context, preview) => ChatDraftPreviewBubble(
        preview: preview,
        bodies: _bodies,
        sender: _demoSender,
        chatId: _rights.chatId,
      ),
    );
    if (fresh && kPanelTrace) _trace = PanelTrace(input);
    if (fresh) {
      _bulletinObstruction = input.insets.bottomPadding.map(
        (bottom) => EdgeInsets.only(bottom: bottom),
      );
    }
    // The document rows set their text over the chrome's text root, and
    // a new root reaches the rows already in the chat.
    final documentStyle = const DocumentRowStyle().withText(
      DefaultTextStyle.of(context).style,
    );
    if (_documentStyle case final notifier?) {
      notifier.value = documentStyle;
    } else {
      _documentStyle = listen.ValueNotifier(documentStyle);
    }
    // A new loading style reaches the embeds already in the chat.
    final stages = MediaLoadingStyleScope.resolve(context).stages;
    if (_stages case final notifier?) {
      notifier.value = stages;
    } else {
      _stages = listen.ValueNotifier(stages);
    }
    // Made with the input set: the chat's embeds hold while its popup panel
    // is over the chat.
    if (fresh) {
      _bodies = ChatBodyHost(
        assets: widget.services.assets,
        policy: _emojiPolicy,
        describe: widget.services.describe,
        held: input.chatPlaybackHeld,
        downloadContext: widget.kind.downloadContext,
        stages: _stages,
        documents: (id) =>
            DemoDocuments.document(id) ??
            widget.services.sentDocuments.document(id),
        documentStyle: _documentStyle,
        media: _media,
      );
    }
    // The chat's stickers and GIFs composite as texture layers: the pool is
    // warmed for them once, as the screen opens (ADR 043, "Pool"), in the
    // class of a sticker as the media size policy draws one.
    if (fresh) {
      if (widget.services.assets.textures case final pool?) {
        final viewport = MediaQuery.sizeOf(context);
        final sizes = _bodies.mediaSizes;
        ChatTextureWarmer.warm(
          pool,
          stickerExtent: sizes
              .sizeFor(
                const ChatMediaItem(kind: ChatMediaKind.sticker),
                viewport: viewport,
                parentWidth: viewport.width,
              )
              .longestSide,
          devicePixelRatio: View.of(context).devicePixelRatio,
          maxPixelExtent: sizes.maxDecodeExtent,
        );
      }
    }
    // The spoiler token's particles: no tick (reduce motion, lite mode) leaves
    // the dust still. The particle colour follows the hidden text; the
    // engine takes no other.
    _spoilers.animate =
        ChromeThemeScope.spoilerOf(
          context,
        ).particles.tickAt(ChromeMotionScope.of(context).speed) !=
        null;
    final safe = MediaQuery.viewPaddingOf(context);
    input
      ..updateEnvironment(
        size: MediaQuery.sizeOf(context),
        safeTop: safe.top,
        safeBottom: safe.bottom,
      )
      ..applyTheme(ChromeThemeScope.composerOf(context));
  }

  void _onSelectionInteraction(ChatSelectionInteraction interaction) {
    switch (interaction) {
      case ChatCopyRefused():
        _protection.reportRefused(interaction);
      case ChatCopied(:final text, :final origin, :final gesture):
        if (gesture == ChatInlineGesture.longPress) {
          HapticFeedback.lightImpact();
        }
        _showCopied(switch (origin) {
          ChatCopyOrigin.textSelection => ChatCopyKind.textSelection,
          ChatCopyOrigin.messageSelection => ChatCopyKind.messages,
          ChatCopyOrigin.codeTap => ChatCopyKind.code,
        }, text);
      case ChatLinkActivated(
        :final messageId,
        :final title,
        :final url,
        :final gesture,
      ):
        switch (gesture) {
          case ChatInlineGesture.tap:
            _onLinkTap(messageId, title, url);
          case ChatInlineGesture.longPress:
            _onLinkLongPress(messageId, title, url);
        }
      // The host decides what a mention means: a resolved one opens the user it
      // names; a username was only typed, so it is looked up by name first.
      case ChatResolvedMentionActivated(:final id, :final name):
        _showNotice('User Profile: $name (id $id)');
      case ChatUsernameMentionActivated(:final name):
        _showNotice('Resolving username: $name');
      case ChatHashtagActivated(:final tag):
        _showNotice('Search: #$tag');
      // A custom emoji in the text opens its pack's emoji sheet. A long press
      // is the message's.
      // The tapped emoji shows above the sheet.
      case ChatEmbedActivated(:final target, gesture: ChatInlineGesture.tap):
        _openPackOf(
          ChatPackTargets.ofEmbed(target, widget.services.describe),
          previewEmoji: ContentKey.tryParse(target),
        );
      case ChatEmbedActivated(gesture: ChatInlineGesture.longPress):
        break;
      case ChatStickerActivated(:final content, :final gesture):
        // A tap on an emoji with an effect is a direct interaction, and the
        // body replays it. Otherwise a tap on a sticker or a custom emoji
        // opens its pack; a GIF or a sticker without a pack
        // opens nothing. A long press is message selection and the body's
        // own.
        if (!_stickerInteractions.onActivated(interaction) &&
            gesture == ChatInlineGesture.tap) {
          _openPackOf(
            ChatPackTargets.ofContent(content, widget.services.describe),
          );
        }
      // A body part's activation is its body's own (the media cell); the demo
      // adds nothing on top.
      case ChatBodyPartActivated():
        break;
      case ChatCodeActivated(:final gesture):
        // Host-owned copy path only when [copyCodeOnClick] is false.
        if (gesture == ChatInlineGesture.longPress) {
          HapticFeedback.lightImpact();
        }
    }
  }

  // Whether a copy is confirmed is the platform family's (the selection
  // policy's), not the trigger's: see [ChatCopyFeedback].
  // Whether the system shows its own clipboard toast; read once at start.
  bool _systemConfirmsCopy = false;

  void _showCopied(ChatCopyKind kind, String text) {
    if (!mounted || text.isEmpty) return;
    final feedback = ChatCopyFeedback.forPolicy(
      _selection.selectionPolicy,
      systemConfirms: _systemConfirmsCopy,
    );
    if (!feedback.showsToast(kind)) return;
    _bulletins.show(ChatBulletins.copied(kind, ChatBulletinStrings.demo));
  }

  // An edit of the user's lists asked from the panel: its bulletin, if one
  // is shown.
  // The sticker or GIF a message body is, for the message menu's rows.
  MessageMenuContent? _menuContentOf(String body) {
    final key = StickerMessageBody.keyOf(body);
    if (key == null) return null;
    final library = widget.services.library;
    return switch (widget.services.describe(key)) {
      ContentDescriptor(semanticKind: SemanticKind.sticker, :final pack) =>
        MessageMenuContent.sticker(
          key: key,
          pack: pack,
          packInstalled:
              pack != null &&
              library.installStateOf(pack) == PackInstallState.installed,
          favourite: library.favouriteStickers.value.contains(key),
        ),
      ContentDescriptor(semanticKind: SemanticKind.gif) =>
        MessageMenuContent.gif(key: key),
      _ => null,
    };
  }

  void _onLibraryEdited(AppliedEdit applied) {
    if (!mounted) return;
    if (ChatPackSheets.libraryEditBulletin(
          applied,
          limits: widget.services.library.limits,
          bulletins: _bulletins,
        )
        case final bulletin?) {
      _bulletins.show(bulletin);
    }
  }

  void _onLinkTap(int messageId, String title, String url) {
    if (!mounted) return;
    final label = switch (LinkActivation.fromUrl(url)) {
      WebLinkActivation(:final uri) => 'Opening: $uri',
      MentionLinkActivation(:final id) => 'Mention: $id',
      UsernameLinkActivation(:final name) => 'Username: $name',
      HashtagLinkActivation(:final tag) => 'Hashtag: $tag',
      OtherLinkActivation(:final url) => 'Link: $url',
    };
    _showNotice(label);
  }

  void _onLinkLongPress(int messageId, String title, String url) {
    if (!mounted) return;
    HapticFeedback.lightImpact();
    unawaited(
      showLinkActionsSheet(
        context,
        title: title,
        url: url,
        onOpen: () => _onLinkTap(messageId, title, url),
        onCopied: (text) => _showCopied(ChatCopyKind.link, text),
      ),
    );
  }

  /// The per-item actions protection allows on [item] of the message
  /// [messageId].
  Set<MediaItemAction> _itemActionsOf(int messageId, MediaItem item) =>
      MediaItemAction.allowedItemActions(
        item,
        protection: _rights.capabilities.value.protection,
        messageProtected:
            _dataSource?.getMessage(messageId)?.isProtected ?? false,
      );

  /// The address of [message]'s link preview card: the page's, else the
  /// sender's options'.
  static Uri? _linkPreviewUrlOf(IChatMessage? message) => switch (message) {
    UserChatMessage(:final payload) => switch (LinkPreviewWire.readLinkPreview(
      payload,
    )) {
      final preview? => preview.page?.url ?? preview.options.url,
      null => null,
    },
    _ => null,
  };

  /// Opens the viewer on a tapped picture; a file alone has no page in it
  /// and opens elsewhere (here, a notice).
  void _openMediaViewer(
    BuildContext context,
    MediaViewerRequest request,
    List<MediaItem> items,
  ) {
    if (!mounted) return;
    if (!ChatMediaViewer.shows(request, items)) {
      final name = items
          .where((item) => item.id == request.item)
          .map((item) => item.descriptor.fileName)
          .firstOrNull;
      _showNotice('Would open ${name ?? 'the file'}');
      return;
    }
    unawaited(
      ChatMediaViewer.open(
        context,
        request,
        items,
        downloadContext: widget.kind.downloadContext,
      ),
    );
  }

  /// The item's options from its semantics action: the per-item rows over
  /// the item's rect.
  void _openItemMenu(
    BuildContext context,
    int messageId,
    MediaHitPart part,
    Rect rect,
  ) {
    final menu = _messageMenu;
    if (menu == null || !mounted) return;
    unawaited(menu.presentItem(context, messageId, part, rect));
  }

  /// A tap on a link preview card: its body opens the page, its button runs
  /// the button's action.
  void _onLinkPreview(
    int messageId,
    LinkPreviewHitPart part,
    LinkPreview page,
  ) {
    switch (part.zone) {
      case LinkPreviewZone.body:
        _onLinkTap(messageId, page.title ?? '', page.url.toString());
      case LinkPreviewZone.button:
        _showNotice('Would open the page in place: ${page.url.host}');
    }
  }

  /// A per-item row: Copy File Name copies; the others (save, share) are
  /// the media-save work's and show what they would do.
  void _onMediaAction(int messageId, MediaItem item, MediaItemAction action) {
    switch ((action, item.descriptor.fileName)) {
      case (MediaItemAction.copyFileName, final name?):
        unawaited(widget.services.clipboard.write(model.RichText.plain(name)));
        _showNotice('File name copied');
      case _:
        _showNotice('Would ${action.name} the item');
    }
  }

  void _onAvatarTap(String sender) {
    _showNotice('User Profile: $sender');
  }

  @override
  void dispose() {
    _pillLastSeenBaseline.removeListener(_onPillBaselineChanged);
    _lifecycle.dispose();
    _saveReadingPosition();
    _flushPendingLastRead();
    _persistLastReadTimer?.cancel();
    _pillLastSeenBaseline.dispose();
    _pageDownChromeVisible.dispose();
    _unreadBoundary?.dispose();
    _search?.dispose();
    _stopScrollReport();
    _controller.dispose();
    _bodyPainters.clear();
    _protection.dispose();
    _selection.dispose();
    _spoilers.dispose();
    _stickersRight.removeListener(_refreshEmojiPolicy);
    widget.services.largeEmoji.enabled.removeListener(_refreshEmojiPolicy);
    widget.services.largeEmoji.desktopLimit.removeListener(_refreshEmojiPolicy);
    _emojiPolicy.dispose();
    _stages?.dispose();
    _documentStyle?.dispose();
    _stickerInteractions.dispose();
    _media.dispose();
    _mediaState.dispose();
    _http.close();
    _trace?.dispose();
    _inputSet?.dispose();
    if (_dataSource case final BackendChatDataSource source) {
      source.removeReconnectGapListener(_onReconnectGap);
    }
    _outboxChat?.detach();
    _disposeOwnSource();
    _messageMenu = null;
    _bulletinObstruction?.dispose();
    _attach.dispose();
    _rights.dispose();
    _bulletins.dispose();
    super.dispose();
  }

  /// Frees the message source unless the outbox's binding keeps it.
  void _disposeOwnSource() {
    final source = _dataSource;
    if (source == null || (_outboxChat?.holds(source) ?? false)) return;
    source.dispose();
  }

  /// Makes the unread boundary pending where a realtime reconnect may have
  /// missed messages.
  void _onReconnectGap(RealtimeReconnectGap gap) =>
      _unreadBoundary?.markReconnectGap(
        newestBeforeDrop: gap.newestBeforeDrop,
        readMark: gap.lastReadMessageId,
      );

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      // final backend = await BackendChatDataSource.connect(
      //   client: Supabase.instance.client,
      // );
      // A chat the outbox sends for keeps its source in the outbox's binding
      // across opens: its outgoing rows and sent messages are there.
      final outboxChat = widget.services.outbox.chat(widget.chatId);
      final backend =
          outboxChat.source ??
          await (widget.dataSourceLoader ?? _loadDemoChat)();

      // The screen may have been popped while `load()` was in flight. The
      // `dispose()` above already ran with `_dataSource == null`, so we
      // would otherwise assign the newly-loaded source into the dead State
      // and never free it.
      if (!mounted) {
        if (!outboxChat.holds(backend)) backend.dispose();
        return;
      }
      // Owned from here on: `dispose()` and the catch below free it, unless
      // the outbox's binding holds it.
      _dataSource = backend;
      if (backend is! BackendChatDataSource) {
        _outboxChat = outboxChat;
        _rights.followSendInFlight(outboxChat.sendInFlight);
        // Messages an earlier run left sending come back first.
        await outboxChat.attach(
          backend,
          capabilities: _rights.capabilities,
          denialText: _rights.denialText,
          onDenied: _rights.showDenied,
          announce: _announceOutgoing,
          askForSource: _askForLostSource,
          atBottom: () => _controller.isAtTail.value,
        );
        if (!mounted) return;
      }
      // An edit ends when its message is deleted.
      _input.bindMessages(backend);
      // The composer keeps this chat's unsent text; a chat that does not
      // outlive a relaunch keeps none.
      if (_chatKey(backend) case final key?) {
        unawaited(_input.bindDrafts(widget.services.drafts, key));
      }

      // Only the server-backed source persists read state; the bundled
      // sources open without a stored last-read.
      final lastRead = switch (backend) {
        final BackendChatDataSource source =>
          await source.getLastReadMessageId(),
        CommentsDataSource() => null,
        _ => null,
      };
      final centerBands = widget.services.centerBands;
      final openPosition = await backend.resolveOpenPosition(
        storedLastRead: lastRead,
        isSelfMessage: _isSelfMessage,
        savedCenterBand: switch (_chatKey(backend)) {
          final key? => await centerBands.read(key),
          null => null,
        },
      );
      if (!mounted) return;
      _readingPositionKnown = true;

      _messageMenu = MessageMenu(
        dataSource: backend,
        clipboard: widget.services.clipboard,
        selection: _selection,
        canEdit: _canEdit,
        actions: MessageMenuActions(
          onDelete: (messageId) => _handleDeleteSelected([messageId]),
          onDeleteSelected: _handleDeleteSelected,
          onEdit: _beginEdit,
          onCopy: (text) => _showCopied(ChatCopyKind.messages, text),
          onCopySelected: (text) =>
              _showCopied(ChatCopyKind.textSelection, text),
          onCopyLink: (text) => _showCopied(ChatCopyKind.link, text),
          onCopyCode: (text) => _showCopied(ChatCopyKind.code, text),
          onEmojiPacks: (packs) => unawaited(_openEmojiPacks(packs)),
          onViewPack: (pack) => unawaited(_openPack(pack)),
          onLibraryEdit: (edit) =>
              _onLibraryEdited(widget.services.libraryShown.apply(edit)),
          onNotice: _showNotice,
          onMessageLogs: kDebugMode ? _openMessageLogs : null,
          onMediaAction: _onMediaAction,
          onRetry: (messageId) => unawaited(_outboxChat?.retryAt(messageId)),
          onDeleteUnsent: (messageId) => _outboxChat?.deleteAt(messageId),
          onDenied: (actionId, messageId) =>
              _protection.reportDenied(switch (actionId) {
                MessageMenuActionId.forward => CapabilityAction.forward,
                MessageMenuActionId.saveGif => CapabilityAction.save,
                _ => CapabilityAction.copy,
              }, messageId),
        ),
        deniedActionsOf: _protection.deniedMenuActions,
        isFailed: (id) => _outboxChat?.isFailedAt(id) ?? false,
        mediaOf: (id) => backend.getMessage(id)?.media ?? const [],
        itemActionsOf: _itemActionsOf,
        linkPreviewUrlOf: (id) => _linkPreviewUrlOf(backend.getMessage(id)),
        contentOf: (id) => switch (backend.getMessage(id)?.text) {
          final text? => _menuContentOf(text),
          null => null,
        },
        emojiPacks: MessageEmojiPacks(
          of: (id) => switch (backend.getMessage(id)?.text) {
            final text? => ChatPackTargets.emojiPacksOf(
              text,
              widget.services.describe,
            ),
            null => const [],
          },
          source: widget.services.packs,
        ),
      );
      _search?.dispose();
      _search = ChatSearchController(dataSource: backend);
      final newest = backend.newestKnownId;
      _pillLastSeenBaseline.value =
          lastRead != null && newest != null && lastRead < newest
          ? lastRead
          : null;
      _unreadBoundary?.dispose();
      final boundary = _unreadBoundary = UnreadBoundaryController(
        dataSource: backend,
        controller: _controller,
        isSelfMessage: _isSelfMessage,
        boundary: switch (openPosition) {
          MessageOpenPosition(:final unreadBoundary) => unreadBoundary,
          CenterBandOpenPosition() => null,
        },
        readElsewhere: switch (backend) {
          final BackendChatDataSource source => source.readElsewhere,
          _ => null,
        },
      );
      if (backend case final BackendChatDataSource source) {
        source.addReconnectGapListener(_onReconnectGap);
      }
      switch (openPosition) {
        case MessageOpenPosition(
          :final anchor,
          :final alignment,
          :final tailFitFraction,
          :final pixelOffset,
        ):
          _controller.jumpTo(
            anchor,
            alignment: alignment,
            tailFitFraction: tailFitFraction,
            pixelOffset: pixelOffset,
          );
        case CenterBandOpenPosition(
          :final centerBand,
          :final pendingBoundaryFrom,
        ):
          if (pendingBoundaryFrom case final fromId?) {
            boundary.setPendingBoundary(fromId);
          }
          _controller.jumpToCenterBand(
            centerBand.messageId,
            centerBand.offsetFromMessageTop,
          );
      }
    } on Object catch (error, stackTrace) {
      dev.log(
        'Error initializing chat screen',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      _unreadBoundary?.dispose();
      _unreadBoundary = null;
      _readingPositionKnown = false;
      _disposeOwnSource();
      _dataSource = null;
      _messageMenu = null;
      _errorMessage = error.toString();
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

  void _onPillBaselineChanged() {
    final newest = _dataSource?.newestKnownId;
    final baseline = _pillLastSeenBaseline.value;
    if (newest == null || baseline == null) return;
    final backend = _dataSource;
    if (backend is! BackendChatDataSource) return;

    _pendingLastReadBaseline = baseline;
    _persistLastReadTimer?.cancel();

    if (baseline >= newest) {
      _flushPendingLastRead();
      return;
    }

    _persistLastReadTimer = Timer(
      _persistLastReadDebounce,
      _flushPendingLastRead,
    );
  }

  void _flushPendingLastRead() {
    _persistLastReadTimer?.cancel();
    _persistLastReadTimer = null;
    final baseline = _pendingLastReadBaseline;
    if (baseline == null) return;
    final backend = _dataSource;
    if (backend is! BackendChatDataSource) return;
    _pendingLastReadBaseline = null;
    unawaited(backend.updateLastReadMessageId(baseline));
  }

  /// Opens the Logs screen on the events of the message with [messageId],
  /// the chat's capabilities at its top.
  /// An outgoing message's records follow its client message id, which
  /// stays the same while its row moves.
  void _openMessageLogs(int messageId) => unawaited(
    Navigator.of(context).push(
      JournalPage.route(
        journal: widget.services.journal,
        filter: switch (_outboxChat?.clientMessageIdAt(messageId)) {
          final clientMessageId? => JournalFilter.ofOutgoing(clientMessageId),
          null => JournalFilter.ofMessage('$messageId'),
        },
        capabilities: _rights.capabilities,
      ),
    ),
  );

  /// Key of [source]'s chat in the per-chat stores, the center-band and the
  /// draft store (a key-value name), or `null` for a chat whose history does
  /// not survive a relaunch.
  static String? _chatKey(ChatDataSource source) => switch (source) {
    BackendChatDataSource(:final chatId) => 'backend.$chatId',
    CommentsDataSource() => 'comments',
    _ => null,
  };

  /// Saves the reading position for the next open, or drops it when the
  /// chat is left at the tail or at the start of unread content — see
  /// [ChatDataSourceX.resolveLeavePosition]. Leaves the store untouched
  /// before the open's first layout.
  void _saveReadingPosition() {
    final source = _dataSource;
    if (!_readingPositionKnown || source == null) return;
    final key = _chatKey(source);
    final range = _controller.visibleRange.value;
    if (key == null || range == null) return;
    final centerBand = source.resolveLeavePosition(
      centerBand: _controller.centerBand.value,
      isAtTail: _controller.isAtTail.value,
      newestVisibleId: range.lastId,
      readMark: _pillLastSeenBaseline.value,
      isSelfMessage: _isSelfMessage,
    );
    unawaited(
      widget.services.centerBands.write(key, centerBand).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        dev.log(
          'Saving the reading position failed',
          name: 'chat_open',
          error: error,
          stackTrace: stackTrace,
        );
      }),
    );
  }

  /// Page-down goes to the unread boundary until its separator has been
  /// seen, pending boundaries included; afterwards it goes to the newest
  /// message.
  bool _pageDownToUnseenBoundary() {
    final fromId = _unreadBoundary?.unseenFromId;
    if (fromId == null) return false;
    unawaited(
      _controller.animateTo(
        fromId,
        alignment: ChatDataSourceX.unreadBoundaryAlignment,
        pixelOffset: ChatDataSourceX.unreadBoundaryPixelOffset,
        highlight: false,
      ),
    );
    return true;
  }

  static const String _demoSender = 'Hixie';

  /// Demo "signed-in user" — same predicate for viewport follow-tail and FAB.
  static bool _isSelfMessage(IChatMessage message) =>
      message.sender == _demoSender;

  /// The demo chat: the bundled comments, then the media messages as the
  /// newest.
  static Future<ChatDataSource> _loadDemoChat() =>
      CommentsDataSource.load(tailMedia: DemoMediaMessages.all);

  /// Sends [text] as one send of the chat: in slow mode the next send waits
  /// an interval, and this one is pending until it lands. [payload] is the
  /// rest of the message (its link preview, `invertMedia`).
  ///
  /// A chat the outbox sends for sends through it: its row shows at once
  /// and the outbox's own checks hold a send slow mode refuses.
  Future<void> _sendInChat(
    String text, {
    Map<String, Object?> payload = const {},
  }) async {
    if (_outboxChat case final chat?) {
      _sent(chat.sendText(text, extras: payload) != null);
      return;
    }
    return _rights.send(() => _handleSendMessage(text, payload: payload));
  }

  /// Sends the attach sheet's plan through the outbox, or each text as a
  /// message where the chat's backend sends.
  void _sendPlanned(
    List<PlannedSend> sends, {
    required List<String> bodies,
    required Map<AttachItemId, PreparedMedia> prepared,
    required List<List<Rect?>> origins,
  }) {
    if (_outboxChat case final chat?) {
      // An outbox row shows its items as media: its text is the caption.
      final messages = chat.sendPlanned(
        sends,
        bodies: [for (final send in sends) ChatAttachMessages.captionOf(send)],
        prepared: prepared,
        origins: origins,
      );
      _sent(messages.any((message) => message != null));
      return;
    }
    unawaited(() async {
      for (final body in bodies) {
        await _sendInChat(body);
      }
    }());
  }

  // A send the outbox accepted starts slow mode's wait and clears the unread
  // boundary of the open it was sent from.
  void _sent(bool accepted) {
    if (!accepted) return;
    _rights.startInterval();
    _unreadBoundary?.clear();
  }

  /// Sends what the composer produced: its body, and its link preview and
  /// `invertMedia` as the message's payload, which the demo sources keep
  /// and the bubbles read as a received message's.
  Future<void> _sendComposed(ChatOutgoingMessage message) =>
      _sendInChat(message.body, payload: message.toJson()..remove('body'));

  /// Sends [text] as the signed-in user through the chat's backend (the
  /// other sources send through the outbox). A send that succeeds clears
  /// the unread boundary of the open it was sent from, whether or not the
  /// tail holding the sent message is loaded. The backend keeps the body
  /// alone.
  Future<void> _handleSendMessage(
    String text, {
    Map<String, Object?> payload = const {},
  }) async {
    final boundary = _unreadBoundary;
    switch (_dataSource) {
      case final BackendChatDataSource ds:
        try {
          await ds.sendMessage(text);
        } on BackendConnectionException catch (error) {
          if (!mounted) return;
          _bulletins.show(ChatBulletins.error(error.message));
          rethrow;
        }
      case _:
        return;
    }
    boundary?.clear();
  }

  void _handleDeleteSelected(Iterable<int> ids) {
    final toDelete = ids.toList();
    final ds = _dataSource;
    ds?.removeMessages(toDelete);
    _selection.clear();
  }

  Future<void> _handleEditSelected(int messageId, String text) async {
    final ds = _dataSource;
    if (ds is CommentsDataSource) {
      final message = ds.getMessage(messageId);
      if (message is UserChatMessage) {
        ds.editMessage(message, text);
      }
      return;
    }
    if (ds is GeneratedChatDataSource) {
      final message = ds.getMessage(messageId);
      if (message is UserChatMessage) {
        ds.editMessage(message, text);
      }
      return;
    }
    final message = ds?.getMessage(messageId);
    if (message != null) {
      ds?.updateMessage(
        UserChatMessage(
          id: message.id,
          sender: message.sender,
          createdAt: message.createdAt,
          updatedAt: DateTime.now(),
          content: text,
          media: message.media,
          payload: switch (message) {
            UserChatMessage(:final payload) => payload,
            _ => const {},
          },
        ),
      );
    }
  }

  /// Host message-menu seam for idle primary tap (mobile) and secondary tap
  /// (desktop right-click) — [ChatScrollView] routes each per selection policy.
  Future<void> _presentMessageMenu(ChatMessageMenuRequest request) async {
    final menu = _messageMenu;
    // One menu at a time: a burst of taps on the error badge opens it once.
    if (menu == null || !mounted || menu.isPresenting) return;
    if (request.partId case DemoErrorBadgePart(:final pointerKind)) {
      ChatDiagnostics.current.emit(
        ChatEventLevel.debug,
        ChatEventCategory.outbox,
        DemoOutgoingOp.badgeMenuOpened,
        correlation: ChatCorrelation(
          chatId: widget.chatId,
          clientMessageId: _outboxChat?.clientMessageIdAt(request.messageId),
          scrollId: '${request.messageId}',
        ),
        fields: () => {'pointer': pointerKind.name},
      );
    }
    await menu.present(context, request);
  }

  // A send's start and end, spoken by assistive technology.
  void _announceOutgoing(String announcement) {
    if (!mounted) return;
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        announcement,
        Directionality.of(context),
      ),
    );
  }

  // The file of an item whose upload source was lost, asked of the user
  // again for a retry.
  Future<SourceBytes?> _askForLostSource(MediaItemId item) async {
    final intake = await PlatformIntake.fileIntake();
    if (!mounted) return null;
    return SourceLostPrompt.ask(context, intake: intake);
  }

  /// The notes field: the one composer of the demo with lists on.
  Future<void> _openNotes() {
    FocusManager.instance.primaryFocus?.unfocus();
    return showNotesDialog(context, clipboard: widget.services.clipboard);
  }

  Future<void> _openBubbleRadiusSettings() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final selected = await showBubbleRadiusDialog(
      context,
      initial: _bubbleRadius,
    );
    if (selected == null || !mounted) return;
    setState(() => _bubbleRadius = selected);
  }

  /// Stable per-state tear-off — same reference for the widget's lifetime,
  /// so the viewport's skip-rebuild cache stays warm across parent rebuilds.
  /// Sender-run chrome comes from viewport [MessageRunLayout], not ad-hoc
  /// neighbor walks here.
  Widget _buildMessage(
    BuildContext context,
    int id,
    IChatMessage? message,
    ChatMessageStatus status,
    MessageRunLayout runLayout,
  ) => buildDemoMessage(
    context,
    id,
    message,
    status,
    runLayout,
    selection: _selection,
    host: _bodies,
    outbox: _outboxChat,
    onAvatarTap: _onAvatarTap,
    onSenderTap: _onAvatarTap,
  );

  void _selectTextFromBar() {
    if (_selection.count != 1) return;
    _selection.enterTextSelection(_selection.selectedIds.first);
  }

  Widget _buildChunkError(
    BuildContext context,
    ChatChunkErrorDetails details,
  ) => DemoChunkErrorTile(
    firstId: details.firstId,
    lastId: details.lastId,
    attempt: details.attempt,
    onRetry: details.retry,
  );

  Widget _buildEmpty(BuildContext context) => const DemoEmptyState();

  Widget _buildUnreadSeparator(BuildContext context) => const UnreadSeparator();

  Widget _buildInitialSkeleton(BuildContext context) =>
      const DemoInitialSkeleton();

  // Whether the message may be edited: not a sticker or a GIF.
  bool _canEdit(int messageId) => switch (_dataSource?.getMessage(messageId)) {
    final message? => MessageEditability.canEdit(message),
    null => false,
  };

  void _beginEdit(int messageId) {
    if (!_canEdit(messageId)) return;
    final message = _dataSource?.getMessage(messageId);
    final content = message?.text;
    if (message == null || content == null) return;
    _selection.clear();
    _input.beginEdit(
      messageId,
      content,
      caption: MessageEditability.editsCaption(message),
    );
  }

  /// Asks before the recent content of [kind] is cleared: the recent
  /// stickers in their own words, the emoji recents in theirs.
  Future<bool> _confirmClearRecents(SemanticKind kind) async {
    if (!mounted) return false;
    final panel = ChromeStringsScope.panelOf(context);
    final (title, message) = switch (kind) {
      SemanticKind.sticker => (
        panel.clearRecentStickersTitle,
        panel.clearRecentStickersMessage,
      ),
      _ => (panel.clearRecentsTitle, panel.clearRecentsMessage),
    };
    // Under a pointer the question is a box on a layer of its own, as a pack
    // removal's is; on touch the platform's dialog.
    if (AppPlatformPolicy.current().asksInBoxes) {
      return ChatConfirmBox.open(
        context,
        ChatConfirmBox(
          title: title,
          question: message,
          confirm: panel.clearAction,
          cancel: panel.cancelAction,
        ),
      );
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(panel.cancelAction),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(panel.clearAction),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  // A pack title in the panel, or "View pack" in its preview: the pack's
  // sheet, a sticker sheet or an emoji sheet by what the pack holds. Its
  // stickers are sent, and its emoji inserted, through the input set as a
  // pick from the panel is; stickers only where the chat allows them.
  Future<void> _openPack(PackId id, {ContentKey? previewEmoji}) async {
    final services = widget.services;
    final lookup = await services.packs.lookup(id);
    if (!mounted) return;
    final kind = switch (lookup) {
      PackLookup$Found(:final pack) => pack.kind,
      // The sheet says the pack is not there.
      _ => PackKind.stickers,
    };
    final input = _input;
    final canPick = kind == PackKind.emoji || _stickersRight.value.isAllowed;
    await _overChat(
      ChatPackSheets.open(
        context,
        services: services,
        bulletins: _bulletins,
        pack: id,
        kind: kind,
        onPick: canPick
            ? (item) => input.pickContent(item.key, kind: item.semanticKind)
            : null,
        onCopy: (item) => input.copyContent(item.key),
        previewEmoji: previewEmoji,
      ),
    );
  }

  // The menu's "contains emoji from N packs": one emoji sheet of them all,
  // whose emoji insert into the composer as a pick from the panel does.
  Future<void> _openEmojiPacks(List<PackId> packs) {
    final input = _input;
    return _overChat(
      ChatPackSheets.openEmojiPacks(
        context,
        services: widget.services,
        bulletins: _bulletins,
        packs: packs,
        onPick: (item) => input.pickContent(item.key, kind: item.semanticKind),
        onCopy: (item) => input.copyContent(item.key),
      ),
    );
  }

  // Holds the chat's stickers while a pack sheet is over it: what is under
  // the sheets pauses while their own stickers play. The app's
  // route observer leaves the clock running for a pack sheet (it holds it
  // only while the sheet moves), so the chat is held on its own.
  Future<void> _overChat(Future<void> sheet) async {
    final claim = _input.holdChatPlayback();
    try {
      await sheet;
    } finally {
      claim.release();
    }
  }

  // A pack named by what was tapped in the chat, if any.
  void _openPackOf(PackId? id, {ContentKey? previewEmoji}) {
    if (id != null) unawaited(_openPack(id, previewEmoji: previewEmoji));
  }

  // A pack's edit asked by the panel: applied with its bulletin, a removal
  // or an archiving behind Undo.
  void _editPack(LibraryPackEdit edit) {
    if (!mounted) return;
    final services = widget.services;
    final pack = switch (services.packs.peek(edit.id)) {
      PackLookup$Found(:final pack) => pack,
      _ => null,
    };
    if (pack == null) {
      ChatPackSheets.applyAlone(services.library, edit);
      return;
    }
    final requests = [(edit: edit, pack: pack)];
    final strings = ChromeStringsScope.packSheetOf(context);
    void apply() =>
        ChatPackSheets.apply(services.library, requests, strings, _bulletins);
    // Under a pointer a removal asks first; the panel it came from stays up
    // while it is asked.
    if (AppPlatformPolicy.current().confirmsPackRemovals &&
        ChatPackSheets.takesAway(requests)) {
      final hold = _input.presentation.holdAutoHide();
      unawaited(
        ChatConfirmBox.open(context, ChatPackSheets.confirmBoxOf(requests))
            .then((confirmed) {
              if (confirmed && mounted) apply();
            })
            .whenComplete(hold.release),
      );
      return;
    }
    apply();
  }

  // The demo sends no media: it shows what it would send, as a composer
  // shows pasted media before sending it. Cancelling pastes the text
  // that came with the media, if any.
  Future<bool> _onPastedMedia(List<PastedMedia> media) async {
    if (!mounted) return false;
    final send = await showPastedMediaSheet(context, media);
    if (send) {
      _showNotice(
        media.length == 1
            ? 'Would send 1 item'
            : 'Would send ${media.length} items',
      );
    }
    return send;
  }

  // A demo label: what the screen would do, where the demo does nothing.
  void _showNotice(String text) {
    if (!mounted) return;
    _bulletins.show(ChatBulletins.notice(text));
  }

  void _copySelected() {
    if (_selection.isTextSelectionActive) {
      unawaited(_selection.copyTextSelection());
      return;
    }
    final source = _dataSource;
    if (source == null) return;
    // A protected member refuses the copy; the facade reports it.
    if (_selection.refusesCopy(_selection.selectedIds)) return;
    final copied = ChatMessagesCopyFormat.forPolicy(
      _selection.selectionPolicy,
    ).compose(ChatCopiedMessage.of(_selection.selectedIds, source));
    if (copied.isEmpty) return;
    unawaited(widget.services.clipboard.write(copied));
    ChatCopyFeedback.endSelection(_selection);
    _showCopied(ChatCopyKind.messages, copied.plain);
  }

  void _editSelectedFromBar() {
    if (_selection.count != 1) return;
    _beginEdit(_selection.selectedIds.first);
  }

  @override
  Widget build(BuildContext context) {
    final chat = _buildChat(context);
    final drop = _attach.dropSource;
    if (drop == null || _loading || _dataSource == null) return chat;
    // Desktop and web: files dragged over the chat open (or add to) the
    // confirm box, by the zone they are dropped in.
    return AttachDropOverlay(
      source: drop,
      policy: _attach.policy,
      boxOpen: _attach.boxOpen,
      maxFileBytes: _rights.value.limits.fileSize,
      onDrop: (files, {required asFiles}) =>
          unawaited(_attach.openBox(context, files, asFiles: asFiles)),
      child: chat,
    );
  }

  Widget _buildChat(BuildContext context) {
    if (_errorMessage != null) {
      return DemoBackendError(message: _errorMessage!, onRetry: _init);
    }
    if (_loading || _dataSource == null || _search == null) {
      return const Scaffold(
        body: DemoChatWallpaper(
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    final chatScrollTheme = ChatScrollTheme.of(context);
    final messageTheme = chatScrollTheme.message;
    final newMessageTheme = messageTheme?.copyWith(bubbleRadius: _bubbleRadius);
    final search = _search!;
    final mobilePanel = _input.panelInKeyboardPlace;

    return ControllerScope.value(
      search,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          final isOpenSearch = search.state.maybeMap(
            closed: (_) => false,
            orElse: () => true,
          );
          if (isOpenSearch) {
            search.close();
          }
          if (_messageMenu?.isPresenting ?? false) return;
          if (_selection.isTextSelectionActive) {
            _selection.clearTextSelection();
            return;
          }
          final hasSelection = _selection.isSelectionMode;
          if (hasSelection) {
            _selection.clear();
            return;
          }
          if (_input.isPanelVisible) {
            unawaited(_input.handleBack());
            return;
          }
          // Nothing of the chat's own is left to close: leave the chat
          // when it was pushed over the chat list. `pop`, not `maybePop`:
          // this scope vetoes every pop, so `maybePop` would land here again.
          final navigator = Navigator.of(context);
          if (navigator.canPop()) navigator.pop();
        },
        child: ChatScrollTheme(
          data: chatScrollTheme.copyWith(message: newMessageTheme),
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.light,
              statusBarBrightness: Brightness.dark,
              systemNavigationBarContrastEnforced: false,
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarDividerColor: Colors.transparent,
              systemNavigationBarIconBrightness: Brightness.light,
              systemStatusBarContrastEnforced: false,
            ),
            child: Scaffold(
              resizeToAvoidBottomInset: false,
              body: StateConsumer<ChatSearchController, ChatSearchState>(
                listener: _onSearchStateChanged,
                child: DemoChatSurface(
                  // Above the chat, the composer and the panel: the copy
                  // shortcut reaches here from any one's focus. The
                  // composer's own copy sits below and wins when it has a
                  // selection; otherwise its action is disabled and the
                  // intent comes up to this one.
                  child: Actions(
                    actions: <Type, Action<Intent>>{
                      CopySelectionTextIntent: _CopySelectedAction(
                        selection: _selection,
                        onCopy: _copySelected,
                      ),
                    },
                    // Every scroll key has an owner (ADR 012, desktop key
                    // routing): the field keeps those it edits with, the
                    // panel under the mouse takes the rest, else the chat.
                    // On a desktop nobody is left with the focus: the router
                    // takes it when the field is left.
                    // The field is that fallback, as the reference desktop
                    // client focuses its field when it shows a chat and
                    // keeps it there while the history is clicked; with
                    // messages selected the history holds the keys (the
                    // router's own node, under the copy action).
                    child: ViewportScrollRouter(
                      holdsFocus: switch (AppPlatformPolicy.current()) {
                        AppPlatformPolicy$Desktop() => true,
                        _ => false,
                      },
                      focusFallback: () =>
                          _selection.isSelectionMode ||
                              _selection.isTextSelectionActive
                          ? null
                          : _input.composer.focusNode,
                      refocusOn: _selection,
                      child: _buildScreenBody(
                        search: search,
                        mobilePanel: mobilePanel,
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
  }

  /// The chat region with its bulletins, and the popup or docked panel over
  /// it.
  Widget _buildScreenBody({
    required ChatSearchController search,
    required bool mobilePanel,
  }) {
    final input = _input;
    final insets = input.insets;
    return GlassSourceScope(
      child: Stack(
        key: _presentationSpace,
        children: <Widget>[
          // A docked panel takes width from the chat region; the
          // popup and the dock draw above it.
          Positioned.fill(
            child: ValueListenableBuilder<double>(
              valueListenable: insets.inlineEnd,
              builder: (context, inlineEnd, child) => Padding(
                padding: EdgeInsetsDirectional.only(end: inlineEnd),
                child: child,
              ),
              // The bulletins over the chat, above the
              // composer and its keyboard or panel. They sit
              // at the chat's bottom padding on the frame it
              // changes, so they move with the composer.
              child: ChromeIconScope(
                icons: ChatBulletins.icons,
                child: BulletinHost(
                  controller: _bulletins,
                  obstruction: _bulletinObstruction,
                  tracksObstruction: true,
                  builders: _bulletinBuilders,
                  child: _buildChatRegion(
                    search: search,
                    mobilePanel: mobilePanel,
                  ),
                ),
              ),
            ),
          ),
          if (!mobilePanel)
            Positioned.fill(
              child: PanelPresentationView(controller: input.presentation),
            ),
        ],
      ),
    );
  }

  /// On a desktop a click in the history is inside the composer's field for
  /// its focus, as in the reference desktop client, where the history never
  /// takes the focus from the field: typing goes on after it. A text or
  /// message selection the press starts moves the keys as the scroll
  /// router says (ADR 012, desktop key routing). On touch a tap on the
  /// history lets the field go, and the soft keyboard with it.
  Widget _historyKeepsField(Widget history) =>
      switch (AppPlatformPolicy.current()) {
        AppPlatformPolicy$Desktop() => TextFieldTapRegion(child: history),
        _ => history,
      };

  /// The chat, its chrome and the composer, in the box the docked panel
  /// leaves.
  Widget _buildChatRegion({
    required ChatSearchController search,
    required bool mobilePanel,
  }) {
    final input = _input;
    final insets = input.insets;
    return Stack(
      children: <Widget>[
        // Chat fills the screen; the composer is stacked over its bottom.
        Positioned.fill(
          child: GlassSource(
            child: DemoChatWallpaper(
              child: MarkdownPainterCacheScope(
                cache: _bodyPainters,
                child: BodyPrefill(
                  cache: _bodyPainters,
                  controller: _controller,
                  dataSource: _dataSource!,
                  selection: _selection,
                  embedResolver: _bodies.embedResolver,
                  child: MessageMediaStateScope(
                    state: _mediaState,
                    child: _historyKeepsField(
                      ChatKeyboardShortcuts(
                        controller: _controller,
                        selectionController: _selection,
                        reverse: true,
                        preserveExternalFocus: true,
                        // A fresh outgoing row appears as its platform does.
                        child: DemoRowAppearanceScope(
                          atBottom: () => _controller.isAtTail.value,
                          child: ChatScrollView(
                            reverse: true,
                            dataSource: _dataSource!,
                            controller: _controller,
                            selectionController: _selection,
                            onIdleMessageTap: _presentMessageMenu,
                            onSecondaryMessageTap: _presentMessageMenu,
                            isSelfMessage: _isSelfMessage,
                            bottomPadding: insets.bottomPadding,
                            topPadding: insets.topPadding,
                            messageBuilder: _buildMessage,
                            chunkErrorBuilder: _buildChunkError,
                            emptyBuilder: _buildEmpty,
                            loadingBuilder: _buildInitialSkeleton,
                            scrollActivityTiming:
                                const ChatScrollActivityTiming(),
                            dayHeaderDelegate: const ChatPushingDayHeader(),
                            dateSeparatorBuilder: (context, bucket, date) =>
                                DateSeparator(date: date),
                            unreadBoundary: _unreadBoundary,
                            unreadSeparatorBuilder: _buildUnreadSeparator,
                            senderRunLayout: switch (_unreadBoundary) {
                              final boundary? => UnreadBoundarySenderRunLayout(
                                boundary: boundary,
                              ),
                              null => DefaultChatSenderRunLayout.instance,
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // Side controls — page-down + search up/down share one stack.
        _ChatSideControlsHost(
          pageDownChromeVisible: _pageDownChromeVisible,
          bottomInset: insets.bottomPadding,
          onSearchStep: _onSearchStep,
          pageDown: ChatScrollToBottomButton(
            embedded: true,
            controller: _controller,
            dataSource: _dataSource!,
            isSelfMessage: _isSelfMessage,
            lastSeenNewestId: _pillLastSeenBaseline,
            interceptTap: _pageDownToUnseenBoundary,
            onChromeVisibleChanged: (visible) =>
                _pageDownChromeVisible.value = visible,
          ),
        ),
        // Soft fade over chat in the chrome zone. Under the composer so the
        // panel is not washed, and outside the glass source so the island
        // frosts the chat and not this wash.
        ValueListenableBuilder<double>(
          valueListenable: insets.bottomPadding,
          builder: (context, zoneHeight, _) {
            if (zoneHeight <= 0) return const SizedBox.shrink();
            return Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: zoneHeight,
              child: ComposerBottomFade(
                zoneHeight: zoneHeight,
                color: ChromeThemeScope.composerOf(context).contentFade,
              ),
            );
          },
        ),
        // Bottom chrome. Insets math:
        //   bottomPadding = composer extent + presentation occupancy.bottom
        // The occupancy holds the live soft keyboard or the panel, whichever
        // is taller, bottom safe area included; the composer's own pad is
        // the part of the band the occupancy has not covered.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: ChatBottomChrome(
            input: input,
            selection: _selection,
            islandKey: _composerGlassKey,
            anchorSpace: _presentationSpace,
            bulletins: _bulletins,
            onAttachPressed: () => unawaited(_attach.open(context)),
            onVoicePressed: () => _showNotice('Voice is not in the demo'),
          ),
        ),
        // Contextual selection bar — overlays the top. [headerReserve] is
        // driven every animation frame so the floating day header tracks the
        // slide.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SelectionAppBar(
            selection: _selection,
            topInset: insets.headerReserve,
            onSelectText: _selectTextFromBar,
            onCopy: _copySelected,
            canCopy: _protection.canCopy,
            onEdit: _editSelectedFromBar,
            canEdit: _canEdit,
            onDelete: () => _handleDeleteSelected(_selection.selectedIds),
          ),
        ),
        // Demo: search + bubble radius — top-right chrome. Position
        // against [chromeTop] (not [topPadding]) so search reserve does not
        // push this row further down. [Positioned] must be a *direct* Stack
        // child; wrapping it in ValueListenableBuilder makes the builder
        // expand and cover the chat.
        Positioned(
          top: 0,
          right: 12,
          child: ValueListenableBuilder<double>(
            valueListenable: insets.chromeTop,
            builder: (context, chromeTop, child) => Padding(
              padding: EdgeInsets.only(top: chromeTop + 8),
              child: child,
            ),
            child: ListenableBuilder(
              listenable: _selection,
              builder: (context, _) {
                if (_selection.isSelectionMode) {
                  return const SizedBox.shrink();
                }
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const ChatSearchToggleButton(),
                    const SizedBox(width: 4),
                    ValueListenableBuilder<bool>(
                      valueListenable: widget.services.largeEmoji.enabled,
                      builder: (context, enabled, _) => IconButton.filledTonal(
                        tooltip: enabled
                            ? 'Large emoji: on'
                            : 'Large emoji: off',
                        isSelected: enabled,
                        onPressed: () => unawaited(
                          widget.services.largeEmoji.set(enabled: !enabled),
                        ),
                        icon: const Icon(
                          Icons.emoji_emotions_outlined,
                          size: 20,
                        ),
                        selectedIcon: const Icon(
                          Icons.emoji_emotions,
                          size: 20,
                        ),
                      ),
                    ),
                    // Desktop only: the other families have no cap.
                    LargeEmojiLimitButton(setting: widget.services.largeEmoji),
                    const SizedBox(width: 4),
                    IconButton.filledTonal(
                      tooltip: 'Notes (lists)',
                      onPressed: _openNotes,
                      icon: const Icon(Icons.checklist, size: 20),
                    ),
                    if (kDebugMode && _outboxChat != null) ...[
                      const SizedBox(width: 4),
                      IconButton.filledTonal(
                        key: DemoServerScriptSheet.openKey,
                        tooltip: 'Fake server',
                        onPressed: () => unawaited(
                          DemoServerScriptSheet.show(
                            context,
                            server: widget.services.outbox.server,
                            chatId: widget.chatId,
                          ),
                        ),
                        icon: const Icon(Icons.dns_outlined, size: 20),
                      ),
                      if (widget.services.debugActions
                          case final debugActions?) ...[
                        const SizedBox(width: 4),
                        IconButton.filledTonal(
                          key: OutboxDebugPanel.openKey,
                          tooltip: 'Outbox debug',
                          onPressed: () => unawaited(
                            Navigator.of(context).push(
                              OutboxDebugPanel.route(
                                outbox: widget.services.outbox,
                                chatId: widget.chatId,
                                actions: debugActions,
                                journal: widget.services.journal,
                                transport: widget.services.uploadTransport,
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.bug_report_outlined, size: 20),
                        ),
                      ],
                    ],
                    if (kDebugMode) ...[
                      const SizedBox(width: 4),
                      IconButton.filledTonal(
                        key: const ValueKey('chat-rights-switcher'),
                        tooltip: 'Chat rights',
                        onPressed: () => unawaited(
                          CapabilitiesSwitcherSheet.show(
                            context,
                            switcher: _switcher,
                          ),
                        ),
                        icon: const Icon(Icons.admin_panel_settings, size: 20),
                      ),
                    ],
                    const SizedBox(width: 4),
                    IconButton.filledTonal(
                      tooltip: 'Message corners',
                      onPressed: _openBubbleRadiusSettings,
                      icon: const Icon(Icons.rounded_corner, size: 20),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 12,
          right: 162,
          child: ValueListenableBuilder<double>(
            valueListenable: insets.chromeTop,
            builder: (context, chromeTop, _) => ValueListenableBuilder<bool>(
              valueListenable: search.select(
                (s) => s.maybeMap(closed: (_) => false, orElse: () => true),
              ),
              builder: (context, isOpen, _) {
                if (!isOpen) return const SizedBox.shrink();
                // Position against chromeTop; measure only the local pad +
                // field into searchReserve.
                return Padding(
                  padding: EdgeInsets.only(top: chromeTop),
                  child: MeasureSize(
                    onChange: (size) => insets.setSearchReserve(size.height),
                    child: const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: ChatSearchBar(),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  void _onSearchStateChanged(
    BuildContext context,
    ChatSearchController controller,
    ChatSearchState previous,
    ChatSearchState current,
  ) {
    final wasOpen = previous.maybeMap(closed: (_) => false, orElse: () => true);
    final isOpen = current.maybeMap(closed: (_) => false, orElse: () => true);
    if (wasOpen && !isOpen) {
      _input.insets.setSearchReserve(0);
    }

    final prevPopulated = previous.mapOrNull(populated: (s) => s);
    final nextPopulated = current.mapOrNull(populated: (s) => s);
    if (nextPopulated == null) return;
    // Index-only commits from [_onSearchStep] keep the same hits list.
    // Re-animating here would double-fire after every accepted step.
    if (prevPopulated != null &&
        identical(prevPopulated.hits, nextPopulated.hits)) {
      return;
    }
    unawaited(
      _controller.animateTo(
        nextPopulated.hits[nextPopulated.index],
        highlight: true,
        alignment: 0.5,
        loadPolicy: AnimateToLoadPolicy.immediate,
        busyPolicy: AnimateToBusyPolicy.ignore,
      ),
    );
  }

  /// Search up/down: one step per in-flight animate under ignore.
  ///
  /// Commit the hit index only when the viewport can accept the navigation.
  /// Advancing first (old [ChatSearchController.goOlder]) races selection
  /// ahead of [AnimateToBusyPolicy.ignore] drops and kills bound-gated FABs.
  void _onSearchStep({required bool towardOlder}) {
    final search = _search;
    if (search == null) return;
    if (_controller.isAnimating) return;
    final step = towardOlder ? search.peekOlder() : search.peekNewer();
    if (step == null) return;
    search.selectIndex(step.index);
    unawaited(
      _controller.animateTo(
        step.id,
        highlight: true,
        alignment: 0.5,
        loadPolicy: AnimateToLoadPolicy.immediate,
        busyPolicy: AnimateToBusyPolicy.ignore,
      ),
    );
  }
}

/// Search up/down + page-down chrome driven by [ChatSearchController].
class _ChatSideControlsHost extends StatelessWidget {
  const _ChatSideControlsHost({
    required this.pageDownChromeVisible,
    required this.bottomInset,
    required this.pageDown,
    required this.onSearchStep,
  });

  final ValueListenable<bool> pageDownChromeVisible;
  final ValueListenable<double> bottomInset;
  final Widget pageDown;
  final void Function({required bool towardOlder}) onSearchStep;

  @override
  Widget build(BuildContext context) {
    final search = context.controllerOf<ChatSearchController>();
    return ValueListenableBuilder(
      valueListenable: search.select(
        (s) => (
          searching: s.maybeMap(closed: (_) => false, orElse: () => true),
          hitCount: s.maybeMap(
            populated: (p) => p.hits.length,
            orElse: () => 0,
          ),
          index: s.maybeMap(populated: (p) => p.index, orElse: () => 0),
        ),
        (prev, next) => prev != next,
      ),
      builder: (context, slice, _) => ValueListenableBuilder<bool>(
        valueListenable: pageDownChromeVisible,
        builder: (context, pageDownVisible, _) => ChatSideControlsBar(
          searching: slice.searching,
          pageDownVisible: pageDownVisible,
          bottomInset: bottomInset,
          onSearchUp: () => onSearchStep(towardOlder: true),
          onSearchDown: () => onSearchStep(towardOlder: false),
          searchHitCount: slice.hitCount,
          searchUpEnabled: slice.index > 0,
          searchDownEnabled:
              slice.hitCount > 0 && slice.index < slice.hitCount - 1,
          pageDown: pageDown,
        ),
      ),
    );
  }
}

/// The copy shortcut ([CopySelectionTextIntent]) over the chat: it copies
/// what is selected, the messages or the text range, through the same path as
/// the selection bar's Copy.
///
/// Disabled with nothing selected, so a focused field's own copy (or the
/// platform's) is left alone, and for a cut, which copies nothing out of a
/// chat.
class _CopySelectedAction extends Action<CopySelectionTextIntent> {
  _CopySelectedAction({required this.selection, required this.onCopy});

  final ChatSelectionController selection;
  final VoidCallback onCopy;

  @override
  bool isEnabled(CopySelectionTextIntent intent) =>
      !intent.collapseSelection &&
      (selection.isSelectionMode || selection.isTextSelectionActive);

  @override
  Object? invoke(CopySelectionTextIntent intent) {
    onCopy();
    return null;
  }
}
