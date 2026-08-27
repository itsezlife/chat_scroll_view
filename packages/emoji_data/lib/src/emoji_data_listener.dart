import 'package:flutter/foundation.dart';

/// Synchronous data listeners.
mixin EmojiDataListenerMixin {
  final _dataListeners = <VoidCallback>[];

  void addDataListener(VoidCallback callback) {
    if (_dataListeners.contains(callback)) return;
    _dataListeners.add(callback);
  }

  void removeDataListener(VoidCallback callback) {
    _dataListeners.remove(callback);
  }

  @protected
  void notifyDataChanged() {
    for (final cb in List<VoidCallback>.of(_dataListeners, growable: false)) {
      cb();
    }
  }

  @protected
  void disposeDataListeners() {
    _dataListeners.clear();
  }
}
