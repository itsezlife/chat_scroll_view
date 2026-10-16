import 'package:panel_shell/panel_shell.dart';
import 'package:panel_shell/testing.dart';

void main() {
  runPageControllerRegistryContract(
    PanelPageControllers.new,
    (registry) => (registry as PanelPageControllers).dispose(),
  );
  runPageControllerRegistryContract(
    FakePageControllerRegistry.new,
    (registry) => (registry as FakePageControllerRegistry).disposeAll(),
  );
}
