import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import '../../Startup/MainControllere.dart';
import '../../constant/app_colors.dart';
import '../../service/updatepage.dart';
import '../../service/ocr_service.dart';
import '../../service/document_scanner_service.dart';
import 'package:ms2026/config/app_endpoints.dart';

class IDVerificationScreen extends StatefulWidget {
  const IDVerificationScreen({super.key});

  @override
  State<IDVerificationScreen> createState() => _IDVerificationScreenState();
}

class _IDVerificationScreenState extends State<IDVerificationScreen>
    with WidgetsBindingObserver {

  final ImagePicker _picker = ImagePicker();
  final OCRService _ocrService = OCRService();
  final DocumentScannerService _documentScanner = DocumentScannerService();
  String? _selectedDocumentType;
  final TextEditingController _documentNumberController =
      TextEditingController();
  XFile? _selectedImage;
  String? _scannedImagePath; // Path from document scanner

  String _documentStatus = 'not_uploaded';
  String _rejectReason = '';
  bool _isLoading = true;
  bool _isCheckingStatus = false;
  bool _isUploading = false;
  bool _hasConsented = false;
  bool _isScanning = false;

  // ─── Marital document state ───────────────────────────────────────────────
  /// Marital status loaded from SharedPreferences (set in PersonalDetailsPage).
  String? _maritalStatus;

  /// Tracks which required marital document types have been uploaded this session.
  /// Key: document label, Value: true when successfully uploaded.
  final Map<String, bool> _maritalDocUploaded = {};

  /// Per-document server state for marital docs (populated from API).
  /// Key: document label, Value: {status, reject_reason}
  final Map<String, Map<String, dynamic>> _maritalDocStates = {};

  /// The marital document type currently being uploaded (used while the image
  /// source bottom-sheet / upload is in progress).
  String? _activeMaritalDocType;

  /// Whether a marital document upload is in progress.
  bool _isUploadingMaritalDoc = false;

  /// Whether the identity upload form is open (user pressed "Change").
  bool _showIdentityUploadForm = false;

  /// Document type label from the last known identity document (server or upload).
  String? _identityDocType;
  // ─────────────────────────────────────────────────────────────────────────

  final List<Map<String, dynamic>> _documentTypes = [
    {'label': 'Passport', 'icon': Icons.book_outlined},
    {'label': "Driver's License", 'icon': Icons.drive_eta_outlined},
    {'label': 'National ID Card', 'icon': Icons.badge_outlined},
    {'label': 'State ID', 'icon': Icons.perm_identity_outlined},
    {'label': 'PAN Card', 'icon': Icons.credit_card_outlined},
    {'label': 'Aadhaar Card', 'icon': Icons.fingerprint},
  ];

  @override
  void initState() {
    super.initState();
    _checkDocumentStatus();
    _loadMaritalStatus();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _documentNumberController.dispose();
    _ocrService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _checkDocumentStatus();
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
        _handleNoUserData();
        return;
      }
      final userData = jsonDecode(userDataString);
      final userId = int.tryParse(userData['id'].toString());
      if (userId == null) {
        _handleNoUserId();
        return;
      }
      final response = await http.post(
        Uri.parse('${kApiBaseUrl}/Api2/check_document_status.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': userId}),
      );
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final docs = result['documents'] as List<dynamic>? ?? [];
          // Collect the labels of documents required for this user's marital status.
          final maritalDocLabels = _getRequiredMaritalDocuments()
              .map((d) => d['label'] as String)
              .toSet();

          String idStatus = 'not_uploaded';
          String idRejectReason = '';
          String idDocType = '';
          final Map<String, Map<String, dynamic>> newMaritalStates = {};

          for (final doc in docs) {
            final type = doc['documenttype'] as String? ?? '';
            final status = doc['status'] as String? ?? 'not_uploaded';
            final reason = doc['reject_reason'] as String? ?? '';

            if (maritalDocLabels.contains(type)) {
              newMaritalStates[type] = {
                'status': status,
                'reject_reason': reason,
              };
            } else {
              // Identity document: pick the highest-priority status seen so far.
              // Priority order: approved (3) > rejected (2) > pending (1) > not_uploaded (0)
              const statusPriority = {
                'approved': 3,
                'rejected': 2,
                'pending': 1,
                'not_uploaded': 0,
              };
              if ((statusPriority[status] ?? 0) >
                  (statusPriority[idStatus] ?? 0)) {
                idStatus = status;
                idRejectReason = reason;
                idDocType = type;
              }
            }
          }

          setState(() {
            _documentStatus = idStatus;
            _rejectReason = idRejectReason;
            if (idDocType.isNotEmpty) _identityDocType = idDocType;
            _maritalDocStates
              ..clear()
              ..addAll(newMaritalStates);
            // Sync boolean upload-tracking map from server states.
            for (final entry in newMaritalStates.entries) {
              _maritalDocUploaded[entry.key] =
                  entry.value['status'] != 'not_uploaded';
            }
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
    }
  }

  void _handleNoUserData() {
    setState(() {
      _isLoading = false;
      _isCheckingStatus = false;
    });
    _showError('User data not found. Please login again.');
  }

  void _handleNoUserId() {
    setState(() {
      _isLoading = false;
      _isCheckingStatus = false;
    });
  }

  // ─── Marital-document helpers ─────────────────────────────────────────────

  /// Reads the marital status that was persisted by [PersonalDetailsPage].
  /// Also restores any previously uploaded marital-document entries.
  Future<void> _loadMaritalStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final status = prefs.getString('selected_marital_status');
    final userDataString = prefs.getString('user_data');
    String? userId;
    if (userDataString != null) {
      try {
        final userData = jsonDecode(userDataString);
        userId = userData['id']?.toString();
      } catch (_) {}
    }
    if (userId != null) {
      final uploadedJson = prefs.getString('marital_docs_uploaded_$userId');
      if (uploadedJson != null) {
        try {
          final List<dynamic> uploaded = jsonDecode(uploadedJson);
          final Map<String, bool> restored = {
            for (final t in uploaded.whereType<String>()) t: true,
          };
          if (mounted) {
            setState(() {
              _maritalDocUploaded.addAll(restored);
              // Seed marital states as 'pending' so the UI shows "Under Review"
              // while _checkDocumentStatus() fetches the real state from the server.
              for (final type in restored.keys) {
                _maritalDocStates.putIfAbsent(
                  type,
                  () => {'status': 'pending', 'reject_reason': ''},
                );
              }
            });
          }
        } catch (_) {}
      }
    }
    if (mounted) setState(() => _maritalStatus = status);
  }

  /// Persists the current set of uploaded marital document types.
  Future<void> _persistMaritalDocUploaded() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('user_data');
    if (userDataString == null) return;
    try {
      final userData = jsonDecode(userDataString);
      final userId = userData['id']?.toString();
      if (userId == null) return;
      final uploadedDocTypes =
          _maritalDocUploaded.entries.where((e) => e.value).map((e) => e.key).toList();
      await prefs.setString(
          'marital_docs_uploaded_$userId', jsonEncode(uploadedDocTypes));
    } catch (_) {}
  }

  /// Returns true when the user's marital status requires supporting documents.
  bool _requiresMaritalDocuments() =>
      _maritalStatus != null && _maritalStatus != 'Still Unmarried';

  /// Returns a section title for the marital documents section that reflects
  /// the user's specific marital status.
  String _getMaritalSectionTitle() {
    switch (_maritalStatus) {
      case 'Widowed':
        return 'Widowhood Documents';
      case 'Divorced':
        return 'Divorce Documents';
      case 'Waiting Divorce':
        return 'Separation Documents';
      default:
        return 'Marital Documents';
    }
  }

  /// Returns the ordered list of document types the user must provide based on
  /// their marital status.
  List<Map<String, dynamic>> _getRequiredMaritalDocuments() {
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
        return [];
    }
  }

  /// Opens a bottom-sheet so the user can pick a source for uploading the
  /// marital document identified by [docType].
  void _showMaritalDocSourceSelector(String docType) {
    setState(() => _activeMaritalDocType = docType);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
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
            Text(
              'Upload "$docType"',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Choose how you want to provide this document',
              style: TextStyle(fontSize: 13, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            _buildSourceOption(
              icon: Icons.document_scanner_rounded,
              label: 'Scan Document',
              subtitle: 'Auto edge detection',
              isRecommended: true,
              onTap: () async {
                Navigator.pop(context);
                await _scanAndUploadMaritalDoc(docType);
              },
            ),
            const SizedBox(height: 12),
            _buildSourceOption(
              icon: Icons.photo_library_rounded,
              label: 'Gallery',
              subtitle: 'Choose existing photo',
              onTap: () async {
                Navigator.pop(context);
                await _galleryUploadMaritalDoc(docType);
              },
            ),
            const SizedBox(height: 12),
            _buildSourceOption(
              icon: Icons.camera_alt_rounded,
              label: 'Camera',
              subtitle: 'Take a new photo',
              onTap: () async {
                Navigator.pop(context);
                await _cameraUploadMaritalDoc(docType);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _scanAndUploadMaritalDoc(String docType) async {
    try {
      final scannedPaths = await _documentScanner.scanDocument(
        numberOfPages: 1,
        allowGallery: true,
      );
      if (scannedPaths != null && scannedPaths.isNotEmpty) {
        await _uploadMaritalDocument(docType, scannedPaths.first);
      }
    } catch (e) {
      _showError('Failed to scan document: $e');
    }
  }

  Future<void> _galleryUploadMaritalDoc(String docType) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 90,
      );
      if (image != null) await _uploadMaritalDocument(docType, image.path);
    } catch (e) {
      _showError('Failed to select image: $e');
    }
  }

  Future<void> _cameraUploadMaritalDoc(String docType) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 90,
      );
      if (image != null) await _uploadMaritalDocument(docType, image.path);
    } catch (e) {
      _showError('Failed to take photo: $e');
    }
  }

  /// Uploads a marital-status supporting document to the server.
  Future<void> _uploadMaritalDocument(String docType, String imagePath) async {
    if (!mounted) return;
    setState(() => _isUploadingMaritalDoc = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');
      if (userDataString == null) {
        _showError('User data not found. Please login again.');
        return;
      }
      final userData = jsonDecode(userDataString);
      final userId = int.tryParse(userData['id'].toString());
      if (userId == null) {
        _showError('Invalid user data.');
        return;
      }

      final uri = Uri.parse('${kApiBaseUrl}/Api2/upload_document.php');
      final request = http.MultipartRequest('POST', uri);
      request.fields['userid'] = userId.toString();
      request.fields['documenttype'] = docType;
      request.fields['documentidnumber'] = '';
      request.fields['title'] = 'Marital Status Document - $docType';

      final imageFile = await http.MultipartFile.fromPath('photo', imagePath);
      request.files.add(imageFile);

      final response = await request.send();
      if (!mounted) return;
      if (response.statusCode == 200) {
        setState(() {
          _maritalDocUploaded[docType] = true;
          // Optimistically mark as pending so the UI reflects the upload
          // immediately while the server processes it.
          _maritalDocStates[docType] = {
            'status': 'pending',
            'reject_reason': '',
          };
        });
        await _persistMaritalDocUploaded();
        _showSuccess('"$docType" uploaded successfully!');
      } else {
        _showError('Upload failed for "$docType". Please try again.');
      }
    } catch (e) {
      _showError('Error uploading document. Check your connection.');
    } finally {
      if (mounted) setState(() => _isUploadingMaritalDoc = false);
    }
  }
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _uploadDocument() async {
    setState(() => _isUploading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');
      final userData = jsonDecode(userDataString!);
      final userId = int.tryParse(userData['id'].toString());

      final uri =
          Uri.parse('${kApiBaseUrl}/Api2/upload_document.php');
      final request = http.MultipartRequest('POST', uri);
      request.fields['userid'] = userId.toString();
      request.fields['documenttype'] = _selectedDocumentType!;
      request.fields['documentidnumber'] = _documentNumberController.text;

      // Use scanned image path if available, otherwise use selected image
      final String imagePath = _scannedImagePath ?? _selectedImage!.path;
      final imageFile = await http.MultipartFile.fromPath('photo', imagePath);
      request.files.add(imageFile);

      final response = await request.send();
      if (response.statusCode == 200) {
        setState(() {
          _documentStatus = 'pending';
          _rejectReason = '';
          _identityDocType = _selectedDocumentType;
          _showIdentityUploadForm = false;
        });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      resizeToAvoidBottomInset: true,
      body: _isLoading
          ? _buildLoadingScreen()
          : _buildContent(),
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
                'Checking your verification status...',
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

  Widget _buildContent() => _buildKYCScreen();

  // ─── UNIFIED KYC SCREEN ──────────────────────────────────────────────────

  Widget _buildKYCScreen() {
    return Column(
      children: [
        _buildHeroHeader(
          title: 'Identity Verification',
          subtitle: 'Upload your documents to complete verification',
          icon: Icons.verified_user_rounded,
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _checkDocumentStatus,
            color: AppColors.primary,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Identity Document Section ──
                  _buildSectionTitle('1. Identity Document'),
                  const SizedBox(height: 12),
                  _buildIdentityDocSection(),

                  // ── Marital Documents Section (if required) ──
                  if (_requiresMaritalDocuments()) ...[
                    const SizedBox(height: 28),
                    const Divider(thickness: 1, color: Color(0xFFEEEEEE)),
                    const SizedBox(height: 24),
                    _buildMaritalDocumentsSection(),
                  ],

                  // ── Continue button (all required docs submitted) ──
                  if (_canProceed()) ...[
                    const SizedBox(height: 32),
                    _buildContinueButton(),
                  ],

                  const SizedBox(height: 12),
                  _buildSkipButton(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Marital documents section ────────────────────────────────────────────

  Widget _buildMaritalDocumentsSection() {
    final docs = _getRequiredMaritalDocuments();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('2. ${_getMaritalSectionTitle()}'),
        const SizedBox(height: 6),
        Text(
          'Since your marital status is "$_maritalStatus", upload all the documents listed below.',
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF757575),
            height: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8E1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFFE082)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Icon(Icons.info_outline_rounded,
                  color: Color(0xFFF57C00), size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Upload all the documents below to verify your marital status. Tap a document tile to upload.',
                  style: TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFF795548),
                      height: 1.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ...docs.map((doc) => _buildMaritalDocItem(
              label: doc['label'] as String,
              icon: doc['icon'] as IconData,
            )),
      ],
    );
  }

  Widget _buildMaritalDocItem({
    required String label,
    required IconData icon,
  }) {
    // Read the real server-side state; fall back to not_uploaded.
    final stateInfo = _maritalDocStates[label] ??
        {'status': 'not_uploaded', 'reject_reason': ''};
    final status = stateInfo['status'] as String? ?? 'not_uploaded';
    final rejectReason = stateInfo['reject_reason'] as String? ?? '';
    final isUploading =
        _isUploadingMaritalDoc && _activeMaritalDocType == label;

    // Resolve colours and labels for each state.
    final Color cardColor;
    final Color borderColor;
    final Color iconBgColor;
    final Color iconColor;
    final String statusLabel;

    switch (status) {
      case 'approved':
        cardColor = const Color(0xFFE8F5E9);
        borderColor = AppColors.success;
        iconBgColor = AppColors.success.withOpacity(0.15);
        iconColor = AppColors.success;
        statusLabel = 'Verified';
        break;
      case 'rejected':
        cardColor = const Color(0xFFFFF5F5);
        borderColor = const Color(0xFFC62828).withOpacity(0.5);
        iconBgColor = const Color(0xFFC62828).withOpacity(0.1);
        iconColor = const Color(0xFFC62828);
        statusLabel = 'Rejected';
        break;
      case 'pending':
        cardColor = const Color(0xFFFFF8E1);
        borderColor = const Color(0xFFF57C00).withOpacity(0.4);
        iconBgColor = const Color(0xFFF57C00).withOpacity(0.1);
        iconColor = const Color(0xFFF57C00);
        statusLabel = 'Under Review';
        break;
      default:
        cardColor = const Color(0xFFFAFAFA);
        borderColor = AppColors.primary.withOpacity(0.3);
        iconBgColor = AppColors.primary.withOpacity(0.08);
        iconColor = AppColors.primary;
        statusLabel = 'Upload Required';
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: borderColor,
          width: status == 'approved' ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
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
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: status == 'approved'
                            ? const Color(0xFF2E7D32)
                            : const Color(0xFF212121),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (status == 'approved') ...[
                          const Icon(Icons.verified_rounded,
                              size: 13, color: AppColors.success),
                          const SizedBox(width: 4),
                        ] else if (status == 'rejected') ...[
                          const Icon(Icons.cancel_rounded,
                              size: 13, color: Color(0xFFC62828)),
                          const SizedBox(width: 4),
                        ] else if (status == 'pending') ...[
                          const Icon(Icons.hourglass_top_rounded,
                              size: 13, color: Color(0xFFF57C00)),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          statusLabel,
                          style: TextStyle(
                            fontSize: 12,
                            color: iconColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isUploading)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                )
              else if (status == 'approved')
                Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_rounded,
                      color: Colors.white, size: 16),
                )
              else if (status != 'pending')
                // Show upload/re-upload button for not_uploaded and rejected states.
                GestureDetector(
                  onTap: () => _showMaritalDocSourceSelector(label),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: status == 'rejected'
                          ? const Color(0xFFC62828)
                          : null,
                      gradient: status == 'rejected'
                          ? null
                          : AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      status == 'rejected' ? 'Re-upload' : 'Upload',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          // Show rejection reason below the row when applicable.
          if (status == 'rejected' && rejectReason.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFFCDD2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_rounded,
                      color: Color(0xFFC62828), size: 14),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      rejectReason,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF424242),
                        height: 1.4,
                      ),
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
  // ─────────────────────────────────────────────────────────────────────────

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
              Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back_ios_new,
                        color: Colors.white, size: 20),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _skipVerification,
                    icon: const Icon(Icons.skip_next_rounded,
                        color: Colors.white70, size: 18),
                    label: const Text('Skip',
                        style:
                            TextStyle(color: Colors.white70, fontSize: 13)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
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
                  fontSize: 24,
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

  Widget _buildDocumentTypeGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 0.95,
      children: _documentTypes.map((doc) {
        final isSelected = _selectedDocumentType == doc['label'];
        return GestureDetector(
          onTap: () {
            setState(() => _selectedDocumentType = doc['label'] as String);
            // Immediately open bottom sheet to select image source
            _showImageSourceSelector();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.primary.withOpacity(0.08)
                  : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? AppColors.primary
                    : const Color(0xFFE0E0E0),
                width: isSelected ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: isSelected
                      ? AppColors.primary.withOpacity(0.18)
                      : Colors.black.withOpacity(0.04),
                  blurRadius: isSelected ? 8 : 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  doc['icon'] as IconData,
                  color: isSelected ? AppColors.primary : Colors.grey,
                  size: 28,
                ),
                const SizedBox(height: 6),
                Text(
                  doc['label'] as String,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: isSelected
                        ? AppColors.primary
                        : const Color(0xFF616161),
                    height: 1.2,
                  ),
                ),
                if (isSelected) ...[
                  const SizedBox(height: 5),
                  Container(
                    width: 18,
                    height: 18,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check,
                        color: Colors.white, size: 11),
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
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 3),
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
              hintText: 'Enter document number',
              hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
              prefixIcon: Container(
                margin: const EdgeInsets.all(10),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.numbers_rounded,
                    color: AppColors.primary, size: 18),
              ),
              suffixIcon: (_selectedImage != null || _scannedImagePath != null)
                  ? _isScanning
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                            ),
                          ),
                        )
                      : IconButton(
                          icon: const Icon(Icons.document_scanner_rounded,
                              color: AppColors.primary),
                          tooltip: 'Scan document ID',
                          onPressed: _scanDocumentId,
                        )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImagePreview() {
    return Column(
      children: [
        Container(
          height: 220,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.success, width: 2),
            boxShadow: [
              BoxShadow(
                color: AppColors.success.withOpacity(0.15),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              children: [
                // Display scanned image or selected image
                if (_scannedImagePath != null)
                  kIsWeb
                      ? FutureBuilder(
                          future: XFile(_scannedImagePath!).readAsBytes(),
                          builder: (context, snapshot) => snapshot.hasData
                              ? Image.memory(snapshot.data!,
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
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.success,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle,
                            color: Colors.white, size: 14),
                        SizedBox(width: 4),
                        Text('Photo Ready',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _showImageSourceSelector,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Change'),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFE0E0E0)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _removeImage,
                icon: const Icon(Icons.delete_outline_rounded,
                    size: 18, color: Colors.red),
                label: const Text('Remove',
                    style: TextStyle(color: Colors.red)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBBDEFB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.lightbulb_outline_rounded,
                  color: Color(0xFF1565C0), size: 20),
              SizedBox(width: 8),
              Text(
                'Photo Tips',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1565C0)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...guidelines.map((g) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(g['icon'] as IconData,
                        size: 16, color: const Color(0xFF1976D2)),
                    const SizedBox(width: 10),
                    Text(
                      g['text'] as String,
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF424242)),
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
                'I consent to use of this document solely for identity verification. It will remain confidential and will not be shared with third parties.',
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

  Widget _buildInfoBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withOpacity(0.08),
            AppColors.primary.withOpacity(0.03)
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline_rounded,
              color: AppColors.primary, size: 20),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Select a document type above to continue with your verification.',
              style: TextStyle(
                  fontSize: 13, color: AppColors.primary, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    final canSubmit = _canContinue() && !_isUploading;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isUploading ? null : _validateAndSubmit,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          disabledBackgroundColor: AppColors.primary.withOpacity(0.5),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          elevation: canSubmit ? 4 : 0,
          shadowColor: AppColors.primary.withOpacity(0.4),
        ),
        child: _isUploading
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5),
                  ),
                  SizedBox(width: 12),
                  Text('Uploading...',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                ],
              )
            : const Text(
                'Submit for Verification',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
      ),
    );
  }

  Widget _buildSkipButton() {
    return Center(
      child: TextButton.icon(
        onPressed: _skipVerification,
        icon: const Icon(Icons.arrow_forward_ios_rounded,
            size: 13, color: Colors.grey),
        label: const Text(
          'Skip for now — verify later',
          style: TextStyle(fontSize: 13, color: Colors.grey),
        ),
      ),
    );
  }

  // ─── IDENTITY DOCUMENT SECTION ───────────────────────────────────────────

  /// Decides whether to show the upload form or a status card for the identity doc.
  Widget _buildIdentityDocSection() {
    final showForm = _documentStatus == 'not_uploaded' ||
        _showIdentityUploadForm ||
        _documentStatus == 'rejected';

    if (showForm) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Rejection banner above form when doc was rejected
          if (_documentStatus == 'rejected' && _rejectReason.isNotEmpty) ...[
            _buildIdentityRejectionBanner(_rejectReason),
            const SizedBox(height: 16),
          ],
          _buildSectionTitle('Select Document Type'),
          const SizedBox(height: 4),
          const Text(
            'Tap a document type to upload',
            style: TextStyle(fontSize: 13, color: Color(0xFF757575), height: 1.4),
          ),
          const SizedBox(height: 16),
          _buildDocumentTypeGrid(),
          if (_selectedDocumentType != null &&
              (_selectedImage != null || _scannedImagePath != null)) ...[
            const SizedBox(height: 28),
            _buildSectionTitle('Document Photo'),
            const SizedBox(height: 4),
            const Text(
              'Review and edit if needed',
              style: TextStyle(fontSize: 13, color: Color(0xFF757575), height: 1.4),
            ),
            const SizedBox(height: 16),
            _buildImagePreview(),
            const SizedBox(height: 28),
            _buildSectionTitle('Document Number'),
            const SizedBox(height: 4),
            const Text(
              'Enter your document identification number',
              style: TextStyle(fontSize: 13, color: Color(0xFF757575), height: 1.4),
            ),
            const SizedBox(height: 16),
            _buildDocumentNumberField(),
            const SizedBox(height: 24),
            _buildGuidelinesCard(),
            const SizedBox(height: 24),
            _buildConsentCard(),
            const SizedBox(height: 28),
            _buildSubmitButton(),
          ] else ...[
            const SizedBox(height: 16),
            _buildInfoBanner(),
          ],
          // Cancel button when user is changing an already-uploaded doc
          if (_showIdentityUploadForm && _documentStatus != 'not_uploaded') ...[
            const SizedBox(height: 16),
            Center(
              child: TextButton.icon(
                onPressed: () => setState(() {
                  _showIdentityUploadForm = false;
                  _selectedDocumentType = null;
                  _selectedImage = null;
                  _scannedImagePath = null;
                  _hasConsented = false;
                  _documentNumberController.clear();
                }),
                icon: const Icon(Icons.close, size: 16, color: Colors.grey),
                label: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          ],
        ],
      );
    }

    // Status card view (pending or approved)
    switch (_documentStatus) {
      case 'approved':
        return _buildIdentityApprovedCard();
      case 'pending':
        return _buildIdentityPendingCard();
      default:
        return _buildInfoBanner();
    }
  }

  void _startIdentityChange() {
    setState(() {
      _showIdentityUploadForm = true;
      _selectedDocumentType = null;
      _selectedImage = null;
      _scannedImagePath = null;
      _hasConsented = false;
      _documentNumberController.clear();
    });
  }

  Widget _buildIdentityApprovedCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2E7D32).withOpacity(0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF2E7D32).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.verified_user_rounded,
                color: Color(0xFF2E7D32), size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _identityDocType ?? 'Identity Document',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF212121)),
                ),
                const SizedBox(height: 6),
                const Row(
                  children: [
                    Icon(Icons.verified_rounded,
                        color: Color(0xFF2E7D32), size: 16),
                    SizedBox(width: 6),
                    Text('Verified',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF2E7D32))),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _buildChangeButton(),
        ],
      ),
    );
  }

  Widget _buildIdentityPendingCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF57C00).withOpacity(0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF57C00).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.hourglass_top_rounded,
                color: Color(0xFFF57C00), size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _identityDocType ?? 'Identity Document',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF212121)),
                ),
                const SizedBox(height: 6),
                const Row(
                  children: [
                    Icon(Icons.hourglass_top_rounded,
                        color: Color(0xFFF57C00), size: 16),
                    SizedBox(width: 6),
                    Text('Under Review',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFF57C00))),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: _isCheckingStatus
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded, size: 20),
            onPressed: _isCheckingStatus ? null : _checkDocumentStatus,
            color: const Color(0xFFF57C00),
            visualDensity: VisualDensity.compact,
            tooltip: 'Refresh status',
          ),
          _buildChangeButton(),
        ],
      ),
    );
  }

  Widget _buildIdentityRejectionBanner(String reason) {
    return Container(
      padding: const EdgeInsets.all(14),
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
              Icon(Icons.cancel_rounded, color: Color(0xFFC62828), size: 18),
              SizedBox(width: 8),
              Text(
                'Identity Document Rejected',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFC62828)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(reason,
              style: const TextStyle(
                  fontSize: 13, color: Color(0xFF424242), height: 1.5)),
        ],
      ),
    );
  }

  Widget _buildChangeButton() {
    return GestureDetector(
      onTap: _startIdentityChange,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.primary.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit_outlined, color: AppColors.primary, size: 16),
            const SizedBox(width: 6),
            Text(
              'Change',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }

  // ─── CONTINUE BUTTON ──────────────────────────────────────────────────────

  /// Returns true when all required documents have been at least submitted
  /// (identity status != 'not_uploaded' and all marital docs != 'not_uploaded').
  bool _canProceed() {
    if (_documentStatus == 'not_uploaded') return false;
    if (!_requiresMaritalDocuments()) return true;
    final requiredDocs = _getRequiredMaritalDocuments();
    return requiredDocs.every((doc) {
      final label = doc['label'] as String;
      final state = _maritalDocStates[label];
      return state != null && state['status'] != 'not_uploaded';
    });
  }

  Widget _buildContinueButton() {
    final allApproved = _documentStatus == 'approved' &&
        (!_requiresMaritalDocuments() ||
            _getRequiredMaritalDocuments().every((doc) {
              final state = _maritalDocStates[doc['label'] as String];
              return state?['status'] == 'approved';
            }));

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: allApproved ? _completeRegistration : _goToHome,
        icon: Icon(
            allApproved
                ? Icons.check_circle_rounded
                : Icons.home_rounded,
            size: 20),
        label: Text(allApproved ? 'Continue to App' : 'Go to Home'),
        style: ElevatedButton.styleFrom(
          backgroundColor:
              allApproved ? const Color(0xFF2E7D32) : AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 4,
          shadowColor: (allApproved
                  ? const Color(0xFF2E7D32)
                  : AppColors.primary)
              .withOpacity(0.4),
        ),
      ),
    );
  }

  // ─── SHARED HELPERS ───────────────────────────────────────────────────────

  void _showImageSourceSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(24)),
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
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Scan, take a photo, or choose from gallery',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              // Document Scanner option (recommended)
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
              // Gallery option
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
              // Camera option
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                gradient: isRecommended
                    ? AppColors.primaryGradient
                    : null,
                color: isRecommended ? null : const Color(0xFF9E9E9E),
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
          _selectedImage = null; // Clear any previously selected image
        });
        // Auto-scan document ID after scanning
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
          _scannedImagePath = null; // Clear any previously scanned image
        });
        // Auto-scan after image selection
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
          _scannedImagePath = null; // Clear any previously scanned image
        });
        // Auto-scan after image capture
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
    if (_selectedImage == null && _scannedImagePath == null) {
      _showError('Please upload a document image first');
      return;
    }

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
        final String? extractedText = await _ocrService.extractDocumentId(imageFile);
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
        _showError('OCR scanning is not available on web. Please enter the document number manually.');
      }
    } catch (e) {
      setState(() => _isScanning = false);
      _showError('Failed to scan document: $e');
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
              child: Text(
                'Document Scanned',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
            const Text(
              'Scanned Document Number:',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.primary.withOpacity(0.3)),
              ),
              child: SelectableText(
                scannedText,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Please verify this is correct before continuing.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                height: 1.4,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.grey),
            ),
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
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text('Use This Number'),
          ),
        ],
      ),
    );
  }


  bool _canContinue() =>
      _selectedDocumentType != null &&
      _documentNumberController.text.isNotEmpty &&
      (_selectedImage != null || _scannedImagePath != null) &&
      _hasConsented;

  void _validateAndSubmit() {
    if (_selectedDocumentType == null) {
      _showError('Please select a document type');
      return;
    }
    if (_documentNumberController.text.isEmpty) {
      _showError('Please enter your document number');
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

  void _skipVerification() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text('Skip Verification?',
            style:
                TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        content: const Text(
          'You can verify your identity later from your profile. Some features may be limited until verified.',
          style: TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _goToHome();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Skip',
                style: TextStyle(color: Colors.white)),
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

  void _completeRegistration() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('user_data');
    if (userDataString != null) {
      final userData = jsonDecode(userDataString);
      final userId = int.tryParse(userData['id'].toString());
      if (userId != null) {
        await UpdateService.updatePageNumber(
            userId: userId.toString(), pageNo: 10);
      }
    }
    _goToHome();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
      backgroundColor: AppColors.error,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(
        children: [
          const Icon(Icons.check_circle_outline, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
      backgroundColor: AppColors.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10)),
    ));
  }
}
