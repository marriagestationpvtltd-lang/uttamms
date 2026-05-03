import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:adminmrz/config/app_endpoints.dart';
import 'package:adminmrz/package/packagemodel.dart';
import 'package:adminmrz/package/packageservice.dart';

// ─── Colors ──────────────────────────────────────────────────────────────────
const _kPrimary = Color(0xFF6366F1);
const _kGreen = Color(0xFF10B981);
const _kRed = Color(0xFFEF4444);
const _kAmber = Color(0xFFF59E0B);
const _kBg = Color(0xFFF8F9FB);
const _kCard = Colors.white;

// ─── Model ───────────────────────────────────────────────────────────────────

class UserPackageRecord {
  final int id;
  final int packageId;
  final String packageName;
  final String packageDuration;
  final double amount;
  final String amountDisplay;
  final String paymentMethod;
  final String note;
  final String purchasedate;
  final String expiredate;
  final String status; // 'active' | 'expired'
  final bool isAdminAssigned;

  const UserPackageRecord({
    required this.id,
    required this.packageId,
    required this.packageName,
    required this.packageDuration,
    required this.amount,
    required this.amountDisplay,
    required this.paymentMethod,
    required this.note,
    required this.purchasedate,
    required this.expiredate,
    required this.status,
    required this.isAdminAssigned,
  });

  bool get isActive => status == 'active';

  factory UserPackageRecord.fromJson(Map<String, dynamic> j) {
    return UserPackageRecord(
      id: (j['id'] as num?)?.toInt() ?? 0,
      packageId: (j['packageid'] as num?)?.toInt() ?? 0,
      packageName: j['package_name']?.toString() ?? '',
      packageDuration: j['package_duration']?.toString() ?? '',
      amount: (j['amount'] as num?)?.toDouble() ?? 0,
      amountDisplay: j['amount_display']?.toString() ?? '',
      paymentMethod: j['payment_method']?.toString() ?? '',
      note: j['note']?.toString() ?? '',
      purchasedate: j['purchasedate']?.toString() ?? '',
      expiredate: j['expiredate']?.toString() ?? '',
      status: j['status']?.toString() ?? 'expired',
      isAdminAssigned: j['is_admin_assigned'] == true,
    );
  }
}

// ─── Service ─────────────────────────────────────────────────────────────────

class UserPackageService {
  final String _base = kAdminApi9BaseUrl;

  Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<Map<String, dynamic>> getHistory(int userId) async {
    final res = await http.get(
      Uri.parse('$_base/get_user_package_history.php?userid=$userId'),
      headers: await _headers(),
    );
    if (res.statusCode == 200)
      return json.decode(res.body) as Map<String, dynamic>;
    throw Exception('Failed to load package history (${res.statusCode})');
  }

  Future<Map<String, dynamic>> assignPackage({
    required int userId,
    required int packageId,
    required double amount,
    required String paymentMethod,
    String note = '',
  }) async {
    final res = await http.post(
      Uri.parse('$_base/admin_assign_package.php'),
      headers: await _headers(),
      body: json.encode({
        'userid': userId,
        'packageid': packageId,
        'amount': amount,
        'payment_method': paymentMethod,
        'note': note,
      }),
    );
    if (res.statusCode == 200)
      return json.decode(res.body) as Map<String, dynamic>;
    throw Exception('Failed to assign package (${res.statusCode})');
  }
}

// ─── Main Section Widget ─────────────────────────────────────────────────────

class UserPackageSection extends StatefulWidget {
  const UserPackageSection({super.key, required this.userId});
  final int userId;

  @override
  State<UserPackageSection> createState() => _UserPackageSectionState();
}

class _UserPackageSectionState extends State<UserPackageSection> {
  final _svc = UserPackageService();

  bool _loading = true;
  String? _error;
  UserPackageRecord? _active;
  List<UserPackageRecord> _history = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _svc.getHistory(widget.userId);
      final rawHistory = (data['history'] as List<dynamic>? ?? []);
      final active = data['active'];
      setState(() {
        _active = active != null
            ? UserPackageRecord.fromJson(active as Map<String, dynamic>)
            : null;
        _history = rawHistory
            .map((e) => UserPackageRecord.fromJson(e as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: 'Package & Subscription',
            icon: Icons.card_membership_rounded,
            onAssign: _openAssignDialog,
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_error != null)
            _ErrorBar(message: _error!, onRetry: _load)
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: _ActivePackageCard(active: _active),
            ),
            if (_history.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 18, 16, 6),
                child: Text(
                  'Purchase History',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF374151),
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              ..._history.map((r) => _HistoryTile(record: r)),
            ],
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Future<void> _openAssignDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _AssignPackageDialog(userId: widget.userId, service: _svc),
    );
    if (result == true && mounted) _load();
  }
}

// ─── Section header ──────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.icon,
    required this.onAssign,
  });

  final String title;
  final IconData icon;
  final VoidCallback onAssign;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _kPrimary.withOpacity(0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: _kPrimary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: onAssign,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Assign Package', style: TextStyle(fontSize: 13)),
            style: FilledButton.styleFrom(
              backgroundColor: _kPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Active package card ─────────────────────────────────────────────────────

class _ActivePackageCard extends StatelessWidget {
  const _ActivePackageCard({required this.active});
  final UserPackageRecord? active;

  @override
  Widget build(BuildContext context) {
    if (active == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Icon(Icons.block_rounded, color: Colors.grey.shade400, size: 22),
            const SizedBox(width: 12),
            Text(
              'No active package',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13.5),
            ),
          ],
        ),
      );
    }

    final expire = _parseDate(active!.expiredate);
    final daysLeft = expire != null
        ? expire.difference(DateTime.now()).inDays
        : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_kGreen.withOpacity(0.08), _kGreen.withOpacity(0.02)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kGreen.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _kGreen.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.verified_rounded, color: _kGreen, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        active!.packageName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF064E3B),
                        ),
                      ),
                    ),
                    if (active!.isAdminAssigned)
                      _Badge(label: 'Admin', color: _kPrimary),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    _InfoChip(
                      icon: Icons.payment_rounded,
                      label: active!.paymentMethod,
                    ),
                    _InfoChip(
                      icon: Icons.currency_rupee_rounded,
                      label: active!.amountDisplay,
                    ),
                    _InfoChip(
                      icon: Icons.timer_outlined,
                      label: active!.packageDuration,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 12,
                      color: Colors.green.shade700,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Expires: ${_formatDate(active!.expiredate)}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (daysLeft != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        '($daysLeft days left)',
                        style: TextStyle(
                          fontSize: 11,
                          color: daysLeft < 30
                              ? _kAmber
                              : Colors.green.shade600,
                        ),
                      ),
                    ],
                  ],
                ),
                if (active!.note.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Note: ${active!.note}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── History tile ─────────────────────────────────────────────────────────────

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.record});
  final UserPackageRecord record;

  @override
  Widget build(BuildContext context) {
    final isActive = record.isActive;
    final statusColor = isActive ? _kGreen : Colors.grey.shade400;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActive ? _kGreen.withOpacity(0.2) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status dot
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        record.packageName,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ),
                    if (record.isAdminAssigned)
                      _Badge(label: 'Admin', color: _kPrimary),
                    const SizedBox(width: 6),
                    _Badge(
                      label: isActive ? 'Active' : 'Expired',
                      color: statusColor,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 14,
                  runSpacing: 2,
                  children: [
                    _InfoChip(
                      icon: Icons.currency_rupee_rounded,
                      label: record.amountDisplay,
                    ),
                    _InfoChip(
                      icon: Icons.payment_rounded,
                      label: record.paymentMethod,
                    ),
                    _InfoChip(
                      icon: Icons.date_range_outlined,
                      label: _formatDate(record.purchasedate),
                    ),
                    _InfoChip(
                      icon: Icons.event_busy_outlined,
                      label: 'Exp: ${_formatDate(record.expiredate)}',
                    ),
                  ],
                ),
                if (record.note.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Note: ${record.note}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Assign Package Dialog ───────────────────────────────────────────────────

const List<String> _kPaymentMethods = [
  'Cash',
  'eSewa',
  'Khalti',
  'Bank Transfer',
  'IME Pay',
  'ConnectIPS',
  'Admin Override',
];

class _AssignPackageDialog extends StatefulWidget {
  const _AssignPackageDialog({required this.userId, required this.service});
  final int userId;
  final UserPackageService service;

  @override
  State<_AssignPackageDialog> createState() => _AssignPackageDialogState();
}

class _AssignPackageDialogState extends State<_AssignPackageDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  bool _loadingPkgs = true;
  bool _submitting = false;
  String? _error;
  List<Package> _packages = [];
  Package? _selectedPkg;
  String _paymentMethod = _kPaymentMethods.first;

  @override
  void initState() {
    super.initState();
    _loadPackages();
  }

  Future<void> _loadPackages() async {
    try {
      final res = await PackageService().getPackages();
      setState(() {
        _packages = res.data;
        _loadingPkgs = false;
        if (_packages.isNotEmpty) {
          _selectedPkg = _packages.first;
          _amountCtrl.text = _packages.first.numericPrice.toStringAsFixed(2);
        }
      });
    } catch (e) {
      setState(() {
        _loadingPkgs = false;
        _error = 'Could not load packages';
      });
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
              decoration: BoxDecoration(
                color: _kPrimary,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.card_membership_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Assign Package',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context, false),
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white70,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
            // ── Body ──
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: _loadingPkgs
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? Text(_error!, style: const TextStyle(color: _kRed))
                    : Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Package selector
                            _FieldLabel(label: 'Select Package'),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<Package>(
                              value: _selectedPkg,
                              isExpanded: true,
                              decoration: _inputDecor(),
                              items: _packages.map((p) {
                                return DropdownMenuItem(
                                  value: p,
                                  child: Text(
                                    '${p.name}  •  ${p.duration}  •  Rs ${p.numericPrice.toStringAsFixed(0)}',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                );
                              }).toList(),
                              onChanged: (p) {
                                setState(() {
                                  _selectedPkg = p;
                                  if (p != null) {
                                    _amountCtrl.text = p.numericPrice
                                        .toStringAsFixed(2);
                                  }
                                });
                              },
                              validator: (v) =>
                                  v == null ? 'Select a package' : null,
                            ),
                            const SizedBox(height: 16),

                            // Amount
                            _FieldLabel(label: 'Amount Paid (Rs)'),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _amountCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: _inputDecor(hint: 'e.g. 500.00'),
                              validator: (v) {
                                if (v == null || v.isEmpty)
                                  return 'Enter amount';
                                if (double.tryParse(v) == null)
                                  return 'Invalid number';
                                if (double.parse(v) < 0)
                                  return 'Amount must be ≥ 0';
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),

                            // Payment method
                            _FieldLabel(label: 'Payment Method'),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String>(
                              value: _paymentMethod,
                              decoration: _inputDecor(),
                              items: _kPaymentMethods.map((m) {
                                return DropdownMenuItem(
                                  value: m,
                                  child: Text(
                                    m,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                );
                              }).toList(),
                              onChanged: (v) => setState(
                                () => _paymentMethod = v ?? _paymentMethod,
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Note
                            _FieldLabel(label: 'Note (optional)'),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _noteCtrl,
                              maxLength: 120,
                              maxLines: 2,
                              decoration: _inputDecor(
                                hint: 'e.g. Paid via agent, discounted rate…',
                              ),
                            ),

                            if (_submitting) ...[
                              const SizedBox(height: 12),
                              const LinearProgressIndicator(),
                            ],
                          ],
                        ),
                      ),
              ),
            ),
            // ── Footer ──
            if (!_loadingPkgs && _error == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _submitting
                            ? null
                            : () => Navigator.pop(context, false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: _submitting ? null : _submit,
                        icon: _submitting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check_circle_outline, size: 18),
                        label: Text(
                          _submitting ? 'Assigning…' : 'Assign Package',
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: _kPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_selectedPkg == null) return;

    setState(() => _submitting = true);
    try {
      final result = await widget.service.assignPackage(
        userId: widget.userId,
        packageId: _selectedPkg!.id,
        amount: double.parse(_amountCtrl.text.trim()),
        paymentMethod: _paymentMethod,
        note: _noteCtrl.text.trim(),
      );
      if (!mounted) return;
      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Package "${_selectedPkg!.name}" assigned successfully',
            ),
            backgroundColor: _kGreen,
          ),
        );
        Navigator.pop(context, true);
      } else {
        setState(() {
          _submitting = false;
          _error = result['message']?.toString() ?? 'Failed to assign package';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.toString();
      });
    }
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
      color: Color(0xFF374151),
    ),
  );
}

InputDecoration _inputDecor({String? hint}) => InputDecoration(
  hintText: hint,
  hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFFADB5BD)),
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: const BorderSide(color: _kPrimary, width: 1.5),
  ),
  errorBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: const BorderSide(color: _kRed),
  ),
  counterText: '',
  isDense: true,
  filled: true,
  fillColor: Colors.white,
);

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.10),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: color.withOpacity(0.25)),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    ),
  );
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 12, color: const Color(0xFF6B7280)),
      const SizedBox(width: 3),
      Text(
        label,
        style: const TextStyle(fontSize: 11.5, color: Color(0xFF4B5563)),
      ),
    ],
  );
}

class _ErrorBar extends StatelessWidget {
  const _ErrorBar({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Row(
      children: [
        const Icon(Icons.error_outline, color: _kRed, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: _kRed, fontSize: 13),
          ),
        ),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}

// ─── Utilities ────────────────────────────────────────────────────────────────

DateTime? _parseDate(String s) {
  try {
    return DateTime.parse(s);
  } catch (_) {
    return null;
  }
}

String _formatDate(String s) {
  final dt = _parseDate(s);
  if (dt == null) return s;
  return '${dt.year}-${_p(dt.month)}-${_p(dt.day)}';
}

String _p(int v) => v.toString().padLeft(2, '0');
