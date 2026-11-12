import 'package:chat_composer/chat_composer.dart' show ComposerView;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The app's binding: the widgets binding with a messenger that answers the
/// text processing actions query once per run for every text field
/// ([ComposerView.shareTextActions]).
///
/// On Android each stock field (a panel page's search field) asks the
/// platform on every mount, a lookup on the UI thread that freezes the frame
/// a page switch shows in. With this binding only the first query, the
/// composer's prefetch after the first frame, reaches the platform.
///
/// Made once, first thing in `main`, in place of
/// `WidgetsFlutterBinding.ensureInitialized`: there is one binding per
/// isolate.
final class AppBinding extends WidgetsFlutterBinding {
  /// Makes the binding the isolate's.
  AppBinding();

  @override
  BinaryMessenger createBinaryMessenger() =>
      ComposerView.shareTextActions(super.createBinaryMessenger());
}
