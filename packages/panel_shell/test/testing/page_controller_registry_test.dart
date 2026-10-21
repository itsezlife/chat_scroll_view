import 'package:panel_shell/panel_shell.dart';
import 'package:panel_shell/testing.dart';

void main() {
  PageControllerRegistryContract.run(
    PanelPageControllers.new,
    (registry) => (registry as PanelPageControllers).dispose(),
  );
  PageControllerRegistryContract.run(
    FakePageControllerRegistry.new,
    (registry) => (registry as FakePageControllerRegistry).disposeAll(),
  );
}
