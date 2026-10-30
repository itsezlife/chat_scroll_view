/// Every registered scenario family, in the order they run.
library;

import '../registry.dart';
import 'churn_scenarios.dart';
import 'scroll_scenarios.dart';

final allScenarios = ScenarioRegistry([
  ...scrollScenarios.all,
  ...churnScenarios.all,
]);
