/// The panel's sticker and GIF pages follow the chat's capabilities: a right
/// denied in the debug switcher gives the page the platform's denied form,
/// with the chat's denial text, and a try on a dimmed page is reported as
/// an attempt from the panel.
///
/// **Seams:** [ChatPanelAvailability] over a [PanelShellController] of fake
/// pages and a [ChatCapabilitiesHost] flipped by its [CapabilitiesSwitcher];
/// the recorded diagnostics; the shell as [PanelShell] draws it.
library;

import 'package:bulletins/bulletins.dart';
import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:chat_scroll_view_example/src/features/chat/capabilities/capabilities_switcher.dart';
import 'package:chat_scroll_view_example/src/features/chat/capabilities/chat_capabilities_host.dart';
import 'package:chat_scroll_view_example/src/features/chat/capabilities/chat_denial_strings.dart';
import 'package:chat_scroll_view_example/src/features/chat/capabilities/chat_panel_availability.dart';
import 'package:chat_scroll_view_example/src/features/chat/capabilities/demo_chat_rights.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/media_panel_pages.dart';
import 'package:content_model/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_shell/panel_shell.dart';
import 'package:panel_shell/testing.dart';

final _start = DateTime(2026, 11, 27, 12);

void main() {
  late RecordingDiagnostics diagnostics;
  late BulletinController bulletins;
  late ChatCapabilitiesHost host;
  late CapabilitiesSwitcher switcher;
  late PanelShellController shell;
  late ChatPanelAvailability availability;

  const stickers = MediaPanelPages.stickersId;
  const gif = MediaPanelPages.gifId;
  final stickerText = ChatDenialStrings.english.text(
    CapabilityAction.sendSticker,
    CapabilityToggle.deniedReason,
    now: _start,
  );
  final gifText = ChatDenialStrings.english.text(
    CapabilityAction.sendAnimation,
    CapabilityToggle.deniedReason,
    now: _start,
  );

  setUp(() {
    diagnostics = RecordingDiagnostics.install();
    bulletins = BulletinController();
    host = ChatCapabilitiesHost.forRights(
      DemoChatRights.member,
      chatId: 'chat-1',
      bulletins: bulletins,
      strings: ChatDenialStrings.english,
      now: () => _start,
    );
    switcher = CapabilitiesSwitcher(host, now: () => _start);
    shell = PanelShellController(
      pages: [
        FakePanelPage('emoji').page,
        FakePanelPage(gif).page,
        FakePanelPage(stickers, labelKey: 'stickers').page,
      ],
      preferences: FakePreferenceStore(),
    );
  });
  tearDown(() {
    availability.dispose();
    shell.dispose();
    host.dispose();
    bulletins.dispose();
  });

  void bind(PageUnavailableForm form) => availability = ChatPanelAvailability(
    shell: shell,
    capabilities: host.capabilities,
    feedback: host.panelFeedback,
    chatId: host.chatId,
    stickersPageId: stickers,
    gifPageId: gif,
    form: form,
  );

  PageAvailability of(String pageId) => shell.availability.value[pageId]!;

  test('allowed rights leave both pages available', () {
    bind(PageUnavailableForm.dimmed);
    expect(of(stickers), const PageAvailability.available());
    expect(of(gif), const PageAvailability.available());
  });

  test('denying stickers in the switcher dims the sticker page with the '
      'denial text (Android) and moves the panel off it', () {
    bind(PageUnavailableForm.dimmed);
    shell.selectPage(stickers);

    switcher.toggle(CapabilityToggle.stickers);

    expect(of(stickers), PageAvailability.dimmed(stickerText));
    expect(of(gif), const PageAvailability.available());
    expect(shell.selectedPageId.value, 'emoji');
    final event = diagnostics.events.lastWhere(
      (e) => e.op == PanelShellOp.pageAvailability,
    );
    expect(event.correlation.chatId, 'chat-1');
    expect(event.fields['form'], 'dimmed');
  });

  test('on iOS the sticker page is hidden', () {
    bind(PageUnavailableForm.hidden);
    switcher.toggle(CapabilityToggle.stickers);

    expect(of(stickers), const PageAvailability.hidden());
    expect(shell.shownPages.value.map((p) => p.id), ['emoji', gif]);
  });

  test('on desktop the sticker page shows the denial text', () {
    bind(PageUnavailableForm.replaced);
    switcher.toggle(CapabilityToggle.stickers);

    expect(of(stickers), PageAvailability.replaced(stickerText));
  });

  test('the GIF row denies the GIF page alone, and allowing it again '
      'brings the page back', () {
    bind(PageUnavailableForm.replaced);
    switcher.toggle(CapabilityToggle.animation);

    expect(of(gif), PageAvailability.replaced(gifText));
    expect(of(stickers), const PageAvailability.available());

    host.update(
      (c) =>
          c.copyWith(sending: c.sending.copyWith(media: const SendableMedia())),
    );
    expect(of(gif), const PageAvailability.available());
  });

  testWidgets('a tap on the dimmed tab reports an attempt from the panel '
      'and shows the text at the tab, not as a bulletin', (tester) async {
    bind(PageUnavailableForm.dimmed);
    switcher.toggle(CapabilityToggle.stickers);
    await tester.pumpWidget(
      PanelShellTestScope(
        child: PanelShell(controller: shell, announcer: FakePanelAnnouncer()),
      ),
    );

    await tester.tap(find.text('Stickers'));
    await tester.pump();

    expect(find.text(stickerText), findsOneWidget);
    final denied = diagnostics.events
        .where((e) => e.op == CapabilitiesOp.denied)
        .single;
    expect(denied.fields['action'], CapabilityAction.sendSticker);
    expect(denied.fields['consumer'], CapabilityConsumer.panel);
    expect(denied.correlation.chatId, 'chat-1');
    expect(bulletins.current.value, isNull);
    await tester.pump(const Duration(seconds: 4));
  });
}
