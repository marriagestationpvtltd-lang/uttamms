import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../adminchat/chatprovider.dart';
import '../auth/service.dart';
import '../document/docprovider/docservice.dart';
import 'dashmodel.dart';
import 'dashservice.dart';

// ─── Design tokens ────────────────────────────────────────────────────────────
const _kPrimary  = Color(0xFF6366F1);
const _kEmerald  = Color(0xFF10B981);
const _kSky      = Color(0xFF0EA5E9);
const _kViolet   = Color(0xFF8B5CF6);
const _kAmber    = Color(0xFFF59E0B);
const _kRose     = Color(0xFFEF4444);
const _kPink     = Color(0xFFEC4899);
const _kSlate700 = Color(0xFF334155);
const _kSlate500 = Color(0xFF64748B);

const _kUnknownLabel = 'Unknown';
final _kBannerDateFmt = DateFormat('EEEE, MMMM d, yyyy');

class DashboardHome extends StatefulWidget {
  /// Called when a card or section link is tapped with the target tab index.
  final void Function(int tabIndex)? onNavigate;

  const DashboardHome({super.key, this.onNavigate});

  @override
  State<DashboardHome> createState() => _DashboardHomeState();
}

class _DashboardHomeState extends State<DashboardHome> {
  DashboardData? _dashboardData;
  bool _isLoading = true;
  String _error = '';
  final DashboardService _dashboardService = DashboardService();
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _fetchDashboardData();
    // Auto-refresh every 60 s so counts stay fresh
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) { if (mounted) _fetchDashboardData(); },
    );
    // Ensure ChatProvider has data for the live online count
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final chatProvider = context.read<ChatProvider>();
      if (chatProvider.chatList.isEmpty) chatProvider.fetchChatList();
      // Ensure DocumentsProvider has data for the pending docs count
      final docsProvider = context.read<DocumentsProvider>();
      if (!docsProvider.isInitialized) docsProvider.fetchDocuments();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchDashboardData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = '';
    });
    try {
      final response = await _dashboardService.getDashboardData();
      if (!mounted) return;
      if (response.success) {
        setState(() => _dashboardData = response.dashboard);
      } else {
        setState(() => _error = 'Failed to load dashboard data');
      }
    } on UnauthorizedException {
      if (!mounted) return;
      // Token is invalid/expired — log out and return to login screen.
      await context.read<AuthProvider>().logout();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Unable to load dashboard data. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── Live dot ───────────────────────────────────────────────────────────────
  Widget _buildLiveDot() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: _kEmerald,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        const Text(
          'LIVE',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: _kEmerald,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  // ─── KPI card ───────────────────────────────────────────────────────────────
  Widget _buildKpiCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    String? subtitle,
    VoidCallback? onTap,
    bool isLive = false,
  }) {
    final cardBg = Theme.of(context).colorScheme.surface;
    final content = Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border(top: BorderSide(color: color, width: 3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const Spacer(),
              if (isLive) _buildLiveDot(),
              if (!isLive && onTap != null)
                Icon(
                  Icons.open_in_new_rounded,
                  size: 13,
                  color: color.withOpacity(0.45),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: _kSlate700,
              height: 1,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _kSlate500,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: _kSlate500.withOpacity(0.65),
              ),
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return content;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: content,
      ),
    );
  }

  // ─── Section header ─────────────────────────────────────────────────────────
  Widget _buildSectionHeader(String title, {VoidCallback? onRefresh, VoidCallback? onViewAll}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _kSlate700,
              letterSpacing: -0.2,
            ),
          ),
          const Spacer(),
          if (onViewAll != null)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: onViewAll,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _kPrimary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Text(
                        'View All',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _kPrimary,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Icon(Icons.arrow_forward_rounded, size: 11, color: _kPrimary),
                    ],
                  ),
                ),
              ),
            ),
          if (onViewAll != null && onRefresh != null) const SizedBox(width: 6),
          if (onRefresh != null)
            GestureDetector(
              onTap: onRefresh,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _kPrimary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(Icons.refresh_rounded, size: 13, color: _kPrimary),
                    const SizedBox(width: 4),
                    Text(
                      'Refresh',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _kPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── User KPI row ────────────────────────────────────────────────────────────
  Widget _buildUserStatsRow() {
    final u = _dashboardData?.users;
    if (u == null) return const SizedBox.shrink();

    final chatList = context.watch<ChatProvider>().chatList;
    final liveOnline = chatList.isNotEmpty
        ? chatList.where((user) => user['online'] == 'true').length
        : u.online;
    final pendingDocsCount =
        context.watch<DocumentsProvider>().pendingDocuments.length;

    final pendingDocsCard = _buildKpiCard(
      label: 'Pending Docs',
      value: '$pendingDocsCount',
      icon: Icons.pending_actions_rounded,
      color: _kAmber,
      onTap: () => widget.onNavigate?.call(2),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 500;
        if (isMobile) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: _buildKpiCard(label: 'Total Members', value: '${u.total}', icon: Icons.people_alt_rounded, color: _kPrimary, onTap: () => widget.onNavigate?.call(1))),
                  const SizedBox(width: 12),
                  Expanded(child: _buildKpiCard(label: 'Active Users', value: '${u.active}', icon: Icons.check_circle_rounded, color: _kEmerald, onTap: () => widget.onNavigate?.call(1))),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _buildKpiCard(label: 'Online Now', value: '$liveOnline', icon: Icons.wifi_rounded, color: _kSky, isLive: true, onTap: () => widget.onNavigate?.call(5))),
                  const SizedBox(width: 12),
                  Expanded(child: _buildKpiCard(label: 'Verified', value: '${u.verified}', icon: Icons.verified_rounded, color: _kViolet, onTap: () => widget.onNavigate?.call(1))),
                  const SizedBox(width: 12),
                  Expanded(child: pendingDocsCard),
                ],
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: _buildKpiCard(label: 'Total Members', value: '${u.total}', icon: Icons.people_alt_rounded, color: _kPrimary, onTap: () => widget.onNavigate?.call(1))),
            const SizedBox(width: 14),
            Expanded(child: _buildKpiCard(label: 'Active Users', value: '${u.active}', icon: Icons.check_circle_rounded, color: _kEmerald, onTap: () => widget.onNavigate?.call(1))),
            const SizedBox(width: 14),
            Expanded(child: _buildKpiCard(label: 'Online Now', value: '$liveOnline', icon: Icons.wifi_rounded, color: _kSky, isLive: true, onTap: () => widget.onNavigate?.call(5))),
            const SizedBox(width: 14),
            Expanded(child: _buildKpiCard(label: 'Verified', value: '${u.verified}', icon: Icons.verified_rounded, color: _kViolet, onTap: () => widget.onNavigate?.call(1))),
            const SizedBox(width: 14),
            Expanded(child: pendingDocsCard),
          ],
        );
      },
    );
  }

  // ─── Revenue KPI row ─────────────────────────────────────────────────────────
  Widget _buildRevenueStatsRow() {
    final p = _dashboardData?.payments;
    if (p == null) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 500;
        if (isMobile) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: _buildKpiCard(label: 'Total Revenue', value: p.totalEarning, icon: Icons.account_balance_wallet_rounded, color: _kEmerald, onTap: () => widget.onNavigate?.call(4))),
                  const SizedBox(width: 12),
                  Expanded(child: _buildKpiCard(label: "Today's Revenue", value: p.todayEarning, icon: Icons.today_rounded, color: _kAmber, subtitle: 'earned today', onTap: () => widget.onNavigate?.call(4))),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _buildKpiCard(label: 'Monthly Revenue', value: p.thisMonthEarning, icon: Icons.calendar_month_rounded, color: _kSky, subtitle: 'this month', onTap: () => widget.onNavigate?.call(4))),
                  const SizedBox(width: 12),
                  Expanded(child: _buildKpiCard(label: 'Total Sales', value: '${p.totalSold}', icon: Icons.shopping_bag_rounded, color: _kRose, onTap: () => widget.onNavigate?.call(4))),
                ],
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: _buildKpiCard(label: 'Total Revenue', value: p.totalEarning, icon: Icons.account_balance_wallet_rounded, color: _kEmerald, onTap: () => widget.onNavigate?.call(4))),
            const SizedBox(width: 14),
            Expanded(child: _buildKpiCard(label: "Today's Revenue", value: p.todayEarning, icon: Icons.today_rounded, color: _kAmber, subtitle: 'earned today', onTap: () => widget.onNavigate?.call(4))),
            const SizedBox(width: 14),
            Expanded(child: _buildKpiCard(label: 'Monthly Revenue', value: p.thisMonthEarning, icon: Icons.calendar_month_rounded, color: _kSky, subtitle: 'this month', onTap: () => widget.onNavigate?.call(4))),
            const SizedBox(width: 14),
            Expanded(child: _buildKpiCard(label: 'Total Sales', value: '${p.totalSold}', icon: Icons.shopping_bag_rounded, color: _kRose, onTap: () => widget.onNavigate?.call(4))),
          ],
        );
      },
    );
  }

  // ─── Best-selling package card ───────────────────────────────────────────────
  Widget _buildBestPackageCard() {
    final pkg = _dashboardData?.payments.bestSellingPackage;
    if (pkg == null) return const SizedBox.shrink();
    final card = Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: _kPrimary.withOpacity(0.28),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.star_rounded, color: Colors.white, size: 18),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  '🏆  Top Seller',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'Best Selling Package',
            style: TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Text(
            pkg.name,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            '${pkg.total} sales',
            style: const TextStyle(fontSize: 13, color: Colors.white70),
          ),
        ],
      ),
    );
    if (widget.onNavigate == null) return card;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: () => widget.onNavigate?.call(3),
        borderRadius: BorderRadius.circular(12),
        child: card,
      ),
    );
  }

  // ─── Payment methods card ────────────────────────────────────────────────────
  Widget _buildPaymentMethodsCard() {
    final p = _dashboardData?.payments;
    if (p == null || p.byMethod.isEmpty) return const SizedBox.shrink();

    final palette = [_kPrimary, _kEmerald, _kAmber, _kSky, _kViolet, _kRose];
    return _buildCard(
      onTap: () => widget.onNavigate?.call(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle('Payment Methods', Icons.credit_card_rounded, _kPrimary),
          const SizedBox(height: 16),
          ...p.byMethod.asMap().entries.map((e) {
            final color = palette[e.key % palette.length];
            final pct   = p.totalSold > 0 ? e.value.total / p.totalSold : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 7),
                          Text(
                            e.value.paidby,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _kSlate700),
                          ),
                        ],
                      ),
                      Text(
                        '${e.value.total}  (${(pct * 100).toStringAsFixed(0)}%)',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct,
                      backgroundColor: color.withOpacity(0.10),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                      minHeight: 5,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  // ─── User-distribution row ───────────────────────────────────────────────────
  Widget _buildUserDistributionRow({bool isMobile = false}) {
    final u = _dashboardData?.users;
    if (u == null) return const SizedBox.shrink();
    final total = u.total;
    final userTypesCard = _buildCard(
      onTap: () => widget.onNavigate?.call(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle('User Types', Icons.category_rounded, _kPrimary),
          const SizedBox(height: 14),
          ...u.byType.map(
            (t) => _buildDistributionRow(
              t.usertype.isEmpty ? _kUnknownLabel : t.usertype,
              t.total,
              total,
              _kPrimary,
            ),
          ),
        ],
      ),
    );
    final genderCard = _buildCard(
      onTap: () => widget.onNavigate?.call(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle('Gender', Icons.people_rounded, _kPink),
          const SizedBox(height: 14),
          ...u.byGender.map(
            (g) => _buildDistributionRow(
              g.gender.isEmpty ? _kUnknownLabel : g.gender,
              g.total,
              total,
              _kPink,
            ),
          ),
        ],
      ),
    );
    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          userTypesCard,
          const SizedBox(height: 14),
          genderCard,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: userTypesCard),
        const SizedBox(width: 14),
        Expanded(child: genderCard),
      ],
    );
  }

  Widget _buildDistributionRow(String label, int count, int total, Color color) {
    final pct = total > 0 ? count / total : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: _kSlate500)),
              Text(
                '$count',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: pct,
              backgroundColor: color.withOpacity(0.08),
              valueColor: AlwaysStoppedAnimation<Color>(color.withOpacity(0.65)),
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Geographic card ─────────────────────────────────────────────────────────
  Widget _buildGeographicCard() {
    final addr = _dashboardData?.permanentAddress;
    if (addr == null) return const SizedBox.shrink();
    return _buildCard(
      onTap: () => widget.onNavigate?.call(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _cardTitle('Geographic Data', Icons.public_rounded, _kViolet),
              const Spacer(),
              _miniStat('With Address', '${addr.totalWithAddress}', _kViolet),
              const SizedBox(width: 20),
              _miniStat('Res. Types', '${addr.byResidentialStatus.length}', _kSky),
            ],
          ),
          if (addr.byCountry.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'Top Countries',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _kSlate500),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: addr.byCountry.map((c) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _kPrimary.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _kPrimary.withOpacity(0.14)),
                  ),
                  child: Text(
                    '${c.country}  ${c.total}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _kPrimary,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Welcome banner ──────────────────────────────────────────────────────────
  Widget _buildWelcomeBanner() {
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good Morning' : hour < 17 ? 'Good Afternoon' : 'Good Evening';
    final dateStr  = _kBannerDateFmt.format(DateTime.now());
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4F46E5), Color(0xFF6366F1)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withOpacity(0.30),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$greeting! 👋',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Marriage Station Admin Dashboard',
                  style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.80)),
                ),
                const SizedBox(height: 3),
                Text(
                  dateStr,
                  style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.60)),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.admin_panel_settings_rounded,
            size: 56,
            color: Colors.white10,
          ),
        ],
      ),
    );
  }

  // ─── Shared helpers ──────────────────────────────────────────────────────────
  Widget _buildCard({required Widget child, VoidCallback? onTap}) {
    final cardBg = Theme.of(context).colorScheme.surface;
    final content = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
    if (onTap == null) return content;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: content,
      ),
    );
  }

  Widget _cardTitle(String title, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon, color: color, size: 15),
        ),
        const SizedBox(width: 9),
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: _kSlate700,
          ),
        ),
      ],
    );
  }

  Widget _miniStat(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color),
        ),
        Text(label, style: const TextStyle(fontSize: 10, color: _kSlate500)),
      ],
    );
  }

  // ─── Loading / error states ──────────────────────────────────────────────────
  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              color: _kPrimary,
              strokeWidth: 2.5,
            ),
          ),
          SizedBox(height: 14),
          Text(
            'Loading dashboard...',
            style: TextStyle(fontSize: 13, color: _kSlate500),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(
              color: Color(0xFFFEF2F2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.error_outline_rounded, size: 36, color: _kRose),
          ),
          const SizedBox(height: 14),
          Text(
            _error,
            style: const TextStyle(fontSize: 13, color: _kSlate500),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: _fetchDashboardData,
            icon: const Icon(Icons.refresh_rounded, size: 15),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Breakdown charts row ────────────────────────────────────────────────────
  Widget _buildBreakdownChartsRow({bool isMobile = false}) {
    final u = _dashboardData?.users;
    final p = _dashboardData?.payments;
    final palette = [_kPrimary, _kEmerald, _kAmber, _kSky, _kViolet, _kRose];

    Widget buildHorizontalBars({
      required List<String> labels,
      required List<int> values,
    }) {
      if (labels.isEmpty) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No data', style: TextStyle(fontSize: 12, color: _kSlate500)),
          ),
        );
      }
      final maxVal = values.fold(0, (a, b) => a > b ? a : b);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(labels.length, (i) {
          final color = palette[i % palette.length];
          final frac = maxVal > 0 ? values[i] / maxVal : 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 90,
                  child: Text(
                    labels[i].isEmpty ? _kUnknownLabel : labels[i],
                    style: const TextStyle(fontSize: 11, color: _kSlate500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: frac,
                      backgroundColor: color.withOpacity(0.10),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                      minHeight: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${values[i]}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
          );
        }),
      );
    }

    Widget skeletonCard() {
      final skeletonRows = Column(
        children: List.generate(
          3,
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Container(
                  width: 70,
                  height: 11,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 24,
                  height: 11,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return _buildCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 120,
              height: 16,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 16),
            skeletonRows,
          ],
        ),
      );
    }

    if (u == null || p == null) {
      if (isMobile) {
        return Column(
          children: [skeletonCard(), const SizedBox(height: 14), skeletonCard()],
        );
      }
      return Row(
        children: [
          Expanded(child: skeletonCard()),
          const SizedBox(width: 14),
          Expanded(child: skeletonCard()),
        ],
      );
    }

    final userTypeCard = _buildCard(
      onTap: () => widget.onNavigate?.call(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle('User Type Breakdown', Icons.bar_chart_rounded, _kPrimary),
          const SizedBox(height: 16),
          buildHorizontalBars(
            labels: u.byType.map((t) => t.usertype).toList(),
            values: u.byType.map((t) => t.total).toList(),
          ),
        ],
      ),
    );

    final paymentMethodCard = _buildCard(
      onTap: () => widget.onNavigate?.call(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle('Payment Methods', Icons.payments_rounded, _kEmerald),
          const SizedBox(height: 16),
          buildHorizontalBars(
            labels: p.byMethod.map((m) => m.paidby).toList(),
            values: p.byMethod.map((m) => m.total).toList(),
          ),
        ],
      ),
    );

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [userTypeCard, const SizedBox(height: 14), paymentMethodCard],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: userTypeCard),
        const SizedBox(width: 14),
        Expanded(child: paymentMethodCard),
      ],
    );
  }

  // ─── Pending docs banner ─────────────────────────────────────────────────────
  Widget _buildPendingDocsBanner() {
    final pendingCount =
        context.watch<DocumentsProvider>().pendingDocuments.length;
    if (pendingCount == 0) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: _kAmber.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kAmber.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: _kAmber.withOpacity(0.20),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.pending_actions_rounded,
              color: _kAmber,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 13, color: _kSlate700),
                children: [
                  const TextSpan(text: '⚠️  '),
                  TextSpan(
                    text: '$pendingCount',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text: ' document${pendingCount == 1 ? '' : 's'} waiting for review',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => widget.onNavigate?.call(2),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: _kAmber,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Review Now',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Main content ────────────────────────────────────────────────────────────
  Widget _buildDashboardContent() {
    return SingleChildScrollView(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 600;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Welcome banner
              _buildWelcomeBanner(),
              const SizedBox(height: 16),

              // Pending documents alert banner (only when count > 0)
              _buildPendingDocsBanner(),
              const SizedBox(height: 16),

              // User KPIs
              _buildSectionHeader(
                'User Statistics',
                onRefresh: _fetchDashboardData,
                onViewAll: () => widget.onNavigate?.call(1),
              ),
              _buildUserStatsRow(),
              const SizedBox(height: 22),

              // Revenue KPIs
              _buildSectionHeader(
                'Revenue Overview',
                onViewAll: () => widget.onNavigate?.call(4),
              ),
              _buildRevenueStatsRow(),
              const SizedBox(height: 22),

              // Breakdown charts: user types + payment methods
              _buildSectionHeader('Breakdown'),
              _buildBreakdownChartsRow(isMobile: isMobile),
              const SizedBox(height: 22),

              // Best package + Payment methods
              if (isMobile) ...[
                _buildSectionHeader(
                  'Package Performance',
                  onViewAll: () => widget.onNavigate?.call(3),
                ),
                _buildBestPackageCard(),
                const SizedBox(height: 22),
                _buildSectionHeader(
                  'Payment Methods',
                  onViewAll: () => widget.onNavigate?.call(4),
                ),
                _buildPaymentMethodsCard(),
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionHeader(
                            'Package Performance',
                            onViewAll: () => widget.onNavigate?.call(3),
                          ),
                          _buildBestPackageCard(),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionHeader(
                            'Payment Methods',
                            onViewAll: () => widget.onNavigate?.call(4),
                          ),
                          _buildPaymentMethodsCard(),
                        ],
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 22),

              // User analytics (types + gender)
              _buildSectionHeader(
                'User Analytics',
                onViewAll: () => widget.onNavigate?.call(1),
              ),
              _buildUserDistributionRow(isMobile: isMobile),
              const SizedBox(height: 22),

              // Geographic
              _buildSectionHeader(
                'Geographic Data',
                onViewAll: () => widget.onNavigate?.call(1),
              ),
              _buildGeographicCard(),
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return _buildLoadingState();
    if (_error.isNotEmpty) return _buildErrorState();
    return _buildDashboardContent();
  }
}