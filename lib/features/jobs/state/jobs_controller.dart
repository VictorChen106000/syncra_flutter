import 'package:flutter/foundation.dart';

/// Tracks per-job UX state — saved, hidden, dismissed — that the job list
/// page reacts to. Backend repositories can be wired into the same actions.
class JobsController extends ChangeNotifier {
  final Set<String> _savedIds = {};
  final Set<String> _hiddenIds = {};
  final Set<String> _dismissedIds = {};
  String? _lastMessage;

  Set<String> get savedIds => Set.unmodifiable(_savedIds);
  Set<String> get hiddenIds => Set.unmodifiable(_hiddenIds);
  Set<String> get dismissedIds => Set.unmodifiable(_dismissedIds);

  bool isSaved(String id) => _savedIds.contains(id);
  bool isHidden(String id) => _hiddenIds.contains(id);
  bool isDismissed(String id) => _dismissedIds.contains(id);

  String? consumeMessage() {
    final m = _lastMessage;
    _lastMessage = null;
    return m;
  }

  void toggleSaved(String id, {String label = ''}) {
    final added = !_savedIds.contains(id);
    if (added) {
      _savedIds.add(id);
      _lastMessage = label.isEmpty ? 'Saved' : 'Saved $label';
    } else {
      _savedIds.remove(id);
      _lastMessage = label.isEmpty ? 'Removed from saved' : 'Unsaved $label';
    }
    notifyListeners();
  }

  void hide(String id, {String label = ''}) {
    _hiddenIds.add(id);
    _dismissedIds.add(id);
    _lastMessage = label.isEmpty ? 'Hidden' : 'Hidden $label';
    notifyListeners();
  }

  void unhide(String id) {
    _hiddenIds.remove(id);
    _dismissedIds.remove(id);
    notifyListeners();
  }

  void dismiss(String id, {String label = ''}) {
    _dismissedIds.add(id);
    _lastMessage = label.isEmpty ? 'Dismissed' : '$label dismissed';
    notifyListeners();
  }

  void undismiss(String id) {
    _dismissedIds.remove(id);
    notifyListeners();
  }
}
