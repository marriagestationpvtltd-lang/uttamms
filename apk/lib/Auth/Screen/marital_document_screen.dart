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
import '../../Startup/MainControllere.dart';
import 'package:ms2026/config/app_endpoints.dart';

/// Screen for uploading a marital-status supporting document (additional
/// details verification). Completely separate from [IDVerificationScreen]
/// which handles complement/identity documents.
class MaritalDocumentUploadScreen extends StatefulWidget {
  const MaritalDocumentUploadScreen({super.key});

  @override
  State<MaritalDocumentUploadScreen> createState() =>
      _MaritalDocumentUploadScreenState();
}

class _MaritalDocumentUploadScreenState
    extends State<MaritalDocumentUploadScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const double _kPulseScaleMin = 0.94;
  static const double _kPulseScaleMax = 1.06;

  final ImagePicker _picker = ImagePicker();
  final OCRService _ocrService = OCRService();
  final DocumentScannerService _documentScanner = DocumentScannerService();

  String? _selectedDocumentType;
  final TextEditingController _documentNumberController =
      TextEditingController();
  XFile? _selectedImage;
  String? _scannedImagePath;

  String _documentStatus = 'not_uploaded';
  String _rejectReason = '';
  String? _uploadedDocumentType; // Track which document type was uploaded
  String? _maritalStatus;
  bool _isLoading = true;
  bool _isCheckingStatus = false;
  bool _isUploading = false;
  bool _hasConsented = false;
  bool _isScanning = false;

  late AnimationController _fadeController;
  late AnimationController _pulseController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _pulseAnimation;

  /// Document types relevant to marital-status verification.
  final List<Map<String, dynamic>> _documentTypes = [
    {'label': 'Death Certificate', 'icon': Icons.article_outlined},
    {'label': 'Divorce Decree', 'icon': Icons.gavel_rounded},
    {'label': 'Court Order', 'icon': Icons.balance_rounded},
    {'label': 'Marriage Certificate', 'icon': Icons.favorite_border_rounded},
    {'label': 'Separation Document', 'icon': Icons.assignment_outlined},
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
    _checkDocumentStatus();
    _loadMaritalStatus();
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
      _checkDocumentStatus();
    }
  }

  // ─── API ─────────────────────────────────────────────────────────────────

  Future<void> _loadMaritalStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final status = prefs.getString('selected_marital_status');
    if (mounted) setState(() => _maritalStatus = status);
  }

  List<Map<String, dynamic>> _getFilteredDocumentTypes() {
    switch (_maritalStatus) {
      case 'Widowed':
        return [
          {'label': 'Death Certificate', 'icon': Icons.article_outlined},
          {'label': 'Marriage Certificate', 'icon': Icons.favorite_border_rounded},
        ];
      case 'Divorced':
        return [
          {'label': 'Divorce Decree', 'icon': Icons.gavel_rounded},
          {'label': 'Court Order', 'icon': Icons.balance_rounded},
        ];
      case 'Waiting Divorce':
        return [
          {'label': 'Divorce Decree', 'icon': Icons.gavel_rounded},
          {'label': 'Separation Document', 'icon': Icons.assignment_outlined},
        ];
      default:
        return _documentTypes;
    }
  }

  Future<void> _checkDocumentStatus() async {
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
        Uri.parse(
            '${kApiBaseUrl}/Api2/check_document_status.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': userId}),
      );
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final newStatus = result['status'] ?? 'not_uploaded';
          setState(() {
            _documentStatus = newStatus;
            _rejectReason = result['reject_reason'] ?? '';
            _uploadedDocumentType = result['document_type'];
          });
        }
      }
    } catch (e) {
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
    setState(() => _isUploading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');
      final userData = jsonDecode(userDataString!);
      final userId = int.tryParse(userData['id'].toString());

      final uri = Uri.parse(
          '${kApiBaseUrl}/Api2/upload_document.php');
      final request = http.MultipartRequest('POST', uri);
      request.fields['userid'] = userId.toString();
      request.fields['documenttype'] = _selectedDocumentType!;
      request.fields['documentidnumber'] = _documentNumberController.text;
      request.fields['title'] = 'Marital Status Document';

      final String imagePath = _scannedImagePath ?? _selectedImage!.path;
      final imageFile = await http.MultipartFile.fromPath('photo', imagePath);
      request.files.add(imageFile);

      final response = await request.send();
      if (response.statusCode == 200) {
        setState(() {
          _documentStatus = 'pending';
          _rejectReason = '';
          _uploadedDocumentType = _selectedDocumentType; // Save the uploaded document type
        });
        _fadeController.forward(from: 0);
        _showSuccess("Document submitted! We'll notify you once it's verified.");
      } else {
        _showError('Upload failed. Please try again.');
      }
    } catch (e) {
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
          : FadeTransition(opacity: _fadeAnimation, child: _buildContent()),
    );
  }

  Widget _buildLoadingScreen() {
    return Scaffold(
      body: Container(
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
                'Checking verification status...',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (_documentStatus) {
      case 'approved':
        return _buildApprovedScreen();
      case 'pending':
        return _buildPendingScreen();
      case 'rejected':
        return _buildRejectedScreen();
      default:
        return _buildUploadScreen();
    }
  }

  // ─── UPLOAD SCREEN ────────────────────────────────────────────────────────

  Widget _buildUploadScreen() {
    return Column(
      children: [
        _buildHeroHeader(
          title: 'Marital Status Verification',
          subtitle: 'Upload a document supporting your marital status',
          icon: Icons.family_restroom_rounded,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStepIndicator(currentStep: _getStepFromStatus()),
                const SizedBox(height: 32),
                // Show status banner if document has been uploaded
                if (_documentStatus != 'not_uploaded') ...[
                  _buildStatusBanner(),
                  const SizedBox(height: 24),
                ],
                _buildInfoBanner(),
                const SizedBox(height: 32),
                _buildSectionTitle('1. Choose Document Type'),
                const SizedBox(height: 8),
                Text(
                  _maritalStatus != null && _maritalStatus != 'Still Unmarried'
                      ? 'Upload a document supporting your "$_maritalStatus" status'
                      : 'Select the type of document you want to upload',
                  style: const TextStyle(fontSize: 14, color: Color(0xFF757575), height: 1.5),
                ),
                const SizedBox(height: 20),
                _buildDocumentTypeGrid(),
                if (_selectedDocumentType != null && (_selectedImage != null || _scannedImagePath != null)) ...[
                  const SizedBox(height: 36),
                  _buildSectionTitle('2. Document Photo'),
                  const SizedBox(height: 8),
                  const Text(
                    'Review the uploaded photo and make changes if needed',
                    style: TextStyle(fontSize: 14, color: Color(0xFF757575), height: 1.5),
                  ),
                  const SizedBox(height: 20),
                  _buildImagePreview(),
                  const SizedBox(height: 36),
                  _buildSectionTitle('3. Document Number (Optional)'),
                  const SizedBox(height: 8),
                  const Text(
                    'Enter the document number if available on your document',
                    style: TextStyle(fontSize: 14, color: Color(0xFF757575), height: 1.5),
                  ),
                  const SizedBox(height: 20),
                  _buildDocumentNumberField(),
                  const SizedBox(height: 28),
                  _buildGuidelinesCard(),
                  const SizedBox(height: 28),
                  _buildConsentCard(),
                  const SizedBox(height: 32),
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

  Widget _buildHeroHeader({
    required String title,
    required String subtitle,
    required IconData icon,
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
              GestureDetector(
                onTap: () => Navigator.pop(context),
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

  Widget _buildStepIndicator({required int currentStep}) {
    final steps = ['Select', 'Upload', 'Verified'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: List.generate(steps.length * 2 - 1, (i) {
          if (i.isOdd) {
            final stepIdx = i ~/ 2;
            return Expanded(
              child: Container(
                height: 3,
                decoration: BoxDecoration(
                  color: stepIdx <= currentStep
                      ? AppColors.primary
                      : const Color(0xFFE0E0E0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }
          final stepIdx = i ~/ 2;
          final isActive = stepIdx <= currentStep;
          final isCompleted = stepIdx < currentStep;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive
                      ? AppColors.primary
                      : const Color(0xFFE0E0E0),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [],
                ),
                child: Center(
                  child: isCompleted
                      ? const Icon(Icons.check, color: Colors.white, size: 18)
                      : Text(
                          '${stepIdx + 1}',
                          style: TextStyle(
                            color: isActive ? Colors.white : const Color(0xFF9E9E9E),
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                steps[stepIdx],
                style: TextStyle(
                  fontSize: 12,
                  color: isActive ? AppColors.primary : const Color(0xFF9E9E9E),
                  fontWeight:
                      isActive ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildInfoBanner() {
    // Different message based on document status
    String message;
    if (_documentStatus == 'rejected') {
      message = 'Your previous document was rejected. Please upload a new valid document that meets all requirements.';
    } else if (_documentStatus == 'pending') {
      message = 'Your document is under review. You can upload a different document if you made a mistake.';
    } else if (_documentStatus == 'approved') {
      message = 'Your marital status is verified. You can upload a different document if needed.';
    } else {
      message = 'Since your marital status requires verification, please upload a supporting document (e.g. death certificate, divorce decree, or court order). This is separate from your identity document.';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFCC02).withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF57F17).withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.info_outline_rounded,
              color: Color(0xFFF57F17),
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF5D4037),
                height: 1.6,
              ),
            ),
          ),
        ],
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

  Widget _buildDocumentTypeGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 0.85,
      children: _getFilteredDocumentTypes().map((doc) {
        final isSelected = _selectedDocumentType == doc['label'];
        final isUploaded = _uploadedDocumentType == doc['label'] && _documentStatus != 'not_uploaded';
        final showUploaded = isUploaded && !isSelected; // Show uploaded indicator if this was uploaded before

        return GestureDetector(
          onTap: () {
            setState(() => _selectedDocumentType = doc['label'] as String);
            // Immediately open bottom sheet to select image source
            _showImageSourceSelector();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.primary.withOpacity(0.08)
                  : showUploaded
                      ? AppColors.success.withOpacity(0.05)
                      : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected
                    ? AppColors.primary
                    : showUploaded
                        ? AppColors.success
                        : const Color(0xFFE0E0E0),
                width: isSelected || showUploaded ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: isSelected
                      ? AppColors.primary.withOpacity(0.15)
                      : showUploaded
                          ? AppColors.success.withOpacity(0.12)
                          : Colors.black.withOpacity(0.06),
                  blurRadius: isSelected || showUploaded ? 12 : 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary.withOpacity(0.1)
                        : showUploaded
                            ? AppColors.success.withOpacity(0.1)
                            : const Color(0xFFF5F5F5),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    doc['icon'] as IconData,
                    color: isSelected
                        ? AppColors.primary
                        : showUploaded
                            ? AppColors.success
                            : const Color(0xFF757575),
                    size: 28,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  doc['label'] as String,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected || showUploaded
                        ? FontWeight.w600
                        : FontWeight.w500,
                    color: isSelected
                        ? AppColors.primary
                        : showUploaded
                            ? AppColors.success
                            : const Color(0xFF212121),
                    height: 1.3,
                  ),
                ),
                if (isSelected) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check,
                        color: Colors.white, size: 12),
                  ),
                ] else if (showUploaded) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.upload_rounded,
                        color: Colors.white, size: 12),
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
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
          hintStyle: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 14),
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

  Widget _buildPhotoUploadArea() {
    if (_selectedImage != null || _scannedImagePath != null) {
      return _buildImagePreview();
    }
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
              style: TextStyle(fontSize: 14, color: Color(0xFF757575), height: 1.4)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
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

  Widget _buildGuidelinesCard() {
    final guidelines = [
      {'icon': Icons.wb_sunny_outlined, 'text': 'Use good, even lighting'},
      {
        'icon': Icons.center_focus_strong_outlined,
        'text': 'All four corners must be visible'
      },
      {
        'icon': Icons.text_fields_rounded,
        'text': 'All text must be clearly readable'
      },
      {
        'icon': Icons.block_rounded,
        'text': 'No glare, blur, or obstruction'
      },
    ];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBBDEFB)),
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
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.lightbulb_outline_rounded,
                  color: Color(0xFF1565C0),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Photo Tips',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1565C0),
                ),
              ),
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
                      child: Icon(
                        g['icon'] as IconData,
                        size: 16,
                        color: const Color(0xFF1976D2),
                      ),
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
                            height: 1.4,
                          ),
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
          boxShadow: [
            BoxShadow(
              color: _hasConsented
                  ? AppColors.success.withOpacity(0.1)
                  : Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
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
                  fontSize: 14,
                  color: Color(0xFF424242),
                  height: 1.6,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: _isUploading
            ? []
            : [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: ElevatedButton(
        onPressed: _isUploading ? null : _validateAndSubmit,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          disabledBackgroundColor: AppColors.primary.withOpacity(0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
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
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  ),
                  SizedBox(width: 14),
                  Text(
                    'Uploading...',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              )
            : const Text(
                'Submit for Verification',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }

  // ─── PENDING SCREEN ───────────────────────────────────────────────────────

  Widget _buildPendingScreen() {
    return Column(
      children: [
        _buildStatusHeroHeader(
          title: 'Under Review',
          subtitle: 'Our team is verifying your marital document',
          icon: Icons.hourglass_top_rounded,
          color: const Color(0xFFF57C00),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _buildStepIndicator(currentStep: 1),
                const SizedBox(height: 24),
                _buildVerificationTimeline(),
                const SizedBox(height: 16),
                _buildEstimatedTimeCard(),
                const SizedBox(height: 16),
                _buildAutoRefreshNote(),
                const SizedBox(height: 24),
                _buildRefreshButton(),
                const SizedBox(height: 12),
                _buildCloseButton(),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusHeroHeader({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      color: color,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: _goToHome,
                  child: const Icon(Icons.arrow_back_ios_new,
                      color: Colors.white, size: 20),
                ),
              ),
              const SizedBox(height: 14),
              ScaleTransition(
                scale: _pulseAnimation,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: Colors.white, size: 48),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(subtitle,
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVerificationTimeline() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildTimelineItem(
            icon: Icons.cloud_upload_outlined,
            title: 'Document Submitted',
            subtitle: 'Your document has been received',
            isCompleted: true,
            isActive: false,
          ),
          _buildTimelineDivider(filled: true),
          _buildTimelineItem(
            icon: Icons.manage_search_rounded,
            title: 'Under Review',
            subtitle: 'Admin is verifying your document',
            isCompleted: false,
            isActive: true,
          ),
          _buildTimelineDivider(filled: false),
          _buildTimelineItem(
            icon: Icons.verified_rounded,
            title: 'Verification Complete',
            subtitle: "You'll be notified when done",
            isCompleted: false,
            isActive: false,
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isCompleted,
    required bool isActive,
  }) {
    final color = isCompleted
        ? AppColors.success
        : isActive
            ? const Color(0xFFF57C00)
            : const Color(0xFFBDBDBD);

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            shape: BoxShape.circle,
            border: Border.all(color: color.withOpacity(0.3), width: 1.5),
          ),
          child: Center(
            child: isCompleted
                ? Icon(Icons.check_rounded, color: color, size: 22)
                : isActive
                    ? ScaleTransition(
                        scale: _pulseAnimation,
                        child: Icon(icon, color: color, size: 22),
                      )
                    : Icon(icon, color: color, size: 22),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isActive
                      ? const Color(0xFFF57C00)
                      : const Color(0xFF212121),
                ),
              ),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
        if (isActive)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'In Progress',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFF57C00)),
            ),
          ),
      ],
    );
  }

  Widget _buildTimelineDivider({required bool filled}) {
    return Padding(
      padding: const EdgeInsets.only(left: 21),
      child: Container(
        width: 2,
        height: 22,
        color: filled
            ? AppColors.success.withOpacity(0.4)
            : Colors.grey.withOpacity(0.3),
      ),
    );
  }

  Widget _buildEstimatedTimeCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: const Color(0xFFFFCC02).withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF57C00).withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.schedule_rounded,
                color: Color(0xFFF57C00), size: 22),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Estimated Verification Time',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF424242)),
                ),
                SizedBox(height: 3),
                Text(
                  '24-48 hours on business days',
                  style:
                      TextStyle(fontSize: 12, color: Color(0xFF757575)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutoRefreshNote() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.sync_rounded, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Status is checked when you return to the app.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRefreshButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _isCheckingStatus ? null : _checkDocumentStatus,
        icon: _isCheckingStatus
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation(AppColors.primary)),
              )
            : const Icon(Icons.refresh_rounded, size: 20),
        label: const Text('Check Status Now'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: const BorderSide(color: AppColors.primary),
          foregroundColor: AppColors.primary,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Widget _buildCloseButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _goToHome,
        icon: const Icon(Icons.close_rounded, size: 20),
        label: const Text('Close'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          elevation: 3,
          shadowColor: AppColors.primary.withOpacity(0.4),
        ),
      ),
    );
  }

  // ─── APPROVED SCREEN ──────────────────────────────────────────────────────

  Widget _buildApprovedScreen() {
    return Column(
      children: [
        _buildStatusHeroHeader(
          title: 'Verified! 🎉',
          subtitle: 'Your marital status has been confirmed',
          icon: Icons.verified_rounded,
          color: const Color(0xFF2E7D32),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _buildStepIndicator(currentStep: 2),
                const SizedBox(height: 24),
                _buildApprovedCard(),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _goToHome,
                    icon: const Icon(Icons.check_rounded, size: 20),
                    label: const Text('Done'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 4,
                      shadowColor:
                          const Color(0xFF2E7D32).withOpacity(0.4),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildApprovedCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Color(0xFFE8F5E9),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.verified_rounded,
                color: Color(0xFF2E7D32), size: 52),
          ),
          const SizedBox(height: 16),
          const Text(
            'Marital Status Verified',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF212121)),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your marital status document has been approved and your profile is now fully verified.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 14, color: Color(0xFF757575), height: 1.5),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle_rounded,
                    color: Color(0xFF2E7D32), size: 22),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Your profile is now fully verified',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2E7D32)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── REJECTED SCREEN ──────────────────────────────────────────────────────

  Widget _buildRejectedScreen() {
    return Column(
      children: [
        _buildStatusHeroHeader(
          title: 'Document Rejected',
          subtitle: 'Please upload a new valid document',
          icon: Icons.cancel_rounded,
          color: const Color(0xFFC62828),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _buildStepIndicator(currentStep: 0),
                const SizedBox(height: 24),
                if (_rejectReason.isNotEmpty) ...[
                  _buildRejectionReasonCard(),
                  const SizedBox(height: 16),
                ],
                _buildRejectionTipsCard(),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _documentStatus = 'not_uploaded';
                        _selectedDocumentType = null;
                        _documentNumberController.clear();
                        _selectedImage = null;
                        _scannedImagePath = null;
                        _hasConsented = false;
                        _rejectReason = '';
                      });
                      _fadeController.forward(from: 0);
                    },
                    icon: const Icon(Icons.upload_rounded, size: 20),
                    label: const Text('Upload New Document'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 4,
                      shadowColor: AppColors.primary.withOpacity(0.4),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRejectionReasonCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5F5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFCDD2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_rounded, color: Color(0xFFC62828), size: 20),
              SizedBox(width: 8),
              Text(
                'Rejection Reason',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFC62828)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _rejectReason,
            style: const TextStyle(
                fontSize: 14, color: Color(0xFF424242), height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildRejectionTipsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBBDEFB)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tips_and_updates_rounded,
                  color: Color(0xFF1565C0), size: 20),
              SizedBox(width: 8),
              Text(
                'How to Fix',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1565C0)),
              ),
            ],
          ),
          SizedBox(height: 10),
          Text(
            '- Make sure the document is an official/legal document\n'
            '- All text and details must be clearly readable\n'
            '- Photo must show all four corners of the document\n'
            '- Avoid dark, blurry, or glare-affected photos',
            style: TextStyle(
                fontSize: 13, color: Color(0xFF424242), height: 1.7),
          ),
        ],
      ),
    );
  }

  // ─── HELPERS ─────────────────────────────────────────────────────────────

  int _getStepFromStatus() {
    switch (_documentStatus) {
      case 'pending':
        return 1;
      case 'approved':
        return 2;
      case 'rejected':
        return 0;
      default:
        return 0;
    }
  }

  Widget _buildStatusBanner() {
    Color bgColor;
    Color borderColor;
    Color iconColor;
    IconData icon;
    String title;
    String subtitle;

    switch (_documentStatus) {
      case 'pending':
        bgColor = const Color(0xFFFFF8E1);
        borderColor = const Color(0xFFF57C00);
        iconColor = const Color(0xFFF57C00);
        icon = Icons.hourglass_top_rounded;
        title = 'Document Under Review';
        subtitle = 'Your document is being verified by our team';
        break;
      case 'approved':
        bgColor = const Color(0xFFE8F5E9);
        borderColor = const Color(0xFF2E7D32);
        iconColor = const Color(0xFF2E7D32);
        icon = Icons.verified_rounded;
        title = 'Document Approved';
        subtitle = 'Your marital status has been verified successfully';
        break;
      case 'rejected':
        bgColor = const Color(0xFFFFF5F5);
        borderColor = const Color(0xFFC62828);
        iconColor = const Color(0xFFC62828);
        icon = Icons.cancel_rounded;
        title = 'Document Rejected';
        subtitle = _rejectReason.isNotEmpty ? _rejectReason : 'Please upload a new valid document';
        break;
      default:
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: iconColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF424242),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          if (_documentStatus == 'pending')
            OutlinedButton(
              onPressed: _isCheckingStatus ? null : _checkDocumentStatus,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: iconColor),
                foregroundColor: iconColor,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: _isCheckingStatus
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded, size: 18),
            ),
        ],
      ),
    );
  }

  void _goToHome() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
          builder: (context) => const MainControllerScreen()),
      (route) => false,
    );
  }

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
              const Text(
                'Choose Upload Method',
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Scan, take a photo, or choose from gallery',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
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
                child: const Text(
                  'RECOMMENDED',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
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
                    color: isRecommended
                        ? AppColors.primary
                        : Colors.black87)),
            const SizedBox(height: 4),
            Text(subtitle,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 12, color: Colors.grey)),
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

    // Show scanning feedback
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
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              SizedBox(width: 12),
              Text('Scanning document number...'),
            ],
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }

    try {
      // OCR only works on native (not web)
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
          // Show feedback when nothing is found
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.white, size: 20),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text('No document number detected. You can enter it manually below.'),
                    ),
                  ],
                ),
                backgroundColor: Colors.orange,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            );
          }
        }
      } else {
        setState(() => _isScanning = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('OCR scanning is not available on web. Please enter the document number manually.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isScanning = false);
    }
  }

  void _showScanResultDialog(String scannedText) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
              child: Text(
                'Document Scanned',
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
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
                      // "Scanned information may be incorrect. Please verify before confirming."
                      'Scanned information may be incorrect. Please verify before confirming.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[800],
                        height: 1.4,
                      ),
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

  bool _canContinue() =>
      _selectedDocumentType != null &&
      (_selectedImage != null || _scannedImagePath != null) &&
      _hasConsented;

  void _validateAndSubmit() {
    if (_selectedDocumentType == null) {
      _showError('Please select a document type');
      return;
    }
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
