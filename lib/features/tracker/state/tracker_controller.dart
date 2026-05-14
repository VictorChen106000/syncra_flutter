import 'package:flutter/foundation.dart';

import '../../../data/mock/mock_tracked_applications.dart';
import '../../../data/models/job.dart';

/// Either "All" or a specific status used to filter the tracker list.
class TrackerFilter {
  const TrackerFilter.all() : status = null;
  const TrackerFilter.status(JobStatus s) : status = s;

  /// `null` when "All", otherwise the status the user is filtering by.
  final JobStatus? status;

  bool get isAll => status == null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrackerFilter && other.status == status;

  @override
  int get hashCode => status.hashCode;
}

class TrackerController extends ChangeNotifier {
  TrackerController() : _items = List.of(MockTrackedApplications.all);

  final List<TrackedApplication> _items;
  TrackerFilter _filter = const TrackerFilter.all();
  String? _lastMessage;

  TrackerFilter get filter => _filter;
  List<TrackedApplication> get items => List.unmodifiable(_items);

  String? consumeMessage() {
    final m = _lastMessage;
    _lastMessage = null;
    return m;
  }

  List<TrackedApplication> get filtered {
    final s = _filter.status;
    if (s == null) return List.unmodifiable(_items);
    return _items.where((a) => a.status == s).toList();
  }

  void setFilter(TrackerFilter f) {
    _filter = f;
    notifyListeners();
  }

  void updateStatus(String jobId, JobStatus status) {
    final idx = _items.indexWhere((a) => a.job.id == jobId);
    if (idx == -1) return;
    final next = _items[idx].copyWith(
      status: status,
      lastUpdate: 'Just now',
    );
    _items[idx] = next;
    _lastMessage = '${next.job.company}: status set to ${status.label}';
    notifyListeners();
  }

  void addNote(String jobId, String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return;
    final idx = _items.indexWhere((a) => a.job.id == jobId);
    if (idx == -1) return;
    final current = _items[idx];
    final notes = List<TrackedApplicationNote>.from(current.notes)
      ..insert(
        0,
        TrackedApplicationNote(body: trimmed, createdAt: DateTime.now()),
      );
    _items[idx] = current.copyWith(notes: notes, lastUpdate: 'Just now');
    _lastMessage = 'Note added to ${current.job.company}';
    notifyListeners();
  }
}
