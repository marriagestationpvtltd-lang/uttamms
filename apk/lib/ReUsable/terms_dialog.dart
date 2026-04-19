// Scrollable Terms & Conditions / Privacy Policy Bottom Sheet
// Shows full T&C content; Accept button is enabled only after user scrolls to bottom.
import 'package:flutter/material.dart';
import '../constant/app_colors.dart';
import 'package:ms2026/config/app_endpoints.dart';

/// Call [TermsConditionsBottomSheet.show] to present the dialog.
/// Returns `true` if the user accepted, `false` or `null` otherwise.
class TermsConditionsBottomSheet {
  static Future<bool> show(BuildContext context) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _TermsSheetContent(),
    );
    return result == true;
  }
}

class _TermsSheetContent extends StatefulWidget {
  const _TermsSheetContent();

  @override
  State<_TermsSheetContent> createState() => _TermsSheetContentState();
}

class _TermsSheetContentState extends State<_TermsSheetContent> {
  final ScrollController _scrollController = ScrollController();
  bool _hasScrolledToBottom = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Check immediately in case content is shorter than viewport
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkScroll());
  }

  void _onScroll() => _checkScroll();

  void _checkScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 60) {
      if (!_hasScrolledToBottom) {
        setState(() => _hasScrolledToBottom = true);
      }
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      height: screenHeight * 0.92,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade200),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.privacy_tip_outlined,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Terms & Privacy Policy',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF212121),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Please read and scroll to the bottom to continue',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Scroll indicator hint
          if (!_hasScrolledToBottom)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AppColors.primary.withOpacity(0.05),
              child: Row(
                children: [
                  Icon(Icons.arrow_downward, size: 14, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Scroll down to read all terms before accepting',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Content
          Expanded(
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: const _TermsContent(),
              ),
            ),
          ),

          // Bottom buttons
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 10,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_hasScrolledToBottom)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        'Please scroll to the bottom to enable the Accept button',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      // Decline button
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.grey.shade700,
                            side: BorderSide(color: Colors.grey.shade300),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Decline',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Accept button
                      Expanded(
                        flex: 2,
                        child: AnimatedOpacity(
                          opacity: _hasScrolledToBottom ? 1.0 : 0.4,
                          duration: const Duration(milliseconds: 300),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: _hasScrolledToBottom
                                  ? const LinearGradient(
                                      colors: [Color(0xFFF90E18), Color(0xFFC10810)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    )
                                  : const LinearGradient(
                                      colors: [Colors.grey, Colors.grey],
                                    ),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: _hasScrolledToBottom
                                  ? [
                                      BoxShadow(
                                        color: AppColors.primary.withOpacity(0.3),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      )
                                    ]
                                  : [],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: _hasScrolledToBottom
                                    ? () => Navigator.of(context).pop(true)
                                    : null,
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 14),
                                  child: Center(
                                    child: Text(
                                      'I Accept & Continue',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Terms & Privacy Policy content ──────────────────────────────────────────
class _TermsContent extends StatelessWidget {
  const _TermsContent();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Marriage Station – Terms of Service & Privacy Policy'),
        _body(
          'Last updated: January 2025\n\n'
          'Welcome to Marriage Station ("we", "our", or "us"). By creating an account or '
          'using our application, you agree to be bound by these Terms of Service and our '
          'Privacy Policy. Please read them carefully before proceeding.',
        ),

        _divider(),

        _heading('1. Acceptance of Terms'),
        _body(
          'By registering for or using the Marriage Station application, you acknowledge that '
          'you have read, understood, and agree to these Terms of Service. If you do not agree '
          'to these terms, please do not create an account or use our services.',
        ),

        _divider(),

        _heading('2. Eligibility'),
        _body(
          '• You must be at least 18 years of age to register and use this service.\n'
          '• You must be legally capable of entering into a binding contract.\n'
          '• You confirm that you are not already married (unless seeking re-marriage after '
          'dissolution of a previous marriage as permitted by applicable laws).\n'
          '• You agree to provide accurate, truthful, and current information during registration.',
        ),

        _divider(),

        _heading('3. Account Registration'),
        _body(
          'When you register an account, you agree to:\n'
          '• Provide true, accurate, and complete information about yourself.\n'
          '• Keep your account credentials (email and password) confidential.\n'
          '• Notify us immediately of any unauthorized use of your account.\n'
          '• Not create multiple accounts or impersonate another person.\n'
          '• Not register on behalf of any other person without their explicit consent.',
        ),

        _divider(),

        _heading('4. User Conduct'),
        _body(
          'You agree NOT to:\n'
          '• Harass, abuse, threaten, or intimidate other users.\n'
          '• Share false, misleading, or fraudulent information.\n'
          '• Post or send explicit, offensive, or harmful content.\n'
          '• Solicit money, personal financial information, or engage in any commercial activity.\n'
          '• Attempt to breach the security of our application.\n'
          '• Use the platform for any illegal or unauthorized purpose.',
        ),

        _divider(),

        _heading('5. Profile Information & Photos'),
        _body(
          'You are responsible for all content you post on your profile. By submitting photos '
          'and personal information, you grant Marriage Station a non-exclusive licence to display '
          'this content to verified users of the platform for matchmaking purposes. We do not '
          'sell your photos or personal data to third parties.',
        ),

        _divider(),

        _heading('6. Privacy Policy'),
        _body(
          'Marriage Station is committed to protecting your privacy. This section outlines how '
          'we collect, use, and safeguard your personal information.',
        ),

        _subheading('6.1 Information We Collect'),
        _body(
          '• Personal details: name, date of birth, gender, contact number, email address.\n'
          '• Profile information: religion, caste, education, occupation, family details.\n'
          '• Physical information: height, weight, complexion (provided voluntarily).\n'
          '• Location data: city, district, country of residence.\n'
          '• Government-issued ID for identity verification (stored securely).\n'
          '• Device information and usage data for app improvement.',
        ),

        _subheading('6.2 How We Use Your Information'),
        _body(
          '• To provide and personalise the matchmaking service.\n'
          '• To display your profile to other registered users who meet your partner preferences.\n'
          '• To communicate with you about matches, notifications, and service updates.\n'
          '• To verify your identity and prevent fraudulent activity.\n'
          '• To improve the app experience through anonymised analytics.',
        ),

        _subheading('6.3 Data Sharing'),
        _body(
          'We do not sell, rent, or trade your personal information to third parties. Your '
          'profile is visible only to verified, registered users of Marriage Station. We may '
          'share data with trusted service providers (e.g., cloud hosting, push notifications) '
          'strictly to operate our service, under strict confidentiality agreements.',
        ),

        _subheading('6.4 Data Security'),
        _body(
          'We implement industry-standard security measures including encrypted communications '
          '(HTTPS), secure data storage, and restricted access controls. However, no method of '
          'transmission over the internet is 100% secure and we cannot guarantee absolute security.',
        ),

        _subheading('6.5 Your Rights'),
        _body(
          'You have the right to:\n'
          '• Access, update, or correct your personal information at any time.\n'
          '• Request deletion of your account and associated data.\n'
          '• Opt out of promotional communications.\n'
          '• Contact us with any privacy concerns at support@digitallami.com.',
        ),

        _divider(),

        _heading('7. ID Verification'),
        _body(
          'To maintain a safe community, we require identity verification. The documents you '
          'submit are used solely for verification purposes and stored securely. Verified profiles '
          'receive a badge visible to other users, increasing trust and match quality.',
        ),

        _divider(),

        _heading('8. Subscription & Payments'),
        _body(
          'Certain premium features may require a paid subscription. All payments are processed '
          'securely. Subscription fees are non-refundable except as required by applicable law. '
          'We reserve the right to modify pricing with reasonable advance notice.',
        ),

        _divider(),

        _heading('9. Termination'),
        _body(
          'We reserve the right to suspend or terminate your account if you violate these terms '
          'or engage in conduct harmful to other users or the platform. You may delete your '
          'account at any time through the app settings.',
        ),

        _divider(),

        _heading('10. Limitation of Liability'),
        _body(
          'Marriage Station is a platform that facilitates introductions between individuals. '
          'We do not guarantee any specific outcome, including marriage or relationship success. '
          'We are not liable for any interactions, meetings, or consequences arising from '
          'connections made through our platform. Always exercise personal safety and good '
          'judgment when meeting anyone online or offline.',
        ),

        _divider(),

        _heading('11. Changes to These Terms'),
        _body(
          'We may update these Terms and Privacy Policy from time to time. Continued use of '
          'the application after changes are posted constitutes your acceptance of the updated terms.',
        ),

        _divider(),

        _heading('12. Contact Us'),
        _body(
          'If you have questions about these Terms or our Privacy Policy, please contact us:\n\n'
          'Marriage Station (Digitallami Pvt. Ltd.)\n'
          'Email: support@digitallami.com\n'
          'Website: ${kApiBaseUrl}\n\n'
          'By scrolling to the bottom and pressing "I Accept & Continue", you confirm that you '
          'have read, understood, and agree to these Terms of Service and Privacy Policy.',
        ),

        const SizedBox(height: 8),
      ],
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
            height: 1.4,
          ),
        ),
      );

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 6),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Color(0xFF212121),
          ),
        ),
      );

  Widget _subheading(String text) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 4),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF424242),
          ),
        ),
      );

  Widget _body(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF616161),
            height: 1.6,
          ),
        ),
      );

  Widget _divider() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Divider(color: Colors.grey.shade200, thickness: 1),
      );
}
