/// The versioned metrics document written once per launch (spec 6.6).
///
/// Pure Dart. Per-frame arrays are a sidecar ([FrameSidecar]), never part of
/// the document: the compare step reads only the metrics map.
library;

import 'metrics.dart';

/// Bumped when the document's shape changes.
const int kMetricsSchemaVersion = 1;

/// The metadata block: what produced the numbers.
final class LaunchMeta {
  const LaunchMeta({
    required this.device,
    required this.os,
    required this.flutterVersion,
    required this.dartVersion,
    required this.backend,
    required this.refreshRateHz,
    required this.semanticsMode,
    required this.corpusVersion,
    required this.buildMode,
    this.environment = const {},
  });

  factory LaunchMeta.fromJson(Map<String, Object?> json) => LaunchMeta(
    device: json['device']! as String,
    os: json['os']! as String,
    flutterVersion: json['flutterVersion']! as String,
    dartVersion: json['dartVersion']! as String,
    backend: json['backend']! as String,
    refreshRateHz: (json['refreshRateHz']! as num).toDouble(),
    semanticsMode: json['semanticsMode']! as String,
    corpusVersion: json['corpusVersion']! as int,
    buildMode: json['buildMode']! as String,
    environment: {...?(json['environment'] as Map<String, Object?>?)},
  );

  final String device;
  final String os;
  final String flutterVersion;
  final String dartVersion;

  /// `impeller` or `skia`, as observed.
  final String backend;

  /// As the display reported it.
  final double refreshRateHz;

  /// `on` or `off`, as observed at run time.
  final String semanticsMode;
  final int corpusVersion;

  /// `profile`, `debug` or `release`, as the app observed it.
  final String buildMode;

  /// Host-observed device state the runner adds after the launch: battery
  /// level and temperature at start and end, active input method, whether the
  /// cooldown bound was hit. Empty when the app wrote the document alone.
  final Map<String, Object?> environment;

  Map<String, Object?> toJson() => {
    'device': device,
    'os': os,
    'flutterVersion': flutterVersion,
    'dartVersion': dartVersion,
    'backend': backend,
    'refreshRateHz': refreshRateHz,
    'semanticsMode': semanticsMode,
    'corpusVersion': corpusVersion,
    'buildMode': buildMode,
    'environment': environment,
  };
}

/// Metadata plus, per `scenario id@version` and window, a flat map of named
/// metrics.
final class MetricsDocument {
  const MetricsDocument({required this.meta, required this.scenarios});

  factory MetricsDocument.fromJson(Map<String, Object?> json) {
    final scenarios = json['scenarios']! as Map<String, Object?>;
    return MetricsDocument(
      meta: LaunchMeta.fromJson(json['meta']! as Map<String, Object?>),
      scenarios: {
        for (final s in scenarios.entries)
          s.key: {
            for (final w in (s.value! as Map<String, Object?>).entries)
              w.key: {
                for (final m in (w.value! as Map<String, Object?>).entries)
                  m.key: Metric.fromJson(m.value! as Map<String, Object?>),
              },
          },
      },
    );
  }

  final LaunchMeta meta;

  /// `id@version` -> window -> metric name -> metric.
  final Map<String, Map<String, Map<String, Metric>>> scenarios;

  Map<String, Object?> toJson() => {
    'schema': kMetricsSchemaVersion,
    'meta': meta.toJson(),
    'scenarios': {
      for (final s in scenarios.entries)
        s.key: {
          for (final w in s.value.entries)
            w.key: {for (final m in w.value.entries) m.key: m.value.toJson()},
        },
    },
  };
}

/// Per-frame arrays of one launch, in milliseconds, keyed by
/// `id@version/window`. Written beside the metrics document.
final class FrameSidecar {
  const FrameSidecar(this.windows);

  final Map<String, List<FrameRow>> windows;

  Map<String, Object?> toJson() => {
    'schema': kMetricsSchemaVersion,
    'windows': {
      for (final w in windows.entries)
        w.key: {
          'buildMs': [for (final f in w.value) f.buildMs],
          'rasterMs': [for (final f in w.value) f.rasterMs],
          'totalMs': [for (final f in w.value) f.totalMs],
        },
    },
  };
}

/// One frame's timings.
final class FrameRow {
  const FrameRow(this.buildMs, this.rasterMs, this.totalMs);

  final double buildMs;
  final double rasterMs;
  final double totalMs;
}
