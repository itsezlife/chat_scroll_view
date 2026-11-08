/// The web hook behind `MediaDiskCache.sweep`: the web keeps no files, so
/// there is nothing to sweep.
Future<void> $sweepMediaFolder(
  String root, {
  required List<String> retire,
  required DateTime now,
  required Duration keepFor,
  required int? limitBytes,
  required Duration inUse,
}) async {}
