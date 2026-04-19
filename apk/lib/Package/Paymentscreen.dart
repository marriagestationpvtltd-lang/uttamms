import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:webview_flutter/webview_flutter.dart';

import '../Home/Screen/HomeScreenPage.dart';
import '../Startup/MainControllere.dart';
import '../constant/design_system.dart';
import 'package:ms2026/config/app_endpoints.dart';

class PaymentPage extends StatefulWidget {
  final double amount;
  final double discount;
  final String packageName;
  final int packageId;
  final String packageDuration;

  const PaymentPage({
    super.key,
    required this.amount,
    required this.discount,
    required this.packageName,
    required this.packageId,
    required this.packageDuration,
  });

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  final ScrollController _scrollController = ScrollController();

  // VAT settings fetched from admin
  bool _vatEnabled = false;
  double _vatRate = 0.0;

  @override
  void initState() {
    super.initState();
    _fetchVatSettings();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchVatSettings() async {
    try {
      final response = await http.get(
        Uri.parse('${kApiBaseUrl}/Api2/app_settings.php'),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final settings = data['data'];
          final enabled = settings['vat_enabled'];
          final rate = settings['vat_rate'];
          if (mounted) {
            setState(() {
              _vatEnabled = enabled == '1' || enabled == 1 || enabled == true;
              final parsedRate = double.tryParse(rate?.toString() ?? '0') ?? 0.0;
              // Accept both percentage (e.g. 13) and decimal (e.g. 0.13)
              _vatRate = parsedRate > 1 ? parsedRate / 100 : parsedRate;
            });
          }
        }
      }
    } catch (_) {}
  }

  String _getPaidBy() {
    switch (_selectedMethod) {
      case PaymentMethod.khalti:
        return "khalti";
      case PaymentMethod.card:
        return "hbl";
      case PaymentMethod.esewa:
        return "esewa";
      case PaymentMethod.connectIps:
        return "connectips";
    }
  }

  PaymentMethod _selectedMethod = PaymentMethod.khalti;
  bool _isProcessing = false;
  bool _isActivating = false;
  bool _isCancelled = false;
  String _paymentStatus = '';
  bool _showWebView = false;
  String? _paymentUrl;
  late WebViewController _webViewController;
  bool _isWebViewLoading = true;

  double get processingCharge => widget.amount;
  double get discount => widget.discount;
  double get subtotal => processingCharge - discount;
  double get taxAmount => _vatEnabled ? subtotal * _vatRate : 0.0;
  double get totalAmount => subtotal + taxAmount;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppColors.primary,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.white,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemStatusBarContrastEnforced: false,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.white),
          onPressed: () {
            if (_showWebView) {
              _handlePaymentCancel();
            } else if (!_isProcessing) {
              Navigator.of(context).pop();
            }
          },
        ),
        title: Text(
          _showWebView ? 'Payment Processing' : 'Secure Payment',
          style: AppTextStyles.whiteLabel.copyWith(fontSize: 18),
        ),
        centerTitle: true,
        actions: [
          if (!_showWebView)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Icon(
                Icons.shield_rounded,
                color: AppColors.premium,
                size: 24,
              ),
            ),
        ],
      ),
      body: _showWebView ? _buildWebView() : _buildPaymentForm(),
    );
  }

  Widget _buildPaymentForm() {
    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Payment Status
          if (_paymentStatus.isNotEmpty)
            _buildPaymentStatus(),

          // Payment Methods
          _buildPaymentMethods(),
          const SizedBox(height: 30),

          // Payment Summary
          _buildPaymentSummary(),
          const SizedBox(height: 40),

          // Pay Now Button
          _buildPayNowButton(),
          const SizedBox(height: 20),

          // Security Info
          _buildSecurityInfo(),
        ],
      ),
    );
  }

  Widget _buildWebView() {
    return Stack(
      children: [
        WebViewWidget(
          controller: _webViewController,
        ),
        if (_isWebViewLoading)
          Container(
            color: AppColors.white,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Loading Payment Gateway...',
                    style: AppTextStyles.labelMedium.copyWith(
                      fontSize: 16,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please wait',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPaymentStatus() {
    Color statusColor = AppColors.warning;
    IconData statusIcon = Icons.info_outline_rounded;

    if (_paymentStatus.contains('Success')) {
      statusColor = AppColors.success;
      statusIcon = Icons.check_circle_rounded;
    } else if (_paymentStatus.contains('Error')) {
      statusColor = AppColors.error;
      statusIcon = Icons.error_outline_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withOpacity(0.3), width: 1.5),
      ),
      child: Row(
        children: [
          Icon(statusIcon, color: statusColor, size: 26),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              _paymentStatus,
              style: AppTextStyles.labelMedium.copyWith(
                color: statusColor,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethods() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowLight,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.payment_rounded, color: AppColors.primary, size: 22),
              const SizedBox(width: 10),
              Text(
                'Select Payment Method',
                style: AppTextStyles.heading4.copyWith(fontSize: 17),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Connect IPS QR Scan
          PaymentMethodTile(
            title: 'Connect IPS QR Scan',
            subtitle: 'Scan QR with mobile banking app',
            icon: Icons.qr_code_scanner_rounded,
            iconColor: const Color(0xFF5C2D91),
            backgroundColor: const Color(0xFFF3E5F5),
            isSelected: _selectedMethod == PaymentMethod.connectIps,
            isEnabled: !_isProcessing,
            onTap: () => _selectMethod(PaymentMethod.connectIps),
          ),
          const SizedBox(height: 12),

          // Khalti
          PaymentMethodTile(
            title: 'Khalti',
            subtitle: 'Pay with Khalti digital wallet',
            icon: Icons.account_balance_wallet_rounded,
            iconColor: const Color(0xFF5C2D91),
            backgroundColor: const Color(0xFFEDE7F6),
            isSelected: _selectedMethod == PaymentMethod.khalti,
            isEnabled: !_isProcessing,
            onTap: () => _selectMethod(PaymentMethod.khalti),
            isRecommended: true,
          ),
          const SizedBox(height: 12),

          // Pay with Card (HBL)
          PaymentMethodTile(
            title: 'Debit/Credit Card',
            subtitle: 'Visa, Mastercard, etc.',
            icon: Icons.credit_card_rounded,
            iconColor: const Color(0xFF1565C0),
            backgroundColor: const Color(0xFFE3F2FD),
            isSelected: _selectedMethod == PaymentMethod.card,
            isEnabled: !_isProcessing,
            onTap: () => _selectMethod(PaymentMethod.card),
          ),
          const SizedBox(height: 12),

          // Pay with Esewa
          PaymentMethodTile(
            title: 'eSewa',
            subtitle: 'Pay with eSewa digital wallet',
            icon: Icons.payment_rounded,
            iconColor: const Color(0xFF2E7D32),
            backgroundColor: const Color(0xFFE8F5E9),
            isSelected: _selectedMethod == PaymentMethod.esewa,
            isEnabled: !_isProcessing,
            onTap: () => _selectMethod(PaymentMethod.esewa),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentSummary() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowLight,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long_rounded, color: AppColors.primary, size: 22),
              const SizedBox(width: 10),
              Text(
                'Bill Summary',
                style: AppTextStyles.heading4.copyWith(fontSize: 17),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Package Info Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.workspace_premium_rounded,
                    color: AppColors.premium,
                    size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.packageName,
                        style: AppTextStyles.whiteLabel.copyWith(fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.packageDuration,
                        style: AppTextStyles.whiteBody.copyWith(
                          fontSize: 13,
                          color: AppColors.white.withOpacity(0.85),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Price Breakdown
          Text(
            'Price Details',
            style: AppTextStyles.labelMedium.copyWith(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),

          _buildPriceRow('Package Price', 'Rs. ${processingCharge.toStringAsFixed(0)}'),
          const SizedBox(height: 10),

          if (discount > 0)
            _buildPriceRow('Discount', '- Rs. ${discount.toStringAsFixed(0)}',
                isDiscount: true),
          if (discount > 0)
            const SizedBox(height: 10),

          Divider(height: 1, color: AppColors.border, thickness: 1),
          const SizedBox(height: 10),

          _buildPriceRow('Subtotal', 'Rs. ${subtotal.toStringAsFixed(0)}',
              isBold: true),
          const SizedBox(height: 10),

          if (_vatEnabled) ...[
            _buildPriceRow(
              'VAT (${(_vatRate * 100).toStringAsFixed(0)}%)',
              'Rs. ${taxAmount.toStringAsFixed(0)}',
              showInfo: true,
            ),
            const SizedBox(height: 16),
          ] else
            const SizedBox(height: 6),

          // Total Amount Card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: AppColors.secondaryGradient,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppColors.secondary.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total Amount',
                      style: AppTextStyles.whiteBody.copyWith(
                        fontSize: 14,
                        color: AppColors.white.withOpacity(0.9),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _vatEnabled ? 'Including all taxes' : 'No tax applied',
                      style: AppTextStyles.whiteBody.copyWith(
                        fontSize: 11,
                        color: AppColors.white.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
                Text(
                  'Rs. ${totalAmount.toStringAsFixed(0)}',
                  style: AppTextStyles.whiteHeading.copyWith(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceRow(String label, String value,
      {bool isDiscount = false, bool isBold = false, bool showInfo = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Text(
              label,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
                fontWeight: isBold ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            if (showInfo)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: AppColors.textHint,
                ),
              ),
          ],
        ),
        Text(
          value,
          style: AppTextStyles.bodyMedium.copyWith(
            color: isDiscount ? AppColors.success : AppColors.textPrimary,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildPayNowButton() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: _isProcessing ? null : AppColors.primaryGradient,
        boxShadow: _isProcessing ? [] : [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.4),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 58,
        child: ElevatedButton(
          onPressed: _isProcessing ? null : _processPayment,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 0,
            disabledBackgroundColor: AppColors.border,
          ),
          child: _isProcessing
              ? Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.white),
                ),
              ),
              const SizedBox(width: 14),
              Text(
                'Processing Payment...',
                style: AppTextStyles.whiteLabel.copyWith(fontSize: 16),
              ),
            ],
          )
              : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_rounded, color: AppColors.white, size: 20),
              const SizedBox(width: 10),
              Text(
                'Pay Rs. ${totalAmount.toStringAsFixed(0)}',
                style: AppTextStyles.whiteLabel.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSecurityInfo() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.success.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.success.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.verified_user_rounded,
                color: AppColors.success,
                size: 20),
              const SizedBox(width: 10),
              Text(
                '100% Secure Payment',
                style: AppTextStyles.labelMedium.copyWith(
                  color: AppColors.success,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Your payment is protected with 256-bit SSL encryption',
            style: AppTextStyles.bodySmall.copyWith(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildSecureIcon(Icons.shield_rounded),
              const SizedBox(width: 14),
              _buildSecureIcon(Icons.lock_rounded),
              const SizedBox(width: 14),
              _buildSecureIcon(Icons.verified_rounded),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSecureIcon(IconData icon) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.success.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 20, color: AppColors.success),
    );
  }

  void _selectMethod(PaymentMethod method) {
    if (!_isProcessing) {
      setState(() {
        _selectedMethod = method;
      });
      // Scroll to the Pay Now button so user can immediately proceed
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
          );
        }
      });
    }
  }

  Future<void> _processPayment() async {
    setState(() {
      _isProcessing = true;
      _isCancelled = false;
      _isActivating = false;
      _paymentStatus = 'Initiating payment...';
    });

    try {
      if (_selectedMethod == PaymentMethod.khalti) {
        await _processKhaltiPayment();
      } else if (_selectedMethod == PaymentMethod.card) {
        await _processHBLPayment();
      } else if (_selectedMethod == PaymentMethod.esewa) {
        _showComingSoonDialog('Esewa');
      } else if (_selectedMethod == PaymentMethod.connectIps) {
        _showComingSoonDialog('Connect IPS');
      } else {
        throw Exception('Unknown payment method');
      }
    } catch (e) {
      print('Payment error: $e');
      setState(() {
        _paymentStatus = 'Error: ${e.toString()}';
      });

      _showErrorDialog('Failed to process payment: ${e.toString()}');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _processKhaltiPayment() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('user_data');
    final userData = jsonDecode(userDataString!);
    final userId = int.tryParse(userData["id"].toString());

    setState(() {
      _paymentStatus = 'Initiating Khalti payment...';
    });

    // Prepare payload
    final payload = {
      "amount": totalAmount.toInt(),
      "userid": userId,
      "packageid": widget.packageId,
      "paidby": "Khalti"
    };

    print('Sending Khalti payment request: $payload');

    // Call Khalti API
    final response = await http.post(
      Uri.parse('https://pay.digitallami.com/khalti_payment.php'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: json.encode(payload),
    );

    print('Khalti Response status: ${response.statusCode}');
    print('Khalti Response body: ${response.body}');

    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      if (data['success'] == true && data['payment_url'] != null) {
        final paymentUrl = data['payment_url'];
        setState(() {
          _paymentStatus = 'Opening Khalti payment page...';
        });

        // Open payment URL in WebView
        _openPaymentInWebView(paymentUrl, 'Khalti');
      } else {
        throw Exception(data['message'] ?? 'Failed to initiate Khalti payment');
      }
    } else {
      throw Exception('Khalti server error: ${response.statusCode}');
    }
  }

  Future<void> _processHBLPayment() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('user_data');
    final userData = jsonDecode(userDataString!);
    final userId = int.tryParse(userData["id"].toString());

    setState(() {
      _paymentStatus = 'Initiating HBL card payment...';
    });

    // Create HBL payment URL with query parameters
    final paymentUrl = Uri.parse('http://pay.digitallami.com/hbl/index.php')
        .replace(queryParameters: {
      'input_amount': totalAmount.toStringAsFixed(0),
      'userid': userId.toString(),
      'packageid': widget.packageId.toString(),
      'paidby': 'hbl'
    }).toString();

    print('HBL Payment URL: $paymentUrl');

    setState(() {
      _paymentStatus = 'Opening HBL payment page...';
    });

    // Open HBL payment URL in WebView
    _openPaymentInWebView(paymentUrl, 'HBL Card');
  }

  void _openPaymentInWebView(String paymentUrl, String gatewayName) {
    // Clean the URL (remove backslashes if any)
    final cleanUrl = paymentUrl.replaceAll(r'\', '');

    setState(() {
      _showWebView = true;
      _paymentUrl = cleanUrl;
      _isWebViewLoading = true;
    });

    // Initialize WebViewController
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            print('WebView loading: $progress%');
            if (progress == 100) {
              setState(() {
                _isWebViewLoading = false;
              });
            }
          },
          onPageStarted: (String url) {
            print('Page started loading: $url');
            setState(() {
              _isWebViewLoading = true;
            });
          },
          onPageFinished: (String url) {
            print('Page finished loading: $url');
            setState(() {
              _isWebViewLoading = false;
            });
            _handleUrlChange(url);
          },
          onWebResourceError: (WebResourceError error) {
            print('WebView error: ${error.description}');
            setState(() {
              _isWebViewLoading = false;
            });
          },
          onNavigationRequest: (NavigationRequest request) {
            print('Navigation request to: ${request.url}');
            _handleUrlChange(request.url);
            return NavigationDecision.navigate;
          },
          onUrlChange: (UrlChange change) {
            if (change.url != null) {
              print('URL changed to: ${change.url}');
              _handleUrlChange(change.url!);
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(cleanUrl));
  }

  void _handleUrlChange(String url) {
    if (_isActivating || _isCancelled) return;
    final lowerUrl = url.toLowerCase();
    // Check cancel/failure FIRST — Khalti may redirect cancel back through the
    // same success.php endpoint but with cancel/failure status query parameters.
    if (_isCancelUrl(lowerUrl)) {
      _handlePaymentCancel();
    } else if (lowerUrl.contains('success.php') || lowerUrl.contains('success=true')) {
      _handlePaymentSuccess(url);
    }
  }

  bool _isCancelUrl(String lowerUrl) {
    // Match path-level cancel/failure segments (e.g. /cancel.php, /failed.php)
    final cancelPaths = [
      'cancel.php',
      'failed.php',
      'failure.php',
      'payment_failed',
      'paymentfailed',
      'payment-failed',
      'payment-cancel',
    ];
    for (final pattern in cancelPaths) {
      if (lowerUrl.contains(pattern)) return true;
    }
    // Match query parameter values like ?status=cancelled, ?status=User+cancelled,
    // ?result=declined, etc. Uses contains() so partial phrases like "user cancelled"
    // are also caught.
    final uri = Uri.tryParse(lowerUrl);
    if (uri != null) {
      final params = uri.queryParameters;
      for (final value in params.values) {
        final lowerValue = value.toLowerCase();
        if (lowerValue.contains('cancel') ||
            lowerValue.contains('fail') ||
            lowerValue.contains('decline')) return true;
      }
    }
    return false;
  }

  Future<void> _handlePaymentCancel() async {
    if (!mounted) return;
    setState(() {
      _isCancelled = true;
      _showWebView = false;
      _isProcessing = false;
    });

    // Notify backend about payment cancellation
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');

      if (userDataString != null) {
        final userData = jsonDecode(userDataString);
        final int userId = int.parse(userData["id"].toString());
        final String paidBy = _getPaidBy();

        // Call backend API to log cancelled payment
        await _notifyPaymentCancellation(
          userId: userId,
          paidBy: paidBy,
          packageId: widget.packageId,
        );
      }
    } catch (e) {
      print('Error logging payment cancellation: $e');
      // Don't block the UI even if logging fails
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Payment cancelled. Your package has not been activated.'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 3),
      ),
    );
    // Return to the packages page
    Navigator.of(context).pop();
  }

  Future<Map<String, dynamic>> purchasePackage({
    required int userId,
    required String paidBy,
    required int packageId,
    String? transactionId,
  }) async {
    final queryParams = {
      "userid": userId.toString(),
      "paidby": paidBy,
      "packageid": packageId.toString(),
    };

    // Add transaction ID if provided
    if (transactionId != null && transactionId.isNotEmpty) {
      queryParams["transaction_id"] = transactionId;
    }

    final Uri url = Uri.parse(
        "${kApiBaseUrl}/Api3/purchase_package.php"
    ).replace(queryParameters: queryParams);

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {
          "status": "error",
          "message": "Server error: ${response.statusCode}"
        };
      }
    } catch (e) {
      return {
        "status": "error",
        "message": e.toString()
      };
    }
  }

  Future<Map<String, dynamic>> _notifyPaymentCancellation({
    required int userId,
    required String paidBy,
    required int packageId,
  }) async {
    final Uri url = Uri.parse(
        "${kApiBaseUrl}/Api3/cancel_payment.php"
    ).replace(queryParameters: {
      "userid": userId.toString(),
      "paidby": paidBy,
      "packageid": packageId.toString(),
      "status": "cancelled",
    });

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {
          "status": "error",
          "message": "Server error: ${response.statusCode}"
        };
      }
    } catch (e) {
      return {
        "status": "error",
        "message": e.toString()
      };
    }
  }

  void _handlePaymentSuccess(String url) async {
    // Guard against multiple calls for the same payment event
    if (_isActivating) return;
    setState(() {
      _isActivating = true;
    });

    print('Payment success detected! URL: $url');

    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');

      if (userDataString == null) {
        throw Exception("User not logged in");
      }

      final userData = jsonDecode(userDataString);
      final int userId = int.parse(userData["id"].toString());
      final String paidBy = _getPaidBy();

      // Extract transaction ID from the payment gateway success URL
      final uri = Uri.tryParse(url);
      final queryParams = uri?.queryParameters ?? {};
      final transactionId = queryParams['transaction_id'] ??
          queryParams['tidx'] ??
          queryParams['pidx'];

      print('Payment URL parameters: $queryParams');
      if (transactionId == null) {
        print('⚠️ No transaction ID found in success URL — proceeding without it');
      }

      setState(() {
        _paymentStatus = "Activating package...";
      });

      // Activate package directly — the payment gateway's redirect to the
      // success URL is a reliable confirmation that payment succeeded.
      final result = await purchasePackage(
        userId: userId,
        paidBy: paidBy,
        packageId: widget.packageId,
        transactionId: transactionId,
      );

      if (result["status"] == "success") {
        print("✅ Package activated successfully");

        _showPaymentSuccessDialog();

        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) _restartApp(context);
        });
      } else {
        throw Exception(result["message"] ?? "Package activation failed");
      }
    } catch (e) {
      print("❌ Error in package activation: $e");
      setState(() {
        _isActivating = false;
        _showWebView = false;
      });

      _showErrorDialog(
          "Payment was successful but package activation failed. Please contact support with your transaction details.\n\nError: ${e.toString()}"
      );
    }
  }
  void _restartApp(BuildContext context) {
    // Clear navigation stack and restart main controller (includes bottom navbar)
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => PopScope(
          canPop: false,
          child: const MainControllerScreen(),
        ),
      ),
          (route) => false,
    );
  }

  void _showPaymentSuccessDialog() {
    // Close WebView if it's open
    if (_showWebView) {
      setState(() {
        _showWebView = false;
      });
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 24),
            SizedBox(width: 10),
            Text('Payment Successful'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Your payment has been processed successfully!'),
            SizedBox(height: 10),
            Text('Redirecting to home page...'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              _goToHomePage();
            },
            child: const Text('Go to Home'),
          ),
        ],
      ),
    );
  }

  void _goToHomePage() {
    // Navigate to your app's home page
    // You might need to adjust this based on your app structure
    Navigator.of(context).popUntil((route) => route.isFirst);

    // If you have a specific home route, use:
    // Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);

    // Or if you want to pop back to the previous screen and refresh:
    // Navigator.of(context).pop(true); // Return success flag
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Payment Failed'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _processPayment(); // Retry
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  void _showComingSoonDialog(String methodName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Coming Soon'),
        content: Text('$methodName payment integration is coming soon. Please use Khalti or Card for now.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

enum PaymentMethod {
  connectIps,
  khalti,
  card,
  esewa,
}

extension PaymentMethodExtension on PaymentMethod {
  String get name {
    switch (this) {
      case PaymentMethod.connectIps:
        return 'Connect IPS';
      case PaymentMethod.khalti:
        return 'Khalti';
      case PaymentMethod.card:
        return 'Card';
      case PaymentMethod.esewa:
        return 'Esewa';
    }
  }
}

class PaymentMethodTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
  final bool isSelected;
  final bool isEnabled;
  final VoidCallback onTap;
  final bool isRecommended;

  const PaymentMethodTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
    required this.isSelected,
    required this.isEnabled,
    required this.onTap,
    this.isRecommended = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isEnabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? backgroundColor.withOpacity(0.15) : backgroundColor.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? iconColor : backgroundColor,
            width: isSelected ? 2.5 : 1,
          ),
          boxShadow: isSelected ? [
            BoxShadow(
              color: iconColor.withOpacity(0.15),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ] : [],
        ),
        child: Stack(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSelected ? iconColor.withOpacity(0.15) : AppColors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: iconColor, size: 26),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTextStyles.labelMedium.copyWith(
                          fontSize: 15,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle!,
                          style: AppTextStyles.bodySmall.copyWith(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                AnimatedScale(
                  scale: isSelected ? 1.0 : 0.8,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: isSelected ? iconColor : AppColors.border,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isSelected ? Icons.check_circle : Icons.circle_outlined,
                      color: AppColors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
            if (isRecommended)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Recommended',
                    style: AppTextStyles.whiteBody.copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}