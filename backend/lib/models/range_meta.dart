/// Boundary hints for a message range response.
class RangeMeta {
  const RangeMeta({
    required this.requestedFrom,
    required this.requestedTo,
    required this.oldestId,
    required this.newestId,
    required this.totalMessages,
    required this.hasOlder,
    required this.hasNewer,
  });

  final int requestedFrom;
  final int requestedTo;
  final int? oldestId;
  final int? newestId;
  final int totalMessages;
  final bool hasOlder;
  final bool hasNewer;

  Map<String, Object?> toJson() => {
    'requestedFrom': requestedFrom,
    'requestedTo': requestedTo,
    'oldestId': oldestId,
    'newestId': newestId,
    'totalMessages': totalMessages,
    'hasOlder': hasOlder,
    'hasNewer': hasNewer,
  };

  /// Compute [RangeMeta] for a range request against conversation bounds.
  static RangeMeta compute({
    required int fromId,
    required int toId,
    required int totalMessages,
  }) {
    final requestedFrom = fromId;
    var requestedTo = toId;
    if (totalMessages <= 0) {
      return RangeMeta(
        requestedFrom: requestedFrom,
        requestedTo: requestedTo,
        oldestId: null,
        newestId: null,
        totalMessages: 0,
        hasOlder: false,
        hasNewer: false,
      );
    }

    final oldestId = 0;
    final newestId = totalMessages - 1;
    if (requestedTo > newestId) {
      requestedTo = newestId;
    }

    final hasOlder = fromId > oldestId;
    final hasNewer = toId < newestId;

    return RangeMeta(
      requestedFrom: requestedFrom,
      requestedTo: requestedTo,
      oldestId: oldestId,
      newestId: newestId,
      totalMessages: totalMessages,
      hasOlder: hasOlder,
      hasNewer: hasNewer,
    );
  }
}
