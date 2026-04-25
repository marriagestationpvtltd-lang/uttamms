import 'dart:typed_data';
import 'package:adminmrz/core/app_theme.dart';
import 'package:adminmrz/payment/paymentmodel.dart';
import 'package:adminmrz/payment/paymentprovider.dart';
import 'package:adminmrz/payment/pdfsevice.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:file_saver/file_saver.dart';
import 'package:url_launcher/url_launcher.dart';

class PaymentsPage extends StatefulWidget {
  const PaymentsPage({Key? key}) : super(key: key);

  @override
  State<PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends State<PaymentsPage> {
  final TextEditingController _searchController = TextEditingController();
  final PDFService _pdfService = PDFService();
  final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');
  bool _isExporting = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PaymentProvider>().fetchPayments();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _showDateRangePicker() async {
    final provider = context.read<PaymentProvider>();
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: provider.startDate != null && provider.endDate != null
          ? DateTimeRange(start: provider.startDate!, end: provider.endDate!)
          : null,
    );
    if (picked != null) {
      provider.setDateRange(picked.start, picked.end);
      provider.fetchFilteredPayments();
    }
  }

  // ─── Stat cards ──────────────────────────────────────────────────────────

  Widget _buildStatCards(PaymentSummary? summary) {
    if (summary == null) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 6),
      child: Row(
        children: [
          _statCard('Total Earnings', summary.totalEarning,
              Icons.account_balance_wallet_outlined, const Color(0xFF6366F1)),
          const SizedBox(width: 10),
          _statCard('Packages Sold', summary.totalPackagesSold.toString(),
              Icons.shopping_bag_outlined, const Color(0xFF8B5CF6)),
          const SizedBox(width: 10),
          _statCard('Active', summary.activePackages.toString(),
              Icons.check_circle_outline, const Color(0xFF10B981)),
          const SizedBox(width: 10),
          _statCard('Expired', summary.expiredPackages.toString(),
              Icons.cancel_outlined, const Color(0xFFEF4444)),
          const SizedBox(width: 10),
          _statCard('Top Method', summary.topPaymentMethod,
              Icons.payment_outlined, const Color(0xFFF59E0B)),
        ],
      ),
    );
  }

  Widget _statCard(
      String label, String value, IconData icon, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = Theme.of(context).colorScheme.surface;
    return Container(
      width: 168,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.18)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.10),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            Positioned(
              top: 0, left: 0, right: 0,
              child: Container(height: 3, decoration: BoxDecoration(
                gradient: LinearGradient(colors: [color, color.withOpacity(0.55)]),
              )),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [color, color.withOpacity(0.75)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(color: color.withOpacity(0.28), blurRadius: 8, offset: const Offset(0, 3)),
                      ],
                    ),
                    child: Icon(icon, size: 19, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          value,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: color,
                            letterSpacing: -0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
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

  // ─── Top section ────────────────────────────────────────────────────────

  Widget _buildTopSection(PaymentProvider provider) {
    final hasFilters = provider.paymentMethodFilter != 'all' ||
        provider.statusFilter != 'all' ||
        provider.startDate != null;
    final cardBg = Theme.of(context).colorScheme.surface;
    return Container(
      color: cardBg,
      child: Column(
        children: [
          // Row 1: Search + action icon buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search by name, email, package…',
                      hintStyle: TextStyle(
                          fontSize: 13, color: Colors.grey.shade400),
                      prefixIcon: Icon(Icons.search_rounded,
                          color: Colors.grey.shade400, size: 18),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            BorderSide(color: Colors.grey.shade200),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            BorderSide(color: Colors.grey.shade200),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                            color: kPrimary, width: 1.5),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 9, horizontal: 12),
                      isDense: true,
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded,
                                  size: 16),
                              onPressed: () {
                                _searchController.clear();
                                provider.setSearchQuery('');
                              },
                            )
                          : null,
                    ),
                    onChanged: provider.setSearchQuery,
                  ),
                ),
                const SizedBox(width: 8),
                _iconBtn(
                  Icons.refresh_rounded,
                  'Refresh',
                  Colors.grey.shade600,
                  Colors.grey.shade100,
                  () => provider.fetchPayments(),
                ),
                const SizedBox(width: 6),
                _iconBtn(
                  Icons.picture_as_pdf_outlined,
                  'Export PDF Report',
                  kRose,
                  kRose.withOpacity(0.08),
                  _isExporting ? null : () => _generateFullReport(provider),
                ),
                const SizedBox(width: 6),
                _iconBtn(
                  Icons.table_chart_outlined,
                  'Export CSV',
                  kEmerald,
                  kEmerald.withOpacity(0.08),
                  _isExporting ? null : () => _exportToCSV(provider),
                ),
                if (_isExporting) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: kPrimary,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Row 2: Stat pills + date chip + status chips + method chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 0, 12, 10),
            child: Row(
              children: [
                _statPill(provider.allPayments.length, 'Total', kPrimary),
                const SizedBox(width: 6),
                _statPill(provider.payments.length, 'Shown', kSky),
                const SizedBox(width: 6),
                _amountPill(provider.filteredTotalAmount, kEmerald),
                const SizedBox(width: 12),
                Container(
                    width: 1, height: 22, color: Colors.grey.shade200),
                const SizedBox(width: 12),
                _dateFilterChip(provider),
                const SizedBox(width: 6),
                Container(
                    width: 1, height: 22, color: Colors.grey.shade300),
                const SizedBox(width: 6),
                ...[
                  ('all', 'All'),
                  ('active', 'Active'),
                  ('expired', 'Expired'),
                  ('pending', 'Pending'),
                ].expand((e) {
                  final (key, label) = e;
                  return [
                    _filterChip(
                      label,
                      provider.statusFilter == key,
                      _statusColor(key),
                      () => provider.setStatusFilter(key),
                    ),
                    const SizedBox(width: 6),
                  ];
                }),
                Container(
                    width: 1, height: 22, color: Colors.grey.shade300),
                const SizedBox(width: 6),
                ...[
                  ('all', 'All Methods'),
                  ...provider.getPaymentMethods().map((m) => (m, m)),
                ].expand((e) {
                  final (key, label) = e;
                  return [
                    _filterChip(
                      label,
                      provider.paymentMethodFilter == key,
                      kViolet,
                      () => provider.setPaymentMethodFilter(key),
                    ),
                    const SizedBox(width: 6),
                  ];
                }),
                if (hasFilters)
                  _filterChip('✕ Clear', true, kRose, () {
                    provider.clearFilters();
                    provider.fetchPayments();
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateFilterChip(PaymentProvider provider) {
    final hasDate = provider.startDate != null;
    final label = hasDate
        ? '📅 ${_dateFormat.format(provider.startDate!)} – ${_dateFormat.format(provider.endDate!)}'
        : '📅 Date Range';
    return GestureDetector(
      onTap: _showDateRangePicker,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: hasDate
              ? kPrimary.withOpacity(0.12)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: hasDate
                ? kPrimary.withOpacity(0.4)
                : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: hasDate ? kPrimary : Colors.grey.shade700,
            fontWeight:
                hasDate ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _statPill(int count, String label, Color color) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$count ',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            TextSpan(
              text: label,
              style: TextStyle(
                fontSize: 11,
                color: color.withOpacity(0.75),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _amountPill(double amount, Color color) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(
        'Rs ${amount.toStringAsFixed(0)}',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _filterChip(
      String label, bool selected, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? color.withOpacity(0.14)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? color.withOpacity(0.45)
                : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? color : Colors.grey.shade700,
            fontWeight:
                selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, String tooltip, Color iconColor,
      Color bgColor, VoidCallback? onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: iconColor.withOpacity(0.25)),
          ),
          child: Icon(icon, size: 18, color: iconColor),
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return kEmerald;
      case 'expired':
        return kRose;
      case 'pending':
        return kAmber;
      default:
        return kSlate500;
    }
  }

  // ─── Payment Card ────────────────────────────────────────────────────────

  Widget _buildPaymentCard(Payment payment) {
    final Color statusColor = payment.statusColor;
    final String initials = payment.displayInitials;
    final cardBg = Theme.of(context).colorScheme.surface;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      elevation: 1,
      shadowColor: Colors.black.withOpacity(0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade100),
      ),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          border: Border(left: BorderSide(color: statusColor, width: 4)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Row 1: Avatar + name/ID/email + status badge + price ────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar with initials
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        statusColor.withOpacity(0.25),
                        statusColor.withOpacity(0.12),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: statusColor.withOpacity(0.3), width: 1.5),
                  ),
                  child: Center(
                    child: Text(
                      initials,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Name + ID + Email
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        payment.fullName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1A2E),
                          letterSpacing: 0.1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            '#${payment.userId}',
                            style: const TextStyle(
                                fontSize: 11,
                                color: kPrimary,
                                fontWeight: FontWeight.w600),
                          ),
                          Text(
                            ' · ${payment.invoiceNumber}',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(Icons.email_outlined,
                              size: 11, color: Colors.grey.shade400),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              payment.email.isNotEmpty
                                  ? payment.email
                                  : '—',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),

                // Status badge + price
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _badge(
                        payment.packageStatus.toUpperCase(), statusColor),
                    const SizedBox(height: 4),
                    Text(
                      payment.packagePrice,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: kEmerald,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 9),
            Divider(height: 1, thickness: 0.8, color: Colors.grey.shade100),
            const SizedBox(height: 7),

            // ── Row 2: Info chips ────────────────────────────────────────────
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                _infoChip(Icons.card_giftcard_outlined,
                    payment.packageName, kPrimary),
                _infoChip(
                    Icons.payment_outlined, payment.paidBy, kViolet),
                _infoChip(Icons.calendar_today_outlined,
                    payment.formattedPurchaseDate, kSky),
                _infoChip(
                  Icons.event_outlined,
                  'Exp: ${payment.formattedExpireDate}',
                  payment.isExpired ? kRose : kAmber,
                ),
              ],
            ),

            const SizedBox(height: 7),
            Divider(height: 1, thickness: 0.8, color: Colors.grey.shade100),
            const SizedBox(height: 7),

            // ── Row 3: Icon-only action buttons ──────────────────────────────
            Row(
              children: [
                _actionIconBtn(
                  Icons.email_outlined,
                  'Send Email',
                  kAmber,
                  () => _sendEmailToCustomer(payment.email, payment),
                ),
                const SizedBox(width: 5),
                _actionIconBtn(
                  Icons.receipt_long_outlined,
                  'Generate Invoice PDF',
                  kEmerald,
                  () => _generateInvoicePDF(payment),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color.withOpacity(0.9),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionIconBtn(
      IconData icon, String tooltip, Color color, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }

  // ─── Empty state ─────────────────────────────────────────────────────────

  Widget _buildEmptyState(PaymentProvider provider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.payments_outlined,
                size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              provider.searchQuery.isNotEmpty
                  ? 'No results for "${provider.searchQuery}"'
                  : 'No payment records found',
              style: TextStyle(fontSize: 15, color: Colors.grey.shade500),
            ),
            if (provider.paymentMethodFilter != 'all' ||
                provider.statusFilter != 'all' ||
                provider.startDate != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: TextButton(
                  onPressed: () {
                    provider.clearFilters();
                    provider.fetchPayments();
                  },
                  child: const Text('Clear Filters'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─── Actions ─────────────────────────────────────────────────────────────

  Future<void> _sendEmailToCustomer(String email, Payment payment) async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: email,
      queryParameters: {
        'subject':
            'Invoice for ${payment.packageName} - Payment #${payment.id}',
        'body':
            'Dear ${payment.fullName},\n\nPlease find attached your invoice for ${payment.packageName} purchased on ${payment.formattedPurchaseDate}.\n\nThank you for your business!\n\nDigital Lami Team',
      },
    );
    if (await canLaunchUrl(emailUri)) {
      await launchUrl(emailUri);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not launch email client'),
          backgroundColor: kRose,
        ),
      );
    }
  }

  Future<void> _generateInvoicePDF(Payment payment) async {
    setState(() => _isExporting = true);
    try {
      final Uint8List pdfBytes =
          await _pdfService.generateInvoicePDF(payment);
      await FileSaver.instance.saveFile(
        name:
            'Invoice-${payment.id}-${payment.fullName.replaceAll(' ', '-')}.pdf',
        bytes: pdfBytes,
        mimeType: MimeType.pdf,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invoice PDF generated successfully'),
            backgroundColor: kEmerald,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating PDF: $e'),
            backgroundColor: kRose,
          ),
        );
      }
    } finally {
      setState(() => _isExporting = false);
    }
  }

  Future<void> _generateFullReport(PaymentProvider provider) async {
    setState(() => _isExporting = true);
    try {
      final Uint8List pdfBytes = await _pdfService.generateReportPDF(
        summary: provider.summary!,
        payments: provider.payments,
        title: 'Payment History Report',
        startDate: provider.startDate,
        endDate: provider.endDate,
      );
      final fileName =
          'Payment-Report-${DateTime.now().millisecondsSinceEpoch}.pdf';
      await FileSaver.instance.saveFile(
        name: fileName,
        bytes: pdfBytes,
        mimeType: MimeType.pdf,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Full report PDF generated successfully'),
            backgroundColor: kEmerald,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating report: $e'),
            backgroundColor: kRose,
          ),
        );
      }
    } finally {
      setState(() => _isExporting = false);
    }
  }

  Future<void> _exportToCSV(PaymentProvider provider) async {
    setState(() => _isExporting = true);
    try {
      final csvContent = _pdfService.generateCSV(provider.payments);
      final csvBytes = Uint8List.fromList(csvContent.codeUnits);
      await FileSaver.instance.saveFile(
        name:
            'Payment-Report-${DateTime.now().millisecondsSinceEpoch}.csv',
        bytes: csvBytes,
        mimeType: MimeType.csv,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('CSV report exported successfully'),
            backgroundColor: kEmerald,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error exporting CSV: $e'),
            backgroundColor: kRose,
          ),
        );
      }
    } finally {
      setState(() => _isExporting = false);
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PaymentProvider>();

    // Plain Column — no Scaffold/AppBar; title shown in dashboard.dart's top bar.
    return Column(
      children: [
        // Top section: search + stat pills + filter chips
        _buildTopSection(provider),

        // Stat cards (horizontally scrollable)
        _buildStatCards(provider.summary),

        Divider(height: 1, thickness: 1, color: Colors.grey.shade200),

        // List header
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
          child: Row(
            children: [
              Text(
                'Payment Records',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: kSlate700,
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(),
              if (provider.payments.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: kEmerald.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kEmerald.withOpacity(0.25)),
                  ),
                  child: Text(
                    'Total: Rs ${provider.filteredTotalAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: kEmerald,
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Scrollable payment list
        Expanded(
          child: provider.isLoading
              ? const Center(child: CircularProgressIndicator())
              : provider.error.isNotEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline,
                              size: 48, color: kRose),
                          const SizedBox(height: 12),
                          Text(
                            'Failed to load payments',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: () => provider.fetchPayments(),
                            icon: const Icon(Icons.refresh_rounded,
                                size: 16),
                            label: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () => provider.fetchPayments(),
                      child: provider.payments.isEmpty
                          ? SingleChildScrollView(
                              physics:
                                  const AlwaysScrollableScrollPhysics(),
                              child: _buildEmptyState(provider),
                            )
                          : ListView.builder(
                              controller: _scrollController,
                              physics:
                                  const AlwaysScrollableScrollPhysics(),
                              padding:
                                  const EdgeInsets.only(bottom: 24),
                              itemCount: provider.payments.length,
                              itemBuilder: (ctx, i) =>
                                  _buildPaymentCard(
                                      provider.payments[i]),
                            ),
                    ),
        ),
      ],
    );
  }
}