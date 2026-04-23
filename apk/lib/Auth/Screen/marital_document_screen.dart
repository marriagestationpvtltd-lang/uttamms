import 'dart:convert';
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import '../../constant/app_colors.dart';
import '../../service/ocr_service.dart';
import '../../service/document_scanner_service.dart';
import 'package:ms2026/config/app_endpoints.dart';

/// Redesigned marital-document upload screen.
///
/// Each required document type has its own independent state:
///   not_uploaded → upload button
///   pending      → "Under Review"
///   approved     → verified badge (no action)
///   rejected     → reject reason + re-upload button
class MaritalDocumentUploadScreen extends StatefulWidget {
  const MaritalDocumentUploadScreen({super.key});

  @override
  State<MaritalDocumentUploadScreen> createState() =>
      _MaritalDocumentUploadScreenState();
}

class _MaritalDocumentUploadScreenState
    extends State<MaritalDocumentUploadScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {

  final ImagePicker _picker = ImagePicker();
  final OCRService _ocrService = OCRService();
  final DocumentScannerService _documentScanner = DocumentScannerService();

  // ── per-document state map ────────────────────────────────────────────────
  // key = documenttype label, value = {status, reject_reason}
  final Map<String, Map<String, dynamic>> _documentStates = {};

  // ── active upload state (set when user taps Upload / Re-upload) ───────────
  String? _activeDocType;
  XFile? _selectedImage;
  String? _scannedImagePath;
  final TextEditingController _documentNumberController =
      TextEditingController();
  bool _hasConsented = false;
  bool _isScanning = false;

  // ── global loading flags ──────────────────────────────────────────────────
  bool _isLoading = true;
  bool _isCheckingStatus = false;
  bool _isUploading = false;

  String? _maritalStatus;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  static const double _kPulseScaleMin = 0.94;
  static const double _kPulseScaleMax = 1.06;

  // ── all possible document types ───────────────────────────────────────────
  final List<Map<String, dynamic>> _allDocumentTypes = [
    {'label': 'Death Certificate',    'icon': Icons.article_outlined},
    {'label': 'Divorce Decree',       'icon': Icons.gavel_rounded},
    {'label': 'Court Order',          'icon': Icons.balance_rounded},
    {'label': 'Marriage Certificate', 'icon': Icons.favorite_border_rounded},
    {'label': 'Separation Document',  'icon': Icons.assignment_outlined},
  ];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1100),
      vsync: this,
    )..repeat(reverse: true);
    _fadeAnimation =
        CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _pulseAnimation =
        Tween<double>(begin: _kPulseScaleMin, end: _kPulseScaleMax).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _loadMaritalStatus();
    _checkDocumentStatuses();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fadeController.dispose();
    _pulseController.dispose();
    _documentNumberController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _checkDocumentStatuses();
    }
  }

  // ─── helpers ─────────────────────────────────────────────────────────────

  Future<void> _loadMaritalStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final status = prefs.getString('selected_marital_status');
    if (mounted) setState(() => _maritalStatus = status);
  }

  List<Map<String, dynamic>> _getRequiredDocTypes() {
    switch (_maritalStatus) {
      case 'Widowed':
        return [
          {'label': 'Death Certificate',    'icon': Icons.article_outlined},
          {'label': 'Marriage Certificate', 'icon': Icons.favorite_border_rounded},
        ];
      case 'Divorced':
        return [
          {'label': 'Divorce Decree', 'icon': Icons.gavel_rounded},
          {'label': 'Court Order',    'icon': Icons.balance_rounded},
        ];
      case 'Waiting Divorce':
        return [
          {'label': 'Divorce Decree',      'icon': Icons.gavel_rounded},
          {'label': 'Separation Document', 'icon': Icons.assignment_outlined},
        ];
      default:
        return [];
    }
  }

  /// Returns a screen title that reflects the user's specific marital status.
  String get _screenTitle {
    switch (_maritalStatus) {
      case 'Widowed':
        return 'Widowhood Documents';
      case 'Divorced':
        return 'Divorce Documents';
      case 'Waiting Divorce':
        return 'Separation Documents';
      default:
        return 'Marital Status Verification';
    }
  }

  // ─── API ─────────────────────────────────────────────────────────────────

  Future<void> _checkDocumentStatuses() async {
    if (_isCheckingStatus) return;
    setState(() {
      _isCheckingStatus = true;
      _isLoading = true;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');
      if (userDataString == null) {
        _showError('User data not found. Please login again.');
        return;
      }
      final userData = jsonDecode(userDataString);
      final userId = int.tryParse(userData['id'].toString());
      if (userId == null) return;

      final response = await http.post(
        Uri.parse('${kApiBaseUrl}/Api2/check_document_status.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': userId}),
      );
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final docs = result['documents'] as List<dynamic>? ?? [];
          setState(() {
            _documentStates.clear();
            for (final doc in docs) {
              final type = doc['documenttype'] as String? ?? '';
              if (type.isNotEmpty) {
                _documentStates[type] = {
                  'status':        doc['status'] ?? 'not_uploaded',
                  'reject_reason': doc['reject_reason'] ?? '',
                };
              }
            }
          });
        }
      }
    } catch (_) {
      _showError('Failed to check status. Please try again.');
    } finally {
      setState(() {
        _isLoading = false;
        _isCheckingStatus = false;
      });
      _fadeController.forward(from: 0);
    }
  }

  Future<void> _uploadDocument() async {
    if (_activeDocType == null) return;
    setState(() => _isUploading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');
      final userData = jsonDecode(userDataString!);
      final userId = int.tryParse(userData['id'].toString());

      final uri = Uri.parse('${kApiBaseUrl}/Api2/upload_document.php');
      final request = http.MultipartRequest('POST', uri);
      request.fields['userid']           = userId.toString();
      request.fields['documenttype']     = _activeDocType!;
      request.fields['documentidnumber'] = _documentNumberController.text;

      final String imagePath = _scannedImagePath ?? _selectedImage!.path;
      final imageFile = await http.MultipartFile.fromPath('photo', imagePath);
      request.files.add(imageFile);

      final response = await request.send();
      if (response.statusCode == 200) {
        setState(() {
          _documentStates[_activeDocType!] = {
            'status':        'pending',
            'reject_reason': '',
          };
          _activeDocType = null;
          _selectedImage = null;
          _scannedImagePath = null;
          _hasConsented = false;
          _documentNumberController.clear();
        });
        _fadeController.forward(from: 0);
        _showSuccess("Document submitted! We'll notify you once it's verified.");
      } else {
        _showError('Upload failed. Please try again.');
      }
    } catch (_) {
      _showError('Error uploading document. Check your connection.');
    } finally {
      setState(() => _isUploading = false);
    }
  }

  // ─── BUILD ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: _isLoading
          ? _buildLoadingScreen()
          : FadeTransition(
              opacity: _fadeAnimation,
              child: _activeDocType != null
                  ? _buildUploadFormScreen()
                  : _buildDocumentListScreen(),
            ),
    );
  }

  Widget _buildLoadingScreen() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFF90E18), Color(0xFFD00D15)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
            SizedBox(height: 20),
            Text(
              'Checking document status...',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  // ─── DOCUMENT LIST SCREEN ─────────────────────────────────────────────────

  Widget _buildDocumentListScreen() {
    final requiredDocs = _getRequiredDocTypes();
    if (requiredDocs.isEmpty) {
      return Column(
        children: [
          _buildHeroHeader(
            title: _screenTitle,
            subtitle: 'Upload the required documents for verification',
            icon: Icons.family_restroom_rounded,
            showBack: true,
            onBack: () => Navigator.pop(context),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.check_circle_outline_rounded,
                          color: AppColors.primary, size: 48),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'No Documents Required',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF212121)),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Your current marital status does not require any supporting documents.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 14, color: Color(0xFF757575), height: 1.5),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        _buildHeroHeader(
          title: _screenTitle,
          subtitle: 'Upload the required documents for verification',
          icon: Icons.family_restroom_rounded,
          showBack: true,
          onBack: () => Navigator.pop(context),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _checkDocumentStatuses,
            color: AppColors.primary,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoNote(),
                  const SizedBox(height: 24),
                  ...requiredDocs.map(
                    (doc) => Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _buildDocumentCard(doc),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoNote() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFCC02).withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              color: Color(0xFFF57F17), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _maritalStatus != null && _maritalStatus != 'Still Unmarried'
                  ? 'Upload the documents below to verify your "$_maritalStatus" status.'
                  : 'Upload a supporting document to verify your marital status.',
              style: const TextStyle(
                  fontSize: 13, color: Color(0xFF5D4037), height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  // ─── PER-DOCUMENT CARD ────────────────────────────────────────────────────

  Widget _buildDocumentCard(Map<String, dynamic> docType) {
    final label  = docType['label'] as String;
    final icon   = docType['icon'] as IconData;
    final state  = _documentStates[label] ?? {'status': 'not_uploaded', 'reject_reason': ''};
    final status = state['status'] as String? ?? 'not_uploaded';

    switch (status) {
      case 'approved':
        return _buildVerifiedCard(label, icon);
      case 'pending':
        return _buildPendingCard(label, icon);
      case 'rejected':
        return _buildRejectedCard(label, icon, state['reject_reason'] as String? ?? '');
      default:
        return _buildNotUploadedCard(label, icon);
    }
  }

  Widget _buildNotUploadedCard(String label, IconData icon) {
    return _cardContainer(
      borderColor: const Color(0xFFE0E0E0),
      child: Row(
        children: [
          _docIcon(icon, const Color(0xFF757575), const Color(0xFFF5F5F5)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold,
                        color: Color(0xFF212121))),
                const SizedBox(height: 4),
                const Text('Not uploaded',
                    style: TextStyle(fontSize: 13, color: Color(0xFF9E9E9E))),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _uploadButton(
            label: 'Upload',
            icon: Icons.upload_rounded,
            color: AppColors.primary,
            onTap: () => _startUpload(label, icon),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingCard(String label, IconData icon) {
    return _cardContainer(
      borderColor: const Color(0xFFF57C00).withOpacity(0.4),
      bgColor: const Color(0xFFFFF8E1),
      child: Row(
        children: [
          _docIcon(icon, const Color(0xFFF57C00),
              const Color(0xFFF57C00).withOpacity(0.1)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold,
                        color: Color(0xFF212121))),
                const SizedBox(height: 6),
                Row(
                  children: [
                    ScaleTransition(
                      scale: _pulseAnimation,
                      child: const Icon(Icons.hourglass_top_rounded,
                          color: Color(0xFFF57C00), size: 16),
                    ),
                    const SizedBox(width: 6),
                    const Text('Under Review',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFF57C00))),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerifiedCard(String label, IconData icon) {
    return _cardContainer(
      borderColor: const Color(0xFF2E7D32).withOpacity(0.4),
      bgColor: const Color(0xFFE8F5E9),
      child: Row(
        children: [
          _docIcon(icon, const Color(0xFF2E7D32),
              const Color(0xFF2E7D32).withOpacity(0.1)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold,
                        color: Color(0xFF212121))),
                const SizedBox(height: 6),
                const Row(
                  children: [
                    Icon(Icons.verified_rounded,
                        color: Color(0xFF2E7D32), size: 16),
                    SizedBox(width: 4),
                    Text('Verified',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF2E7D32))),
                    SizedBox(width: 6),
                    Icon(Icons.lock_rounded,
                        color: Color(0xFF2E7D32), size: 14),
                    SizedBox(width: 4),
                    Text('Locked',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF2E7D32))),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRejectedCard(String label, IconData icon, String rejectReason) {
    return _cardContainer(
      borderColor: const Color(0xFFC62828).withOpacity(0.4),
      bgColor: const Color(0xFFFFF5F5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _docIcon(icon, const Color(0xFFC62828),
                  const Color(0xFFC62828).withOpacity(0.1)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold,
                            color: Color(0xFF212121))),
                    const SizedBox(height: 6),
                    const Row(
                      children: [
                        Icon(Icons.cancel_rounded,
                            color: Color(0xFFC62828), size: 16),
                        SizedBox(width: 6),
                        Text('Rejected',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFC62828))),
                      ],
                    ),
                  ],
                ),
              ),
              _uploadButton(
                label: 'Re-upload',
                icon: Icons.upload_rounded,
                color: AppColors.primary,
                onTap: () => _startUpload(label, icon),
              ),
            ],
          ),
          if (rejectReason.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFFCDD2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_rounded,
                      color: Color(0xFFC62828), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      rejectReason,
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF424242), height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── CARD HELPERS ─────────────────────────────────────────────────────────

  Widget _cardContainer({
    required Widget child,
    Color? borderColor,
    Color? bgColor,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor ?? Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor ?? const Color(0xFFE0E0E0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _docIcon(IconData icon, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Icon(icon, color: color, size: 26),
    );
  }

  Widget _uploadButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }

  // ─── UPLOAD FORM SCREEN ───────────────────────────────────────────────────

  void _startUpload(String docType, IconData icon) {
    setState(() {
      _activeDocType = docType;
      _selectedImage = null;
      _scannedImagePath = null;
      _hasConsented = false;
      _documentNumberController.clear();
    });
  }

  Widget _buildUploadFormScreen() {
    final docIcon = _getRequiredDocTypes().firstWhere(
      (d) => d['label'] == _activeDocType,
      orElse: () => {'icon': Icons.article_outlined},
    )['icon'] as IconData;

    return Column(
      children: [
        _buildHeroHeader(
          title: _activeDocType!,
          subtitle: 'Upload a clear photo of this document',
          icon: docIcon,
          showBack: true,
          onBack: () => setState(() {
            _activeDocType = null;
            _selectedImage = null;
            _scannedImagePath = null;
            _hasConsented = false;
            _documentNumberController.clear();
          }),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Photo upload area
                _buildSectionTitle('1. Document Photo'),
                const SizedBox(height: 12),
                (_selectedImage != null || _scannedImagePath != null)
                    ? _buildImagePreview()
                    : _buildPhotoUploadArea(),

                // Document number (optional)
                if (_selectedImage != null || _scannedImagePath != null) ...[
                  const SizedBox(height: 28),
                  _buildSectionTitle('2. Document Number (Optional)'),
                  const SizedBox(height: 8),
                  const Text(
                    'Enter the document number if available',
                    style: TextStyle(
                        fontSize: 14, color: Color(0xFF757575), height: 1.5),
                  ),
                  const SizedBox(height: 14),
                  _buildDocumentNumberField(),
                  const SizedBox(height: 28),
                  _buildGuidelinesCard(),
                  const SizedBox(height: 20),
                  _buildConsentCard(),
                  const SizedBox(height: 28),
                  _buildSubmitButton(),
                  const SizedBox(height: 40),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─── SHARED WIDGETS ───────────────────────────────────────────────────────

  Widget _buildHeroHeader({
    required String title,
    required String subtitle,
    required IconData icon,
    bool showBack = false,
    VoidCallback? onBack,
  }) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFF90E18), Color(0xFFD00D15)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showBack)
                GestureDetector(
                  onTap: onBack,
                  child: const Icon(Icons.arrow_back_ios_new,
                      color: Colors.white, size: 20),
                ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: Colors.white, size: 36),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 13, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: Color(0xFF212121),
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }

  Widget _buildPhotoUploadArea() {
    return GestureDetector(
      onTap: _showImageSourceSelector,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: AppColors.primary.withOpacity(0.4), width: 2.5),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.35),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(Icons.cloud_upload_rounded,
                  color: Colors.white, size: 40),
            ),
            const SizedBox(height: 20),
            const Text(
              'Upload Document Photo',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF212121)),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap here to scan or select from gallery',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14, color: Color(0xFF757575), height: 1.4)),
            const SizedBox(height: 16),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.document_scanner_rounded,
                      color: AppColors.primary, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Scan recommended',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    return Column(
      children: [
        Container(
          height: 240,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.success, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: AppColors.success.withOpacity(0.15),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                if (_scannedImagePath != null)
                  kIsWeb
                      ? FutureBuilder(
                          future: XFile(_scannedImagePath!).readAsBytes(),
                          builder: (context, snap) => snap.hasData
                              ? Image.memory(snap.data!,
                                  width: double.infinity,
                                  height: double.infinity,
                                  fit: BoxFit.cover)
                              : const SizedBox(),
                        )
                      : Image.file(
                          File(_scannedImagePath!),
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.cover,
                        )
                else if (_selectedImage != null)
                  FutureBuilder(
                    future: _selectedImage!.readAsBytes(),
                    builder: (context, snapshot) {
                      if (snapshot.hasData) {
                        return Image.memory(
                          snapshot.data!,
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.cover,
                        );
                      }
                      return const Center(
                        child: CircularProgressIndicator(
                          valueColor:
                              AlwaysStoppedAnimation(AppColors.primary),
                        ),
                      );
                    },
                  ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.success,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle,
                            color: Colors.white, size: 16),
                        SizedBox(width: 6),
                        Text('Photo Ready',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _showImageSourceSelector,
                icon: const Icon(Icons.refresh_rounded, size: 20),
                label: const Text('Change Photo'),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.primary, width: 1.5),
                  foregroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _removeImage,
                icon: const Icon(Icons.delete_outline_rounded,
                    size: 20, color: Colors.red),
                label: const Text('Remove',
                    style: TextStyle(color: Colors.red)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red, width: 1.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDocumentNumberField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0E0E0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _documentNumberController,
        autofocus: false,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => FocusScope.of(context).unfocus(),
        onChanged: (_) => setState(() {}),
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          hintText: 'Enter document number (if available)',
          hintStyle:
              const TextStyle(color: Color(0xFF9E9E9E), fontSize: 14),
          prefixIcon: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.numbers_rounded,
                color: AppColors.primary, size: 20),
          ),
          suffixIcon: (_selectedImage != null || _scannedImagePath != null)
              ? _isScanning
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              AppColors.primary),
                        ),
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.document_scanner_rounded,
                          color: AppColors.primary, size: 22),
                      tooltip: 'Scan document number',
                      onPressed: _scanDocumentId,
                    )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        ),
      ),
    );
  }

  Widget _buildGuidelinesCard() {
    final guidelines = [
      {'icon': Icons.wb_sunny_outlined,          'text': 'Use good, even lighting'},
      {'icon': Icons.center_focus_strong_outlined,'text': 'All four corners must be visible'},
      {'icon': Icons.text_fields_rounded,         'text': 'All text must be clearly readable'},
      {'icon': Icons.block_rounded,               'text': 'No glare, blur, or obstruction'},
    ];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBBDEFB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.lightbulb_outline_rounded,
                    color: Color(0xFF1565C0), size: 22),
              ),
              const SizedBox(width: 12),
              const Text('Photo Tips',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1565C0))),
            ],
          ),
          const SizedBox(height: 16),
          ...guidelines.map((g) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1976D2).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(g['icon'] as IconData,
                          size: 16, color: const Color(0xFF1976D2)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          g['text'] as String,
                          style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF424242),
                              height: 1.4),
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildConsentCard() {
    return GestureDetector(
      onTap: () => setState(() => _hasConsented = !_hasConsented),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _hasConsented ? const Color(0xFFF1F8E9) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _hasConsented
                ? AppColors.success
                : const Color(0xFFE0E0E0),
            width: 2,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: _hasConsented ? AppColors.success : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _hasConsented
                      ? AppColors.success
                      : const Color(0xFFBDBDBD),
                  width: 2,
                ),
              ),
              child: _hasConsented
                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                  : null,
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Text(
                'I consent to use of this document solely for marital-status verification. It will remain confidential and will not be shared with third parties.',
                style: TextStyle(
                    fontSize: 14, color: Color(0xFF424242), height: 1.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    final canSubmit = (_selectedImage != null || _scannedImagePath != null) &&
        _hasConsented &&
        !_isUploading;

    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: canSubmit
            ? [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : [],
      ),
      child: ElevatedButton(
        onPressed: canSubmit ? _validateAndSubmit : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          disabledBackgroundColor: AppColors.primary.withOpacity(0.5),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
        child: _isUploading
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5),
                  ),
                  SizedBox(width: 14),
                  Text('Uploading...',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                ],
              )
            : const Text(
                'Submit for Verification',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Colors.white),
              ),
      ),
    );
  }

  // ─── IMAGE / SCAN HELPERS ─────────────────────────────────────────────────

  void _showImageSourceSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E0E0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Text('Choose Upload Method',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Scan, take a photo, or choose from gallery',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 20),
              _buildSourceOption(
                icon: Icons.document_scanner_rounded,
                label: 'Scan Document',
                subtitle: 'Auto edge detection',
                isRecommended: true,
                onTap: () {
                  Navigator.pop(context);
                  _scanDocument();
                },
              ),
              const SizedBox(height: 12),
              _buildSourceOption(
                icon: Icons.photo_library_rounded,
                label: 'Gallery',
                subtitle: 'Choose existing',
                onTap: () {
                  Navigator.pop(context);
                  _selectFromGallery();
                },
              ),
              const SizedBox(height: 12),
              _buildSourceOption(
                icon: Icons.camera_alt_rounded,
                label: 'Camera',
                subtitle: 'Take a photo',
                onTap: () {
                  Navigator.pop(context);
                  _selectFromCamera();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSourceOption({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
    bool isRecommended = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isRecommended
              ? AppColors.primary.withOpacity(0.05)
              : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isRecommended
                ? AppColors.primary.withOpacity(0.3)
                : const Color(0xFFE0E0E0),
          ),
        ),
        child: Column(
          children: [
            if (isRecommended)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('RECOMMENDED',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              ),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 12),
            Text(label,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isRecommended ? AppColors.primary : Colors.black87)),
            const SizedBox(height: 4),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Future<void> _scanDocument() async {
    try {
      final scannedPaths = await _documentScanner.scanDocument(
        numberOfPages: 1,
        allowGallery: true,
      );
      if (scannedPaths != null && scannedPaths.isNotEmpty) {
        setState(() {
          _scannedImagePath = scannedPaths.first;
          _selectedImage = null;
        });
        await _scanDocumentId();
      }
    } catch (e) {
      _showError('Failed to scan document: $e');
    }
  }

  Future<void> _selectFromGallery() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 90,
      );
      if (image != null) {
        setState(() {
          _selectedImage = image;
          _scannedImagePath = null;
        });
        await _scanDocumentId();
      }
    } catch (e) {
      _showError('Failed to select image: $e');
    }
  }

  Future<void> _selectFromCamera() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 90,
      );
      if (image != null) {
        setState(() {
          _selectedImage = image;
          _scannedImagePath = null;
        });
        await _scanDocumentId();
      }
    } catch (e) {
      _showError('Failed to capture image: $e');
    }
  }

  void _removeImage() => setState(() {
        _selectedImage = null;
        _scannedImagePath = null;
      });

  Future<void> _scanDocumentId() async {
    if (_selectedImage == null && _scannedImagePath == null) return;
    setState(() => _isScanning = true);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Colors.white)),
              ),
              SizedBox(width: 12),
              Text('Scanning document number...'),
            ],
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }

    try {
      if (!kIsWeb) {
        final File imageFile = _scannedImagePath != null
            ? File(_scannedImagePath!)
            : File(_selectedImage!.path);
        final String? extractedText =
            await _ocrService.extractDocumentId(imageFile);
        setState(() => _isScanning = false);
        if (extractedText != null && extractedText.isNotEmpty) {
          _showScanResultDialog(extractedText);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.white, size: 20),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                          'No document number detected. You can enter it manually.'),
                    ),
                  ],
                ),
                backgroundColor: Colors.orange,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            );
          }
        }
      } else {
        setState(() => _isScanning = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'OCR scanning is not available on web. Please enter the document number manually.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (_) {
      setState(() => _isScanning = false);
    }
  }

  void _showScanResultDialog(String scannedText) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.document_scanner_rounded,
                  color: AppColors.primary, size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Document Scanned',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3CD),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFFECAA)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Color(0xFFE6A800), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Scanned information may be incorrect. Please verify before confirming.',
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[800],
                          height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text('Scanned Document Number:',
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppColors.primary.withOpacity(0.3)),
              ),
              child: SelectableText(
                scannedText,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _documentNumberController.text = scannedText;
              });
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text('Use This Number'),
          ),
        ],
      ),
    );
  }

  void _validateAndSubmit() {
    if (_selectedImage == null && _scannedImagePath == null) {
      _showError('Please upload a photo of your document');
      return;
    }
    if (!_hasConsented) {
      _showError('Please accept the consent checkbox to continue');
      return;
    }
    _uploadDocument();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

