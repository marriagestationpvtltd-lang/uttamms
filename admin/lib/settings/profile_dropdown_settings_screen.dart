import 'dart:convert';

import 'package:adminmrz/config/app_endpoints.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────
const _kPrimary = Color(0xFF6366F1);
const _kDanger = Color(0xFFEF4444);
const _kSuccess = Color(0xFF10B981);
const _kWarning = Color(0xFFF59E0B);
const _kBg = Color(0xFFF8FAFC);
const _kBorder = Color(0xFFE2E8F0);
const _kSub = Color(0xFF64748B);

// ─────────────────────────────────────────────────────────────────────────────
// Root screen — owns load/persist + TabBar
// ─────────────────────────────────────────────────────────────────────────────
class ProfileDropdownSettingsScreen extends StatefulWidget {
  const ProfileDropdownSettingsScreen({super.key});

  @override
  State<ProfileDropdownSettingsScreen> createState() =>
      _ProfileDropdownSettingsScreenState();
}

class _ProfileDropdownSettingsScreenState
    extends State<ProfileDropdownSettingsScreen>
    with SingleTickerProviderStateMixin {
  static final _getUri = Uri.parse(
    '$kAdminApi9BaseUrl/get_profile_dropdown_master.php',
  );
  static final _updateUri = Uri.parse(
    '$kAdminApi9BaseUrl/update_profile_dropdown_master.php',
  );

  static const _fields = [
    {'key': 'religion', 'label': 'Religion', 'icon': '\u{1F6D5}\uFE0F'},
    {'key': 'community', 'label': 'Community', 'icon': '\u{1F465}'},
    {'key': 'castgroup', 'label': 'Cast Group', 'icon': '\u{1F3F7}\uFE0F'},
    {'key': 'caste', 'label': 'Cast', 'icon': '\u{1F3DB}\uFE0F'},
    {'key': 'annualincome', 'label': 'Annual Income', 'icon': '\u{1F4B0}'},
    {'key': 'educationtype', 'label': 'Education Type', 'icon': '\u{1F393}'},
    {'key': 'degree', 'label': 'Degree', 'icon': '\u{1F4DC}'},
    {'key': 'faculty', 'label': 'Faculty', 'icon': '\u{1F3DB}\uFE0F'},
    {
      'key': 'educationmedium',
      'label': 'Education Medium',
      'icon': '\u{1F4DA}',
    },
    {'key': 'occupationtype', 'label': 'Occupation Type', 'icon': '\u{1F4BC}'},
    {'key': 'workingwith', 'label': 'Working With', 'icon': '\u{1F3E2}'},
  ];

  // Parent holds last-synced lists (for tab badge counts only)
  final Map<String, List<String>> _synced = {};
  late final TabController _tabController;
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _fields.length, vsync: this);
    for (final f in _fields) {
      _synced[f['key']!] = [];
    }
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<String?> _token() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final token = await _token();
      final res = await http.get(
        _getUri,
        headers: {
          'Accept': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );
      if (res.statusCode != 200) {
        throw Exception('Server error ${res.statusCode}');
      }
      final data = json.decode(res.body);
      final map = data['data'] is Map
          ? Map<String, dynamic>.from(data['data'] as Map)
          : <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        for (final f in _fields) {
          final k = f['key']!;
          _synced[k] = map[k] is List
              ? (map[k] as List)
                    .map((e) => e.toString().trim())
                    .where((e) => e.isNotEmpty)
                    .toList()
              : [];
        }
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = e.toString();
      });
    }
  }

  /// Called by _FieldTab on every save; syncs badge counts in parent.
  Future<void> _persist(String fieldKey, List<String> items) async {
    final token = await _token();
    final res = await http.post(
      _updateUri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: json.encode({'field': fieldKey, 'options': items}),
    );
    if (res.statusCode != 200) {
      final body = json.decode(res.body) as Map;
      throw Exception(body['message']?.toString() ?? 'Save failed');
    }
    if (mounted) setState(() => _synced[fieldKey] = List<String>.from(items));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        title: const Text(
          'Dropdown Options Master',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          if (!_isLoading)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Reload from server',
              onPressed: _load,
            ),
        ],
        bottom: _isLoading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(
                  color: _kPrimary,
                  backgroundColor: Colors.transparent,
                ),
              )
            : PreferredSize(
                preferredSize: const Size.fromHeight(46),
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  labelColor: _kPrimary,
                  unselectedLabelColor: _kSub,
                  indicatorColor: _kPrimary,
                  indicatorWeight: 3,
                  tabAlignment: TabAlignment.start,
                  labelStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  unselectedLabelStyle: const TextStyle(fontSize: 12),
                  tabs: _fields.map((f) {
                    final count = _synced[f['key']!]?.length ?? 0;
                    return Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(f['label']!),
                          const SizedBox(width: 6),
                          _Badge(count: count),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
      ),
      body: _loadError != null
          ? _buildError()
          : _isLoading
          ? const SizedBox.shrink()
          : TabBarView(
              controller: _tabController,
              children: _fields
                  .map(
                    (f) => _FieldTab(
                      key: ValueKey(f['key']!),
                      fieldKey: f['key']!,
                      fieldLabel: f['label']!,
                      fieldIcon: f['icon']!,
                      initialItems: List<String>.from(_synced[f['key']!]!),
                      onPersist: (items) => _persist(f['key']!, items),
                    ),
                  )
                  .toList(),
            ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _kDanger.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.cloud_off_rounded,
                color: _kDanger,
                size: 32,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Failed to load',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              _loadError!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: _kSub),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Per-field tab — StatefulWidget so showDialog always uses valid context
// ─────────────────────────────────────────────────────────────────────────────
class _FieldTab extends StatefulWidget {
  const _FieldTab({
    super.key,
    required this.fieldKey,
    required this.fieldLabel,
    required this.fieldIcon,
    required this.initialItems,
    required this.onPersist,
  });

  final String fieldKey;
  final String fieldLabel;
  final String fieldIcon;
  final List<String> initialItems;
  final Future<void> Function(List<String>) onPersist;

  @override
  State<_FieldTab> createState() => _FieldTabState();
}

class _FieldTabState extends State<_FieldTab>
    with AutomaticKeepAliveClientMixin {
  late List<String> _items;
  final Set<int> _selected = {};
  final _addCtrl = TextEditingController();
  final _addFocus = FocusNode();
  final _searchCtrl = TextEditingController();
  bool _saving = false;
  bool _showAdd = false;
  String _search = '';
  bool _showSearch = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _items = List<String>.from(widget.initialItems);
  }

  @override
  void didUpdateWidget(covariant _FieldTab old) {
    super.didUpdateWidget(old);
    if (!_saving && old.initialItems != widget.initialItems) {
      setState(() {
        _items = List<String>.from(widget.initialItems);
        _selected.clear();
      });
    }
  }

  @override
  void dispose() {
    _addCtrl.dispose();
    _addFocus.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      await widget.onPersist(List<String>.from(_items));
      if (!mounted) return;
      _snack('Saved', isError: false);
    } catch (e) {
      if (!mounted) return;
      _snack('Save failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg, {required bool isError}) {
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? _kDanger : _kSuccess,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  bool _isDuplicate(String v, {int? skip}) => _items.asMap().entries.any(
    (e) =>
        (skip == null || e.key != skip) &&
        e.value.trim().toLowerCase() == v.trim().toLowerCase(),
  );

  void _commitAdd() {
    final val = _addCtrl.text.trim();
    if (val.isEmpty) {
      HapticFeedback.lightImpact();
      return;
    }
    if (_isDuplicate(val)) {
      HapticFeedback.lightImpact();
      _snack('"$val" already exists', isError: true);
      return;
    }
    setState(() {
      _items.add(val);
      _addCtrl.clear();
      _showAdd = false;
    });
    _save();
  }

  void _openAdd() {
    setState(() => _showAdd = true);
    Future.delayed(const Duration(milliseconds: 60), () {
      if (mounted) _addFocus.requestFocus();
    });
  }

  Future<void> _editItem(int index) async {
    final ctrl = TextEditingController(text: _items[index]);
    String? result;
    try {
      result = await showDialog<String>(
        context: context,
        barrierColor: Colors.black54,
        builder: (ctx) => _EditDialog(
          title: 'Edit ${widget.fieldLabel}',
          controller: ctrl,
          onDone: (v) => Navigator.of(ctx).pop(v.trim()),
          onCancel: () => Navigator.of(ctx).pop(),
        ),
      );
    } finally {
      ctrl.dispose();
    }
    if (!mounted || result == null || result.isEmpty) return;
    if (result == _items[index]) return;
    if (_isDuplicate(result, skip: index)) {
      _snack('"$result" already exists', isError: true);
      return;
    }
    setState(() => _items[index] = result!);
    await _save();
  }

  Future<void> _deleteItem(int index) async {
    final item = _items[index];
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => _ConfirmDialog(
        message: 'Remove "$item" from the list?',
        onConfirm: () => Navigator.of(ctx).pop(true),
        onCancel: () => Navigator.of(ctx).pop(false),
      ),
    );
    if (!mounted || ok != true) return;

    setState(() {
      _items.removeAt(index);
      final newSel = <int>{};
      for (final s in _selected) {
        if (s < index) newSel.add(s);
        if (s > index) newSel.add(s - 1);
      }
      _selected
        ..clear()
        ..addAll(newSel);
    });
    await _save();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Removed "$item"'),
        backgroundColor: const Color(0xFF334155),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        action: SnackBarAction(
          label: 'Undo',
          textColor: Colors.amber,
          onPressed: () {
            if (!mounted) return;
            setState(() {
              _items.insert(index, item);
              _selected.clear();
            });
            _save();
          },
        ),
      ),
    );
  }

  Future<void> _bulkDelete() async {
    if (_selected.isEmpty) return;
    final n = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => _ConfirmDialog(
        message:
            'Permanently delete $n selected option${n > 1 ? 's' : ''}?\n\nThis cannot be undone.',
        isDanger: true,
        onConfirm: () => Navigator.of(ctx).pop(true),
        onCancel: () => Navigator.of(ctx).pop(false),
      ),
    );
    if (!mounted || ok != true) return;
    final sorted = _selected.toList()..sort((a, b) => b.compareTo(a));
    setState(() {
      for (final i in sorted) _items.removeAt(i);
      _selected.clear();
    });
    await _save();
  }

  Future<void> _onReorder(int oldIdx, int newIdx) async {
    if (newIdx > oldIdx) newIdx--;
    setState(() {
      final item = _items.removeAt(oldIdx);
      _items.insert(newIdx, item);
      _selected.clear();
    });
    await _save();
  }

  List<(int, String)> get _filtered {
    if (_search.isEmpty) {
      return [for (var i = 0; i < _items.length; i++) (i, _items[i])];
    }
    return [
      for (var i = 0; i < _items.length; i++)
        if (_items[i].toLowerCase().contains(_search.toLowerCase()))
          (i, _items[i]),
    ];
  }

  bool get _allSelected =>
      _items.isNotEmpty && _selected.length == _items.length;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final filtered = _filtered;
    final hasSel = _selected.isNotEmpty;

    return Column(
      children: [
        _buildToolbar(hasSel),
        if (_showAdd) _buildAddRow(),
        if (_showSearch) _buildSearchRow(),
        const Divider(height: 1, color: _kBorder),
        if (_items.isEmpty && !_showAdd)
          _buildEmptyState()
        else if (filtered.isEmpty && _search.isNotEmpty)
          _buildNoResults()
        else
          Expanded(child: _buildList(filtered)),
      ],
    );
  }

  Widget _buildToolbar(bool hasSel) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: Row(
        children: [
          if (hasSel) ...[
            Checkbox(
              value: _allSelected ? true : (_selected.isEmpty ? false : null),
              tristate: !_allSelected && _selected.isNotEmpty,
              activeColor: _kPrimary,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (_) => setState(() {
                if (_allSelected) {
                  _selected.clear();
                } else {
                  _selected.addAll(List.generate(_items.length, (i) => i));
                }
              }),
            ),
            const SizedBox(width: 4),
            Text(
              '${_selected.length} selected',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() => _selected.clear()),
              style: TextButton.styleFrom(
                foregroundColor: _kSub,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Cancel', style: TextStyle(fontSize: 13)),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _bulkDelete,
              icon: const Icon(Icons.delete_sweep_rounded, size: 16),
              label: Text('Delete ${_selected.length}'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kDanger,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ] else ...[
            _CountChip(count: _items.length, icon: widget.fieldIcon),
            const Spacer(),
            if (_saving)
              const Padding(
                padding: EdgeInsets.only(right: 10),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _kPrimary,
                  ),
                ),
              ),
            IconButton(
              icon: Icon(
                _showSearch ? Icons.search_off_rounded : Icons.search_rounded,
              ),
              iconSize: 20,
              tooltip: 'Search',
              color: _showSearch ? _kPrimary : _kSub,
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) {
                  _search = '';
                  _searchCtrl.clear();
                }
              }),
            ),
            ElevatedButton.icon(
              onPressed: _showAdd
                  ? () => setState(() {
                      _showAdd = false;
                      _addCtrl.clear();
                    })
                  : _openAdd,
              icon: Icon(
                _showAdd ? Icons.close_rounded : Icons.add_rounded,
                size: 16,
              ),
              label: Text(_showAdd ? 'Cancel' : 'Add'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _showAdd ? Colors.grey.shade100 : _kPrimary,
                foregroundColor: _showAdd ? Colors.black87 : Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAddRow() {
    return Container(
      color: _kPrimary.withOpacity(0.04),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _addCtrl,
              focusNode: _addFocus,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _commitAdd(),
              decoration: InputDecoration(
                hintText: 'New ${widget.fieldLabel} option\u2026',
                hintStyle: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFFADB5BD),
                ),
                filled: true,
                fillColor: Colors.white,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _kBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _kBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _kPrimary, width: 1.5),
                ),
                prefixIcon: const Icon(
                  Icons.add_circle_outline_rounded,
                  size: 18,
                  color: _kPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: _commitAdd,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchRow() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _search = v),
        decoration: InputDecoration(
          hintText: 'Search ${widget.fieldLabel}\u2026',
          hintStyle: const TextStyle(fontSize: 13),
          isDense: true,
          filled: true,
          fillColor: const Color(0xFFF1F5F9),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 9,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          prefixIcon: const Icon(Icons.search_rounded, size: 18, color: _kSub),
          suffixIcon: _search.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16),
                  onPressed: () => setState(() {
                    _search = '';
                    _searchCtrl.clear();
                  }),
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Expanded(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: _kPrimary.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    widget.fieldIcon,
                    style: const TextStyle(fontSize: 36),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'No options yet',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Add the first option for "${widget.fieldLabel}"',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: _kSub),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _openAdd,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add First Option'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoResults() {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.search_off_rounded,
              size: 48,
              color: Color(0xFFCBD5E1),
            ),
            const SizedBox(height: 12),
            Text(
              'No match for "$_search"',
              style: const TextStyle(fontSize: 14, color: _kSub),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(List<(int, String)> filtered) {
    if (_search.isNotEmpty) {
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: filtered.length,
        itemBuilder: (_, i) {
          final (realIdx, item) = filtered[i];
          return _buildTile(realIdx, item, reorderMode: false, query: _search);
        },
      );
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _items.length,
      onReorder: _onReorder,
      proxyDecorator: (child, index, animation) => Material(
        elevation: 6,
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        shadowColor: _kPrimary.withOpacity(0.25),
        child: child,
      ),
      itemBuilder: (_, idx) => _buildTile(
        idx,
        _items[idx],
        reorderMode: true,
        query: '',
        key: ValueKey('${widget.fieldKey}::${_items[idx]}'),
      ),
    );
  }

  Widget _buildTile(
    int index,
    String item, {
    required bool reorderMode,
    required String query,
    Key? key,
  }) {
    final isSel = _selected.contains(index);
    return _ItemTile(
      key: key,
      index: index,
      item: item,
      isSelected: isSel,
      reorderMode: reorderMode,
      searchQuery: query,
      onTap: () => setState(() {
        if (isSel) {
          _selected.remove(index);
        } else {
          _selected.add(index);
        }
      }),
      onLongPress: () => _editItem(index),
      onEdit: () => _editItem(index),
      onDelete: () => _deleteItem(index),
      onCheckChanged: (v) => setState(
        () => v == true ? _selected.add(index) : _selected.remove(index),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stateless item tile
// ─────────────────────────────────────────────────────────────────────────────
class _ItemTile extends StatelessWidget {
  const _ItemTile({
    super.key,
    required this.index,
    required this.item,
    required this.isSelected,
    required this.reorderMode,
    required this.searchQuery,
    required this.onTap,
    required this.onLongPress,
    required this.onEdit,
    required this.onDelete,
    required this.onCheckChanged,
  });

  final int index;
  final String item;
  final bool isSelected;
  final bool reorderMode;
  final String searchQuery;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool?> onCheckChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: isSelected ? _kPrimary.withOpacity(0.06) : Colors.white,
        elevation: isSelected ? 2 : 0,
        shadowColor: _kPrimary.withOpacity(0.15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: isSelected ? _kPrimary.withOpacity(0.4) : _kBorder,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            child: Row(
              children: [
                if (reorderMode)
                  ReorderableDragStartListener(
                    index: index,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      child: Icon(
                        Icons.drag_handle_rounded,
                        size: 18,
                        color: isSelected
                            ? _kPrimary.withOpacity(0.5)
                            : const Color(0xFFCBD5E1),
                      ),
                    ),
                  )
                else
                  const SizedBox(width: 10),
                SizedBox(
                  width: 22,
                  height: 22,
                  child: Checkbox(
                    value: isSelected,
                    activeColor: _kPrimary,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    side: BorderSide(
                      color: isSelected ? _kPrimary : const Color(0xFFCBD5E1),
                      width: 1.5,
                    ),
                    onChanged: onCheckChanged,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? _kPrimary.withOpacity(0.12)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? _kPrimary : _kSub,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _HighlightText(
                    text: item,
                    query: searchQuery,
                    isSelected: isSelected,
                  ),
                ),
                _IconBtn(
                  icon: Icons.edit_outlined,
                  color: _kSub,
                  tooltip: 'Edit',
                  onPressed: onEdit,
                ),
                _IconBtn(
                  icon: Icons.delete_outline_rounded,
                  color: _kDanger.withOpacity(0.75),
                  tooltip: 'Delete',
                  onPressed: onDelete,
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Edit dialog
// ─────────────────────────────────────────────────────────────────────────────
class _EditDialog extends StatelessWidget {
  const _EditDialog({
    required this.title,
    required this.controller,
    required this.onDone,
    required this.onCancel,
  });

  final String title;
  final TextEditingController controller;
  final ValueChanged<String> onDone;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _kPrimary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.edit_rounded,
                    size: 18,
                    color: _kPrimary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onSubmitted: (v) => onDone(v.trim()),
              decoration: InputDecoration(
                labelText: 'Option name',
                labelStyle: const TextStyle(color: _kSub),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _kPrimary, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onCancel,
                  style: TextButton.styleFrom(foregroundColor: _kSub),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => onDone(controller.text.trim()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                  ),
                  child: const Text(
                    'Update',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Confirm delete dialog
// ─────────────────────────────────────────────────────────────────────────────
class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.message,
    required this.onConfirm,
    required this.onCancel,
    this.isDanger = false,
  });

  final String message;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final bool isDanger;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: _kDanger.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.delete_outline_rounded,
                color: _kDanger,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Confirm Delete',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: _kSub),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onCancel,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kSub,
                      side: const BorderSide(color: _kBorder),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onConfirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kDanger,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'Delete',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small helpers
// ─────────────────────────────────────────────────────────────────────────────
class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.count, required this.icon});
  final int count;
  final String icon;

  @override
  Widget build(BuildContext context) {
    final has = count > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: has ? _kPrimary.withOpacity(0.08) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: has ? _kPrimary.withOpacity(0.2) : _kBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 6),
          Text(
            '$count option${count != 1 ? 's' : ''}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: has ? _kPrimary : _kSub,
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: count > 0
            ? _kPrimary.withOpacity(0.12)
            : Colors.grey.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: count > 0 ? _kPrimary : Colors.grey,
        ),
      ),
    );
  }
}

class _HighlightText extends StatelessWidget {
  const _HighlightText({
    required this.text,
    required this.query,
    required this.isSelected,
  });

  final String text;
  final String query;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: isSelected ? _kPrimary : const Color(0xFF1E293B),
    );
    if (query.isEmpty) return Text(text, style: base);
    final lower = text.toLowerCase();
    final q = query.toLowerCase();
    final start = lower.indexOf(q);
    if (start < 0) return Text(text, style: base);
    return RichText(
      text: TextSpan(
        style: base,
        children: [
          if (start > 0) TextSpan(text: text.substring(0, start)),
          TextSpan(
            text: text.substring(start, start + q.length),
            style: base.copyWith(
              backgroundColor: _kWarning.withOpacity(0.25),
              color: const Color(0xFFB45309),
              fontWeight: FontWeight.w700,
            ),
          ),
          if (start + q.length < text.length)
            TextSpan(text: text.substring(start + q.length)),
        ],
      ),
    );
  }
}
