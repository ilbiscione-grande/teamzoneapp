import 'package:flutter/foundation.dart';

typedef AppListSearchText<T> = String Function(T item);

class AppListController<T> extends ChangeNotifier {
  AppListController({required this.searchText, this.pageSize = 30});

  final int pageSize;
  final AppListSearchText<T> searchText;
  List<T> _items = const [];
  String _query = '';
  String? _filterKey;
  bool Function(T)? _filter;
  Comparator<T>? _comparator;
  int _visibleCount = 0;

  String get query => _query;
  String? get filterKey => _filterKey;

  List<T> get matchingItems {
    final normalizedQuery = _query.trim().toLowerCase();
    final result = _items
        .where((item) {
          if (_filter case final filter? when !filter(item)) return false;
          return normalizedQuery.isEmpty ||
              searchText(item).toLowerCase().contains(normalizedQuery);
        })
        .toList(growable: false);
    if (_comparator case final comparator?) {
      return result.toList()..sort(comparator);
    }
    return result;
  }

  List<T> get visibleItems =>
      matchingItems.take(_visibleCount).toList(growable: false);
  bool get hasMore => visibleItems.length < matchingItems.length;
  bool get hasActiveQuery => _query.isNotEmpty || _filter != null;

  void replaceItems(List<T> items) {
    _items = List.unmodifiable(items);
    _visibleCount = pageSize.clamp(0, _items.length);
    notifyListeners();
  }

  void setQuery(String value) {
    final normalized = value.trimLeft();
    if (_query == normalized) return;
    _query = normalized;
    _resetPage();
  }

  void setFilter({required String? key, bool Function(T)? predicate}) {
    if (_filterKey == key && _filter == predicate) return;
    _filterKey = key;
    _filter = predicate;
    _resetPage();
  }

  void setSort(Comparator<T>? comparator) {
    _comparator = comparator;
    _resetPage();
  }

  void loadMore() {
    final next = (_visibleCount + pageSize).clamp(0, matchingItems.length);
    if (next == _visibleCount) return;
    _visibleCount = next;
    notifyListeners();
  }

  void clearQueryAndFilter() {
    _query = '';
    _filterKey = null;
    _filter = null;
    _resetPage();
  }

  void _resetPage() {
    _visibleCount = pageSize.clamp(0, matchingItems.length);
    notifyListeners();
  }
}
