import 'package:adminmrz/users/userdetails/userdetailprovider.dart';
import 'package:adminmrz/document/docprovider/docmodel.dart';
import 'package:adminmrz/document/docprovider/docservice.dart';
import 'package:adminmrz/config/profile_constants.dart';
import 'user_package_section.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'detailmodel.dart';
import 'userdetailservice.dart' show ProfileFieldOption;

class _BulkFieldConfig {
  final String key;
  final String label;
  final String apiField;
  final String section;
  final String initial;
  final TextInputType inputType;
  final bool multiline;

  /// Plain-string static options (value == label). Used for text-stored fields.
  final List<String>? staticOptions;

  /// Keyed static options (value â‰  label). Used for ID-stored fields such as
  /// [maritalStatusId] where the DB column holds a foreign-key integer but the
  /// UI must show a human-readable name. Backed by [ProfileFieldOption].
  final List<ProfileFieldOption>? staticLabeledOptions;

  const _BulkFieldConfig({
    required this.key,
    required this.label,
    required this.apiField,
    required this.section,
    required this.initial,
    this.inputType = TextInputType.text,
    this.multiline = false,
    this.staticOptions,
    this.staticLabeledOptions,
  });
}

String _cleanInitial(String value) {
  if (value == 'Not available' || value == 'null') return '';
  return value;
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ colour palette â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
const _kPrimary = Color(0xFF6366F1); // indigo-500
const _kPrimaryDark = Color(0xFF4F46E5);
const _kViolet = Color(0xFF8B5CF6);
const _kEmerald = Color(0xFF10B981);
const _kAmber = Color(0xFFF59E0B);
const _kRose = Color(0xFFEF4444);
const _kSky = Color(0xFF0EA5E9);
const _kPersonal = _kPrimary;
const _kEducation = _kEmerald;
const _kFamily = _kViolet;
const _kLifestyle = _kAmber;
const _kPartner = Color(0xFFDB2777);
const _kDocs = _kSky;
const _kPageBg = Color(0xFFF1F5F9);

class UserDetailsScreen extends StatefulWidget {
  final int userId;
  final int myId;
  final void Function(int userId)? onOpenChat;
  final String? email;
  final String? phone;
  final String? whatsapp;

  const UserDetailsScreen({
    super.key,
    required this.userId,
    required this.myId,
    this.onOpenChat,
    this.email,
    this.phone,
    this.whatsapp,
  });

  @override
  State<UserDetailsScreen> createState() => _UserDetailsScreenState();
}

class _UserDetailsScreenState extends State<UserDetailsScreen> {
  UserDetailsProvider? _detailsProvider;
  DocumentsProvider? _documentsProvider;
  bool _depsCached = false;

  String? _editingKey;
  String? _editingDropdownValue;
  final TextEditingController _editCtrl = TextEditingController();
  final TextEditingController _rejectDocCtrl = TextEditingController();
  final TextEditingController _notifTitleCtrl = TextEditingController();
  final TextEditingController _notifBodyCtrl = TextEditingController();
  bool _isSaving = false;
  final ScrollController _pageScrollController = ScrollController();

  final GlobalKey _documentsKey = GlobalKey();
  final GlobalKey _galleryKey = GlobalKey();
  final GlobalKey _personalKey = GlobalKey();
  final GlobalKey _educationKey = GlobalKey();
  final GlobalKey _familyKey = GlobalKey();
  final GlobalKey _lifestyleKey = GlobalKey();
  final GlobalKey _partnerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _detailsProvider?.fetchUserDetails(widget.userId, widget.myId);
      // Load documents for this user if not yet initialized
      final docProvider = _documentsProvider;
      if (docProvider == null) return;
      if (!docProvider.isInitialized && !docProvider.isLoading) {
        docProvider.fetchDocuments();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_depsCached) return;
    _detailsProvider = context.read<UserDetailsProvider>();
    _documentsProvider = context.read<DocumentsProvider>();
    _depsCached = true;
  }

  @override
  void dispose() {
    _detailsProvider?.clearData();
    _pageScrollController.dispose();
    _editCtrl.dispose();
    _rejectDocCtrl.dispose();
    _notifTitleCtrl.dispose();
    _notifBodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _scrollToSection(GlobalKey key) async {
    final ctx = key.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      alignment: 0.02,
    );
  }

  Widget _quickJumpChip({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withOpacity(0.24)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickJumpBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick Jump',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade700,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _quickJumpChip(
                label: 'Documents',
                icon: Icons.description_outlined,
                color: _kDocs,
                onTap: () => _scrollToSection(_documentsKey),
              ),
              _quickJumpChip(
                label: 'Gallery',
                icon: Icons.photo_library_outlined,
                color: _kViolet,
                onTap: () => _scrollToSection(_galleryKey),
              ),
              _quickJumpChip(
                label: 'Personal',
                icon: Icons.person_outline,
                color: _kPersonal,
                onTap: () => _scrollToSection(_personalKey),
              ),
              _quickJumpChip(
                label: 'Education',
                icon: Icons.school_outlined,
                color: _kEducation,
                onTap: () => _scrollToSection(_educationKey),
              ),
              _quickJumpChip(
                label: 'Family',
                icon: Icons.family_restroom_outlined,
                color: _kFamily,
                onTap: () => _scrollToSection(_familyKey),
              ),
              _quickJumpChip(
                label: 'Lifestyle',
                icon: Icons.self_improvement_outlined,
                color: _kLifestyle,
                onTap: () => _scrollToSection(_lifestyleKey),
              ),
              _quickJumpChip(
                label: 'Partner',
                icon: Icons.favorite_border,
                color: _kPartner,
                onTap: () => _scrollToSection(_partnerKey),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // â”€â”€ edit helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  // Returns true for fields whose options come from the backend master-data API.
  // are NOT in here â€” those use staticOptions / staticLabeledOptions instead.
  bool _usesLookupDropdown(String apiField) {
    return apiField == 'religionId' ||
        apiField == 'communityId' ||
        apiField == 'subCommunityId' ||
        apiField == 'annualincome' ||
        apiField == 'educationtype' ||
        apiField == 'degree' ||
        apiField == 'faculty' ||
        apiField == 'educationmedium' ||
        apiField == 'occupationtype' ||
        apiField == 'workingwith';
  }

  void _startEdit(
    String key,
    String currentValue, {
    required String apiField,
    String? editValue,
    int? religionId,
    int? communityId,
    List<String>? staticOptions,
    List<ProfileFieldOption>? staticLabeledOptions,
  }) {
    final isLookup = _usesLookupDropdown(apiField);
    final hasStatic = staticOptions != null && staticOptions.isNotEmpty;
    final hasLabeled =
        staticLabeledOptions != null && staticLabeledOptions.isNotEmpty;
    setState(() {
      _editingKey = key;
      _editingDropdownValue = null;
      _editCtrl.text =
          (currentValue == 'Not available' || currentValue == 'null')
          ? ''
          : currentValue;
      if (isLookup || hasStatic || hasLabeled) {
        final seed = (editValue ?? '').trim();
        _editingDropdownValue = seed.isEmpty ? null : seed;
      }
    });

    if (isLookup) {
      context.read<UserDetailsProvider>().ensureFieldOptions(
        field: apiField,
        religionId: religionId,
        communityId: communityId,
      );
    }
  }

  void _cancelEdit() {
    setState(() {
      _editingKey = null;
      _editingDropdownValue = null;
      _editCtrl.clear();
    });
  }

  Future<void> _saveEdit(
    String key,
    String section,
    String apiField, {
    String? overrideValue,
  }) async {
    final newValue = (overrideValue ?? _editCtrl.text).trim();
    setState(() => _isSaving = true);

    final ok = await context.read<UserDetailsProvider>().updateField(
      section: section,
      field: apiField,
      value: newValue,
    );

    setState(() {
      _isSaving = false;
      _editingKey = null;
      _editingDropdownValue = null;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok ? 'Updated successfully' : 'Update failed â€” please try again',
          ),
          backgroundColor: ok ? Colors.green.shade700 : Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _handlePhotoAction(String action) async {
    final prov = context.read<UserDetailsProvider>();
    String? reason;
    if (action == 'reject') {
      _rejectDocCtrl.clear();
      final res = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Reject Profile Photo'),
          content: TextField(
            controller: _rejectDocCtrl,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'Reason for rejection'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.pop(context, _rejectDocCtrl.text.trim()),
              style: ElevatedButton.styleFrom(backgroundColor: _kRose),
              child: const Text('Reject'),
            ),
          ],
        ),
      );
      if (res == null) return;
      reason = res;
      if (reason.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Please provide a rejection reason'),
            backgroundColor: _kRose,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
        return;
      }
    }

    final ok = await prov.handleProfilePhotoRequest(
      action: action,
      reason: reason,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Photo ${action == 'approve' ? 'approved' : 'rejected'}'
                : 'Action failed',
          ),
          backgroundColor: ok
              ? (action == 'approve' ? _kEmerald : _kRose)
              : Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  Future<void> _requestPhotoUpload(PersonalDetail p) async {
    if (!mounted) return;
    final prov = context.read<UserDetailsProvider>();
    final ok = await prov.sendAdminNotification(
      title: 'Please upload your profile photo',
      message:
          'Hi ${p.firstName}, please upload a clear profile photo so our team can verify and approve your profile faster.',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Upload request sent to user' : 'Failed to send request',
        ),
        backgroundColor: ok ? _kPrimary : _kRose,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Future<void> _showSendNotificationDialog() async {
    _notifTitleCtrl.clear();
    _notifBodyCtrl.clear();
    final prov = context.read<UserDetailsProvider>();
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Send Notification'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _notifTitleCtrl,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notifBodyCtrl,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Message'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: _kPrimary),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (res != true) return;
    final ok = await prov.sendAdminNotification(
      title: _notifTitleCtrl.text.trim().isEmpty
          ? 'Admin Message'
          : _notifTitleCtrl.text.trim(),
      message: _notifBodyCtrl.text.trim(),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok ? 'Notification sent' : 'Failed to send notification',
          ),
          backgroundColor: ok ? _kPrimary : Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  Future<void> _pickAndUploadProfilePhoto() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );
    if (result == null || result.files.isEmpty || !mounted) return;

    final ok = await context.read<UserDetailsProvider>().uploadProfilePhoto(
      result.files.first,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Profile photo updated' : 'Failed to update photo'),
        backgroundColor: ok ? _kEmerald : _kRose,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Future<void> _pickAndUploadGalleryPhotos() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'],
      withData: true,
    );
    if (result == null || result.files.isEmpty || !mounted) return;

    final ok = await context.read<UserDetailsProvider>().uploadGalleryPhotos(
      result.files,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Gallery photo upload success' : 'Gallery upload failed',
        ),
        backgroundColor: ok ? _kEmerald : _kRose,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Future<void> _replaceGalleryPhoto(UserGalleryPhoto photo) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'],
      withData: true,
    );
    if (result == null || result.files.isEmpty || !mounted) return;

    final ok = await context.read<UserDetailsProvider>().replaceGalleryPhoto(
      galleryId: photo.id,
      file: result.files.first,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Gallery photo replaced' : 'Failed to replace gallery photo',
        ),
        backgroundColor: ok ? _kEmerald : _kRose,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Future<void> _deleteGalleryPhoto(UserGalleryPhoto photo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete Gallery Photo'),
        content: const Text('Delete this gallery photo permanently?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kRose,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final ok = await context.read<UserDetailsProvider>().deleteGalleryPhoto(
      galleryId: photo.id,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Gallery photo deleted' : 'Failed to delete gallery photo',
        ),
        backgroundColor: ok ? _kEmerald : _kRose,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  static const _kDocTypes = [
    'Citizenship',
    'Passport',
    'Driving License',
    'National ID',
    'Voter ID',
    'Birth Certificate',
    'PAN Card',
    'Other',
  ];

  Future<void> _showUploadDocumentDialog() async {
    String? selectedDocType;
    String otherDocType = '';
    String documentNumber = '';
    bool isUploading = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: const Text('Add Document'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Upload a review-ready document with the correct type and optional number.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: Colors.blueGrey.shade600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedDocType,
                      decoration: const InputDecoration(
                        labelText: 'Document Type *',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      items: _kDocTypes
                          .map(
                            (t) => DropdownMenuItem(value: t, child: Text(t)),
                          )
                          .toList(),
                      onChanged: isUploading
                          ? null
                          : (value) => setLocal(() => selectedDocType = value),
                    ),
                    if (selectedDocType == 'Other') ...[
                      const SizedBox(height: 10),
                      TextField(
                        decoration: const InputDecoration(
                          labelText: 'Specify Type *',
                          border: OutlineInputBorder(),
                        ),
                        enabled: !isUploading,
                        onChanged: (value) => otherDocType = value,
                      ),
                    ],
                    const SizedBox(height: 10),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Document Number',
                        border: OutlineInputBorder(),
                      ),
                      enabled: !isUploading,
                      onChanged: (value) => documentNumber = value,
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _kDocs.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _kDocs.withOpacity(0.12)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline,
                            size: 16,
                            color: _kDocs,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Accepted formats: JPG, PNG, WEBP, PDF',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blueGrey.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isUploading ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                icon: isUploading
                    ? const SizedBox(
                        height: 14,
                        width: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.upload_file_outlined, size: 16),
                label: Text(isUploading ? 'Uploading...' : 'Pick & Upload'),
                style: ElevatedButton.styleFrom(backgroundColor: _kPrimary),
                onPressed: isUploading
                    ? null
                    : () async {
                        if (selectedDocType == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please select a document type'),
                              backgroundColor: _kRose,
                            ),
                          );
                          return;
                        }

                        final type = selectedDocType == 'Other'
                            ? otherDocType.trim()
                            : selectedDocType!;
                        if (type.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please specify the document type'),
                              backgroundColor: _kRose,
                            ),
                          );
                          return;
                        }

                        final pick = await FilePicker.platform.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: const [
                            'jpg',
                            'jpeg',
                            'png',
                            'webp',
                            'pdf',
                          ],
                          withData: true,
                        );
                        if (pick == null || pick.files.isEmpty) return;

                        if (!ctx.mounted) return;
                        setLocal(() => isUploading = true);
                        final ok = await context
                            .read<UserDetailsProvider>()
                            .uploadDocument(
                              documentType: type,
                              documentIdNumber: documentNumber.trim(),
                              file: pick.files.first,
                            );
                        if (!mounted || !ctx.mounted) return;
                        setLocal(() => isUploading = false);
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              ok
                                  ? 'Document uploaded for review'
                                  : 'Document upload failed',
                            ),
                            backgroundColor: ok ? _kEmerald : _kRose,
                            behavior: SnackBarBehavior.floating,
                            margin: const EdgeInsets.all(16),
                          ),
                        );
                      },
              ),
            ],
          ),
        );
      },
    );

    if (!mounted) return;
    // Refresh docs list after dialog closes (successful or not)
    context.read<DocumentsProvider>().fetchDocuments();
  }

  // â”€â”€ reusable editable row â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _row(
    String key,
    String label,
    String rawValue, {
    required String section,
    required String apiField,
    String? editValue,
    int? religionId,
    int? communityId,
    List<String>? staticOptions,
    List<ProfileFieldOption>? staticLabeledOptions,
    IconData? icon,
    bool highlight = false,
  }) {
    final displayValue = (rawValue.isEmpty || rawValue == 'null')
        ? 'â€”'
        : rawValue;
    final isEditing = _editingKey == key;
    final isLookup = _usesLookupDropdown(apiField);
    final hasStatic = staticOptions != null && staticOptions.isNotEmpty;
    final hasLabeled =
        staticLabeledOptions != null && staticLabeledOptions.isNotEmpty;
    final optionProvider = context.watch<UserDetailsProvider>();
    final options = isLookup
        ? optionProvider.fieldOptionsFor(apiField)
        : <ProfileFieldOption>[];
    final isOptionsLoading =
        isLookup && optionProvider.isFieldOptionsLoading(apiField);
    final faded = displayValue == 'Not available' || displayValue == 'â€”';

    Widget buildEditWidget() {
      // â”€â”€ Keyed static dropdown (value â‰  label, e.g. maritalStatusId) â”€â”€â”€
      if (hasLabeled) {
        final selected = _editingDropdownValue;
        final validValues = staticLabeledOptions.map((o) => o.value).toSet();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              value: selected != null && validValues.contains(selected)
                  ? selected
                  : null,
              isExpanded: true,
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: _kPrimary.withOpacity(0.4)),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(6)),
                  borderSide: BorderSide(color: _kPrimary, width: 1.5),
                ),
                isDense: true,
              ),
              hint: Text('Select $label', style: const TextStyle(fontSize: 13)),
              items: staticLabeledOptions
                  .map(
                    (o) => DropdownMenuItem<String>(
                      value: o.value,
                      child: Text(
                        o.label,
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _isSaving
                  ? null
                  : (v) => setState(() => _editingDropdownValue = v),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _btn(
                  'Save',
                  bg: _kPrimary,
                  fg: Colors.white,
                  loading: _isSaving,
                  onPressed: _isSaving || _editingDropdownValue == null
                      ? null
                      : () => _saveEdit(
                          key,
                          section,
                          apiField,
                          overrideValue: _editingDropdownValue,
                        ),
                ),
                _btn(
                  'Cancel',
                  bg: Colors.white,
                  fg: Colors.grey.shade700,
                  border: Colors.grey.shade300,
                  onPressed: _isSaving ? null : _cancelEdit,
                ),
              ],
            ),
          ],
        );
      }
      // â”€â”€ Static (hardcoded) dropdown â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      if (hasStatic) {
        final selected = _editingDropdownValue;
        final hasSelection = selected != null && selected.isNotEmpty;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              value: hasSelection && staticOptions.contains(selected)
                  ? selected
                  : null,
              isExpanded: true,
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: _kPrimary.withOpacity(0.4)),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(6)),
                  borderSide: BorderSide(color: _kPrimary, width: 1.5),
                ),
                isDense: true,
              ),
              hint: Text('Select $label', style: const TextStyle(fontSize: 13)),
              items: staticOptions
                  .map(
                    (o) => DropdownMenuItem<String>(
                      value: o,
                      child: Text(
                        o,
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _isSaving
                  ? null
                  : (v) => setState(() => _editingDropdownValue = v),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _btn(
                  'Save',
                  bg: _kPrimary,
                  fg: Colors.white,
                  loading: _isSaving,
                  onPressed: _isSaving || _editingDropdownValue == null
                      ? null
                      : () => _saveEdit(
                          key,
                          section,
                          apiField,
                          overrideValue: _editingDropdownValue,
                        ),
                ),
                _btn(
                  'Cancel',
                  bg: Colors.white,
                  fg: Colors.grey.shade700,
                  border: Colors.grey.shade300,
                  onPressed: _isSaving ? null : _cancelEdit,
                ),
              ],
            ),
          ],
        );
      }

      if (isLookup) {
        final selected = _editingDropdownValue;
        final hasSelection = selected != null && selected.isNotEmpty;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              value: hasSelection ? selected : null,
              isExpanded: true,
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: _kPrimary.withOpacity(0.4)),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(6)),
                  borderSide: BorderSide(color: _kPrimary, width: 1.5),
                ),
                isDense: true,
              ),
              hint: Text(
                isOptionsLoading ? 'Loading optionsâ€¦' : 'Select $label',
                style: const TextStyle(fontSize: 13),
              ),
              items: options
                  .map(
                    (o) => DropdownMenuItem<String>(
                      value: o.value,
                      child: Text(
                        o.label,
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (_isSaving || isOptionsLoading)
                  ? null
                  : (v) => setState(() => _editingDropdownValue = v),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _btn(
                  'Save',
                  bg: _kPrimary,
                  fg: Colors.white,
                  loading: _isSaving,
                  onPressed: _isSaving || _editingDropdownValue == null
                      ? null
                      : () => _saveEdit(
                          key,
                          section,
                          apiField,
                          overrideValue: _editingDropdownValue,
                        ),
                ),
                _btn(
                  'Cancel',
                  bg: Colors.white,
                  fg: Colors.grey.shade700,
                  border: Colors.grey.shade300,
                  onPressed: _isSaving ? null : _cancelEdit,
                ),
              ],
            ),
          ],
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 34,
            child: TextField(
              controller: _editCtrl,
              autofocus: true,
              onSubmitted: (_) => _saveEdit(key, section, apiField),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: _kPrimary.withOpacity(0.4)),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(6)),
                  borderSide: BorderSide(color: _kPrimary, width: 1.5),
                ),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _btn(
                'Save',
                bg: _kPrimary,
                fg: Colors.white,
                loading: _isSaving,
                onPressed: _isSaving
                    ? null
                    : () => _saveEdit(key, section, apiField),
              ),
              _btn(
                'Cancel',
                bg: Colors.white,
                fg: Colors.grey.shade700,
                border: Colors.grey.shade300,
                onPressed: _isSaving ? null : _cancelEdit,
              ),
            ],
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 26,
                    child: icon != null
                        ? Icon(icon, size: 15, color: Colors.blueGrey.shade300)
                        : null,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (isEditing)
                buildEditWidget()
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        displayValue,
                        style: TextStyle(
                          fontSize: 14,
                          color: faded
                              ? Colors.grey.shade400
                              : highlight
                              ? _kPrimary
                              : Colors.grey.shade900,
                          fontWeight: faded
                              ? FontWeight.w400
                              : highlight
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => _startEdit(
                        key,
                        rawValue,
                        apiField: apiField,
                        editValue: editValue,
                        religionId: religionId,
                        communityId: communityId,
                        staticOptions: staticOptions,
                        staticLabeledOptions: staticLabeledOptions,
                      ),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: Icon(
                          Icons.edit_outlined,
                          size: 13,
                          color: Colors.blueGrey.shade300,
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }

  // â”€â”€ Location picker dialog (country â†’ state â†’ city) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  void _showLocationPickerDialog({
    required String section, // 'personal' or 'partner'
    required String currentCountry,
    required String currentState,
    required String currentCity,
  }) {
    // Capture the provider from the screen context BEFORE opening the modal.
    // The modal bottom sheet creates a new route with a fresh widget tree that
    // cannot reach InheritedWidgets (like Provider) from the parent route.
    final prov = context.read<UserDetailsProvider>();
    prov.loadCountries();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        // Local mutable state declared here (outside builders) so it survives
        // rebuilds triggered by both ListenableBuilder and StatefulBuilder.
        String? selectedCountryId;
        String? selectedCountryName;
        String? selectedStateId;
        String? selectedStateName;
        String? selectedCityName;
        bool isSaving = false;
        String? error;

        // ListenableBuilder listens to the captured provider instance directly,
        // no InheritedWidget lookup needed.
        return ListenableBuilder(
          listenable: prov,
          builder: (_, __) {
            return StatefulBuilder(
              builder: (ctx2, setSheet) {
                final countries = prov.countries;
                final states = prov.states;
                final cities = prov.cities;
                final loadingC = prov.loadingCountries;
                final loadingS = prov.loadingStates;
                final loadingCi = prov.loadingCities;

                Future<void> save() async {
                  if (selectedCountryName == null) {
                    setSheet(() => error = 'Please select a country');
                    return;
                  }
                  setSheet(() {
                    isSaving = true;
                    error = null;
                  });
                  final toSave = <String, String>{
                    'country': selectedCountryName ?? '',
                    'state': selectedStateName ?? '',
                    'city': selectedCityName ?? '',
                  };
                  final filtered = <String, String>{};
                  for (final entry in toSave.entries) {
                    if (entry.value.isEmpty) continue;
                    filtered[entry.key] = entry.value;
                  }

                  final ok = await prov.updateSection(
                    section: section,
                    fields: filtered,
                  );
                  setSheet(() => isSaving = false);
                  if (ok) {
                    if (ctx2.mounted) Navigator.pop(ctx2);
                  } else {
                    setSheet(() => error = 'Failed to save location');
                  }
                }

                return Padding(
                  padding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: 24,
                    bottom: MediaQuery.of(ctx2).viewInsets.bottom + 24,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.public, color: _kPrimary, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Edit Location',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.grey.shade800,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => Navigator.pop(ctx2),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Country
                      DropdownButtonFormField<String>(
                        value: selectedCountryId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'Country',
                          prefixIcon: const Icon(Icons.public, size: 18),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        hint: loadingC
                            ? const Text('Loading...')
                            : const Text('Select Country'),
                        items: countries.map((c) {
                          return DropdownMenuItem<String>(
                            value: c['id'].toString(),
                            child: Text(
                              c['name'].toString(),
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (id) {
                          if (id == null) return;
                          final match = countries.firstWhere(
                            (c) => c['id'].toString() == id,
                            orElse: () => {},
                          );
                          selectedCountryId = id;
                          selectedCountryName = match['name']?.toString() ?? '';
                          selectedStateId = null;
                          selectedStateName = null;
                          selectedCityName = null;
                          prov.loadStatesFor(int.parse(id));
                          setSheet(() {});
                        },
                      ),
                      const SizedBox(height: 12),

                      // State
                      DropdownButtonFormField<String>(
                        value: selectedStateId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'State / Province',
                          prefixIcon: const Icon(Icons.map_outlined, size: 18),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        hint: loadingS
                            ? const Text('Loading...')
                            : selectedCountryId == null
                            ? const Text('Select country first')
                            : const Text('Select State'),
                        items: states.map((s) {
                          return DropdownMenuItem<String>(
                            value: s['id'].toString(),
                            child: Text(
                              s['name'].toString(),
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (id) {
                          if (id == null) return;
                          final match = states.firstWhere(
                            (s) => s['id'].toString() == id,
                            orElse: () => {},
                          );
                          selectedStateId = id;
                          selectedStateName = match['name']?.toString() ?? '';
                          selectedCityName = null;
                          prov.loadCitiesFor(int.parse(id));
                          setSheet(() {});
                        },
                      ),
                      const SizedBox(height: 12),

                      // City
                      DropdownButtonFormField<String>(
                        value: selectedCityName,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'City',
                          prefixIcon: const Icon(Icons.location_city, size: 18),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        hint: loadingCi
                            ? const Text('Loading...')
                            : selectedStateId == null
                            ? const Text('Select state first')
                            : const Text('Select City'),
                        items: cities.map((c) {
                          return DropdownMenuItem<String>(
                            value: c['name'].toString(),
                            child: Text(
                              c['name'].toString(),
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (name) {
                          selectedCityName = name;
                          setSheet(() {});
                        },
                      ),

                      if (error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          error!,
                          style: const TextStyle(
                            color: _kRose,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isSaving
                                  ? null
                                  : () => Navigator.pop(ctx2),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                side: const BorderSide(
                                  color: Color(0xFFE2E8F0),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: isSaving ? null : save,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _kPrimary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                elevation: 0,
                              ),
                              child: isSaving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Save Location'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _btn(
    String label, {
    required Color bg,
    required Color fg,
    Color? border,
    bool loading = false,
    VoidCallback? onPressed,
  }) => SizedBox(
    height: 30,
    child: ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        elevation: 0,
        shadowColor: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        minimumSize: const Size(52, 30),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: border != null ? BorderSide(color: border) : BorderSide.none,
        ),
      ),
      child: loading
          ? SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2, color: fg),
            )
          : Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
    ),
  );

  Widget _chipButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    Color color = _kPrimary,
    Color? bg,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg ?? color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // â”€â”€ section wrapper â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _section({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> rows,
    Widget? trailing,
  }) {
    final rowCountLabel = rows.length == 1
        ? '1 field'
        : '${rows.length} fields';
    return Container(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            color: color.withOpacity(0.05),
            child: Row(
              children: [
                Icon(icon, size: 17, color: color),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: color,
                    letterSpacing: 0.2,
                  ),
                ),
                const Spacer(),
                if (rows.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      rowCountLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
                if (trailing != null) trailing,
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columnCount = constraints.maxWidth >= 1180
                    ? 3
                    : constraints.maxWidth >= 820
                    ? 2
                    : 1;
                if (columnCount == 1) {
                  return Column(children: rows);
                }

                final children = <Widget>[];
                for (int i = 0; i < rows.length; i += columnCount) {
                  final slice = rows.skip(i).take(columnCount).toList();
                  children.add(
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (
                          int columnIndex = 0;
                          columnIndex < columnCount;
                          columnIndex++
                        ) ...[
                          Expanded(
                            child: columnIndex < slice.length
                                ? slice[columnIndex]
                                : const SizedBox.shrink(),
                          ),
                          if (columnIndex != columnCount - 1)
                            const SizedBox(width: 16),
                        ],
                      ],
                    ),
                  );
                }
                return Column(children: children);
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _activityStatCard(
    String label,
    String value,
    Color color,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.20),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.blueGrey.shade600,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _activityStatGrid(UserDetailsProvider prov) {
    final stats = prov.activityStats;
    if (prov.isLoadingActivity && stats == null) {
      return const SizedBox(
        height: 60,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final s = stats ?? ActivityStats.empty();
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _activityStatCard(
          'Requests Sent',
          '${s.requestsSent}',
          _kPrimary,
          Icons.send_rounded,
        ),
        _activityStatCard(
          'Requests Received',
          '${s.requestsReceived}',
          _kViolet,
          Icons.inbox_outlined,
        ),
        _activityStatCard(
          'Chat Sent',
          '${s.chatRequestsSent}',
          _kSky,
          Icons.chat_bubble_outline,
        ),
        _activityStatCard(
          'Chat Accepted',
          '${s.chatRequestsAccepted}',
          _kEmerald,
          Icons.check_circle_outline,
        ),
        _activityStatCard(
          'Profile Views',
          '${s.profileViews}',
          _kAmber,
          Icons.visibility_outlined,
        ),
        _activityStatCard(
          'Matches',
          '${s.matchesCount}',
          _kPartner,
          Icons.favorite_outline,
        ),
      ],
    );
  }

  Widget _statusPill(String label, Color color, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showGalleryPreview(
    List<UserGalleryPhoto> photos,
    int initialIndex,
  ) async {
    if (photos.isEmpty) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.88),
      builder: (_) => _GalleryLightbox(
        photos: photos,
        initialIndex: initialIndex.clamp(0, photos.length - 1),
      ),
    );
  }

  Widget _buildActivityStats(UserDetailsProvider prov) {
    final stats = prov.activityStats;
    if (prov.isLoadingActivity && stats == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final s = stats ?? ActivityStats.empty();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              const Text(
                'User Activity',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _kPrimary,
                ),
              ),
              if (prov.isLoadingActivity) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  height: 14,
                  width: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _activityStatCard(
                'Requests Sent',
                '${s.requestsSent}',
                _kPrimary,
                Icons.send_rounded,
              ),
              _activityStatCard(
                'Requests Received',
                '${s.requestsReceived}',
                const Color(0xFF8B5CF6),
                Icons.inbox_outlined,
              ),
              _activityStatCard(
                'Chat Sent',
                '${s.chatRequestsSent}',
                const Color(0xFF0EA5E9),
                Icons.chat_bubble_outline,
              ),
              _activityStatCard(
                'Chat Accepted',
                '${s.chatRequestsAccepted}',
                const Color(0xFF10B981),
                Icons.check_circle_outline,
              ),
              _activityStatCard(
                'Profile Views',
                '${s.profileViews}',
                const Color(0xFFF59E0B),
                Icons.visibility_outlined,
              ),
              _activityStatCard(
                'Matches',
                '${s.matchesCount}',
                const Color(0xFFDB2777),
                Icons.favorite_outline,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildAdminActions(PersonalDetail p, UserDetailsProvider prov) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Admin Actions',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(width: 8),
              if (prov.isSendingNotification || prov.isPhotoActioning)
                const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.notifications_active_outlined, size: 16),
                label: const Text('Send Notification'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
                onPressed: prov.isSendingNotification
                    ? null
                    : _showSendNotificationDialog,
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.chat_bubble_outline, size: 16),
                label: const Text('Open Chat'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kPrimary,
                  side: const BorderSide(color: _kPrimary),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
                onPressed: widget.onOpenChat != null
                    ? () => widget.onOpenChat!(widget.userId)
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _handleGalleryPhotoAction(
    UserDetailsProvider prov,
    int galleryId,
    String action,
  ) async {
    String? reason;
    if (action == 'reject') {
      _rejectDocCtrl.clear();
      final res = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Reject Gallery Photo'),
          content: TextField(
            controller: _rejectDocCtrl,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'Reason for rejection'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.pop(context, _rejectDocCtrl.text.trim()),
              style: ElevatedButton.styleFrom(backgroundColor: _kRose),
              child: const Text('Reject'),
            ),
          ],
        ),
      );

      if (res == null) return;
      reason = res;
      if (reason.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Please provide a rejection reason'),
            backgroundColor: _kRose,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
        return;
      }
    }

    final ok = await prov.handleGalleryPhotoRequest(
      galleryId: galleryId,
      action: action,
      reason: reason,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Gallery photo ${action == 'approve' ? 'approved' : 'rejected'}'
              : 'Gallery action failed',
        ),
        backgroundColor: ok
            ? (action == 'approve' ? _kEmerald : _kRose)
            : Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildGalleryReview(UserDetailsProvider prov) {
    final photos = prov.galleryPhotos;
    final pendingCount = photos.where((e) => e.isPending).length;
    final approvedCount = photos.where((e) => e.isApproved).length;
    final rejectedCount = photos.where((e) => e.isRejected).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withOpacity(0.06)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final split = constraints.maxWidth >= 980;
              final children = [
                Expanded(
                  child: Container(
                    key: _documentsKey,
                    child: _buildDocumentsSection(),
                  ),
                ),
                if (split)
                  const SizedBox(width: 12)
                else
                  const SizedBox(height: 12),
                Expanded(
                  child: Container(
                    key: _galleryKey,
                    child: _buildGalleryPhotosPartition(
                      prov,
                      pendingCount: pendingCount,
                      approvedCount: approvedCount,
                      rejectedCount: rejectedCount,
                    ),
                  ),
                ),
              ];

              return split
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: children,
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: children,
                    );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildGalleryPhotosPartition(
    UserDetailsProvider prov, {
    required int pendingCount,
    required int approvedCount,
    required int rejectedCount,
  }) {
    final photos = prov.galleryPhotos;

    Color statusColor(String status) {
      switch (status.toLowerCase()) {
        case 'approved':
          return _kEmerald;
        case 'rejected':
          return _kRose;
        default:
          return _kAmber;
      }
    }

    IconData statusIcon(String status) {
      switch (status.toLowerCase()) {
        case 'approved':
          return Icons.verified_rounded;
        case 'rejected':
          return Icons.cancel_rounded;
        default:
          return Icons.pending_outlined;
      }
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kViolet.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Gallery Photos',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              if (prov.isUploadingMedia) ...[
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
              ],
              _statusPill(
                '$pendingCount pending',
                pendingCount > 0 ? _kAmber : _kEmerald,
                icon: pendingCount > 0
                    ? Icons.pending_outlined
                    : Icons.check_circle_outline,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _miniInfoChip(
                icon: Icons.photo_library_outlined,
                label: '${photos.length} total',
                color: _kPrimary,
              ),
              _miniInfoChip(
                icon: Icons.verified_outlined,
                label: '$approvedCount approved',
                color: _kEmerald,
              ),
              _miniInfoChip(
                icon: Icons.cancel_outlined,
                label: '$rejectedCount rejected',
                color: _kRose,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (photos.isEmpty)
            InkWell(
              onTap: prov.isUploadingMedia ? null : _pickAndUploadGalleryPhotos,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 14,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _kPrimary.withOpacity(0.06),
                      _kViolet.withOpacity(0.08),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _kViolet.withOpacity(0.14)),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: prov.isUploadingMedia
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(
                              Icons.add_photo_alternate_outlined,
                              color: _kPrimary,
                              size: 24,
                            ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'No gallery photos yet',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tap to upload photos',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blueGrey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 560;
                final medium = constraints.maxWidth >= 360;
                final crossAxisCount = wide ? 5 : (medium ? 4 : 3);
                final itemCount = photos.length + 1;

                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: itemCount,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                    childAspectRatio: wide ? 0.85 : (medium ? 0.80 : 0.78),
                  ),
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return InkWell(
                        onTap: prov.isUploadingMedia
                            ? null
                            : _pickAndUploadGalleryPhotos,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                _kPrimary.withOpacity(0.06),
                                _kViolet.withOpacity(0.08),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _kViolet.withOpacity(0.16),
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: prov.isUploadingMedia
                                    ? const Padding(
                                        padding: EdgeInsets.all(12),
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.add,
                                        color: _kPrimary,
                                        size: 20,
                                      ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Add Photos',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    final photo = photos[i - 1];
                    final color = statusColor(photo.status);
                    final isActioning = prov.isGalleryActioning(photo.id);
                    return Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        children: [
                          ClipRRect(
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(10),
                              topRight: Radius.circular(10),
                            ),
                            child: InkWell(
                              onTap: photo.imageUrl.isEmpty
                                  ? null
                                  : () => _showGalleryPreview(photos, i - 1),
                              child: SizedBox(
                                height: 52,
                                width: double.infinity,
                                child: photo.imageUrl.isEmpty
                                    ? Container(
                                        color: Colors.grey.shade200,
                                        alignment: Alignment.center,
                                        child: const Icon(
                                          Icons.broken_image,
                                          color: Colors.grey,
                                        ),
                                      )
                                    : Stack(
                                        children: [
                                          Positioned.fill(
                                            child: Image.network(
                                              photo.imageUrl,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  Container(
                                                    color: Colors.grey.shade200,
                                                    alignment: Alignment.center,
                                                    child: const Icon(
                                                      Icons.broken_image,
                                                      color: Colors.grey,
                                                    ),
                                                  ),
                                            ),
                                          ),
                                          Positioned(
                                            left: 6,
                                            top: 6,
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: color.withOpacity(0.92),
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    statusIcon(photo.status),
                                                    size: 11,
                                                    color: Colors.white,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    photo.status.toUpperCase(),
                                                    style: const TextStyle(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          Positioned(
                                            top: 4,
                                            right: 4,
                                            child: PopupMenuButton<String>(
                                              tooltip: 'Photo actions',
                                              padding: EdgeInsets.zero,
                                              icon: const Icon(
                                                Icons.more_vert_rounded,
                                                size: 17,
                                                color: Colors.white,
                                              ),
                                              color: Colors.white,
                                              style: IconButton.styleFrom(
                                                backgroundColor: Colors.black45,
                                                minimumSize: const Size(26, 26),
                                              ),
                                              onSelected: (value) {
                                                switch (value) {
                                                  case 'approve':
                                                    _handleGalleryPhotoAction(
                                                      prov,
                                                      photo.id,
                                                      'approve',
                                                    );
                                                    break;
                                                  case 'reject':
                                                    _handleGalleryPhotoAction(
                                                      prov,
                                                      photo.id,
                                                      'reject',
                                                    );
                                                    break;
                                                  case 'replace':
                                                    _replaceGalleryPhoto(photo);
                                                    break;
                                                  case 'delete':
                                                    _deleteGalleryPhoto(photo);
                                                    break;
                                                }
                                              },
                                              itemBuilder: (_) => [
                                                if (photo.isPending)
                                                  const PopupMenuItem(
                                                    value: 'approve',
                                                    child: Text('Approve'),
                                                  ),
                                                if (photo.isPending)
                                                  const PopupMenuItem(
                                                    value: 'reject',
                                                    child: Text('Reject'),
                                                  ),
                                                const PopupMenuItem(
                                                  value: 'replace',
                                                  child: Text('Replace'),
                                                ),
                                                const PopupMenuItem(
                                                  value: 'delete',
                                                  child: Text('Delete'),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 3),
                          if (photo.isRejected &&
                              (photo.rejectReason ?? '').isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(6, 1, 6, 2),
                              child: Text(
                                photo.rejectReason!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 9.5,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(6, 0, 6, 5),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    photo.isPending
                                        ? 'Approve, reject, replace or delete'
                                        : 'Replace or delete',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      color: Colors.blueGrey.shade600,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (isActioning)
                                  const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
        ],
      ),
    );
  }

  // â”€â”€ profile header â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildHeader(PersonalDetail p, ContactDetail c) {
    final prov = context.watch<UserDetailsProvider>();
    final isPhotoMissing = !p.hasProfilePicture;
    final photoStatus = p.photoRequest.isNotEmpty
        ? p.photoRequest
        : (isPhotoMissing ? 'No profile photo' : 'Uploaded');
    final normalizedStatus = photoStatus.toLowerCase();
    final photoStatusColor = isPhotoMissing
        ? _kAmber
        : normalizedStatus.contains('approve')
        ? _kEmerald
        : normalizedStatus.contains('reject')
        ? _kRose
        : _kSky;
    final canReviewPhoto =
        p.hasProfilePicture &&
        !normalizedStatus.contains('approve') &&
        !normalizedStatus.contains('reject');
    final showRequestUpload =
        isPhotoMissing || normalizedStatus.contains('reject');

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: prov.isUploadingMedia
                    ? null
                    : _pickAndUploadProfilePhoto,
                borderRadius: BorderRadius.circular(999),
                child: Stack(
                  children: [
                    Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _kPrimary.withOpacity(0.25),
                          width: 3,
                        ),
                        gradient: LinearGradient(
                          colors: [
                            _kPrimary.withOpacity(0.18),
                            _kViolet.withOpacity(0.20),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: p.hasProfilePicture
                          ? Image.network(
                              p.profilePicture,
                              fit: BoxFit.cover,
                              loadingBuilder: (_, child, prog) => prog == null
                                  ? child
                                  : const Center(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                              errorBuilder: (_, __, ___) =>
                                  _buildHeaderInitial(p),
                            )
                          : _buildHeaderInitial(p),
                    ),
                    Positioned(
                      right: 2,
                      bottom: 2,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.72),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withOpacity(0.24),
                          ),
                        ),
                        child: prov.isUploadingMedia
                            ? const Padding(
                                padding: EdgeInsets.all(7),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.add,
                                color: Colors.white,
                                size: 16,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 22),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            p.fullName,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: _kPrimaryDark,
                            ),
                          ),
                        ),
                        if (prov.isPhotoActioning ||
                            prov.isSendingNotification) ...[
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                        ],
                        _statusPill(
                          photoStatus.toUpperCase(),
                          photoStatusColor,
                          icon: Icons.photo_camera_outlined,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 18,
                      runSpacing: 4,
                      children: [
                        if (p.age != null)
                          _metaChip(
                            Icons.cake,
                            '${p.age} yrs',
                            Colors.blue.shade700,
                          ),
                        _metaChip(
                          Icons.location_on,
                          p.city,
                          Colors.blue.shade700,
                        ),
                        if (p.country != 'Not available')
                          _metaChip(
                            Icons.public,
                            p.country,
                            Colors.teal.shade700,
                          ),
                        _metaChip(
                          Icons.favorite,
                          p.maritalStatusName,
                          Colors.pink.shade600,
                        ),
                        _metaChip(
                          Icons.badge,
                          'ID: ${p.memberId}',
                          Colors.grey.shade600,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _badge(
                          label: p.userType.isEmpty
                              ? 'FREE'
                              : p.userType.toUpperCase(),
                          icon: p.userType == 'paid'
                              ? Icons.workspace_premium
                              : Icons.person_outline,
                          bg: p.userType == 'paid'
                              ? _kAmber.withOpacity(0.15)
                              : Colors.grey.shade100,
                          border: p.userType == 'paid'
                              ? _kAmber.withOpacity(0.6)
                              : Colors.grey.shade300,
                          fg: p.userType == 'paid'
                              ? const Color(0xFF92400E)
                              : Colors.grey.shade700,
                        ),
                        _badge(
                          label: p.isVerified == 1
                              ? 'Verified'
                              : 'Pending Verification',
                          icon: p.isVerified == 1
                              ? Icons.verified_user
                              : Icons.pending_actions,
                          bg: p.isVerified == 1
                              ? _kEmerald.withOpacity(0.12)
                              : _kAmber.withOpacity(0.12),
                          border: p.isVerified == 1
                              ? _kEmerald.withOpacity(0.4)
                              : _kAmber.withOpacity(0.4),
                          fg: p.isVerified == 1
                              ? const Color(0xFF065F46)
                              : const Color(0xFFB45309),
                        ),
                        if (p.privacy.isNotEmpty)
                          _badge(
                            label: p.privacy,
                            icon: Icons.lock_outline,
                            bg: Colors.indigo.shade50,
                            border: Colors.indigo.shade200,
                            fg: Colors.indigo.shade800,
                          ),
                        _badge(
                          label: p.hasProfilePicture
                              ? 'Tap photo to change'
                              : 'Tap photo to upload',
                          icon: Icons.add_photo_alternate_outlined,
                          bg: _kPrimary.withOpacity(0.08),
                          border: _kPrimary.withOpacity(0.20),
                          fg: _kPrimaryDark,
                        ),
                      ],
                    ),
                    if (canReviewPhoto || showRequestUpload) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          if (canReviewPhoto)
                            ElevatedButton.icon(
                              onPressed: prov.isPhotoActioning
                                  ? null
                                  : () => _handlePhotoAction('approve'),
                              icon: const Icon(
                                Icons.check_circle_outline,
                                size: 16,
                              ),
                              label: const Text('Approve Photo'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _kEmerald,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                elevation: 0,
                              ),
                            ),
                          if (canReviewPhoto)
                            OutlinedButton.icon(
                              onPressed: prov.isPhotoActioning
                                  ? null
                                  : () => _handlePhotoAction('reject'),
                              icon: const Icon(Icons.cancel_outlined, size: 16),
                              label: const Text('Reject Photo'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _kRose,
                                side: const BorderSide(color: _kRose),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          if (showRequestUpload)
                            TextButton.icon(
                              onPressed: prov.isSendingNotification
                                  ? null
                                  : () => _requestPhotoUpload(p),
                              icon: const Icon(Icons.send_outlined, size: 16),
                              label: Text(
                                prov.isSendingNotification
                                    ? 'Sending...'
                                    : 'Request Upload',
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: _kPrimary,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 10,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    _buildContactInfo(c),
                  ],
                ),
              ),
            ],
          ),
          if (p.aboutMe.isNotEmpty && p.aboutMe != 'Not available') ...[
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'About Me',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _kPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    p.aboutMe,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.blueGrey.shade800,
                      height: 1.6,
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

  Widget _buildHeaderInitial(PersonalDetail p) {
    return Center(
      child: Text(
        (p.fullName.trim().isNotEmpty ? p.fullName.trim().substring(0, 1) : 'U')
            .toUpperCase(),
        style: const TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w800,
          color: _kPrimaryDark,
        ),
      ),
    );
  }

  Widget _metaChip(IconData icon, String label, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 13, color: color),
      const SizedBox(width: 3),
      Text(
        label,
        style: TextStyle(
          fontSize: 13,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    ],
  );

  Widget _badge({
    required String label,
    required IconData icon,
    required Color bg,
    required Color border,
    required Color fg,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: fg),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: fg,
          ),
        ),
      ],
    ),
  );

  Widget _buildContactInfo(ContactDetail c) {
    final hasAny = c.hasEmail || c.hasPhone;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueGrey.shade50),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.contact_mail_outlined,
                size: 16,
                color: _kPrimary,
              ),
              const SizedBox(width: 8),
              const Text(
                'Contact Information',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: _kPrimaryDark,
                ),
              ),
              if (!hasAny) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Missing',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.amber.shade700,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 10,
            children: [
              _contactTile(
                icon: Icons.email_outlined,
                label: 'Email',
                value: c.hasEmail ? c.email : 'Not available',
              ),
              _contactTile(
                icon: Icons.phone_outlined,
                label: 'Phone',
                value: c.hasPhone ? c.preferredPhone : 'Not available',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _contactTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final missing =
        value.isEmpty || value == 'Not available' || value == 'null';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: missing ? Colors.grey.shade50 : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: missing ? Colors.grey.shade200 : Colors.blue.shade100,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: missing ? Colors.grey.shade500 : Colors.blue.shade700,
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                missing ? 'Not available' : value,
                style: TextStyle(
                  fontSize: 13,
                  color: missing
                      ? Colors.grey.shade500
                      : Colors.blueGrey.shade900,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // â”€â”€ section builders â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildPersonal(PersonalDetail p) => _section(
    title: 'Personal Details',
    icon: Icons.person_outline,
    color: _kPersonal,
    trailing: _chipButton(
      label: 'Edit all',
      icon: Icons.edit_outlined,
      onTap: () => _openPersonalBulk(p),
      color: _kPersonal,
    ),
    rows: [
      _row(
        'p_first',
        'First Name',
        p.firstName,
        section: 'personal',
        apiField: 'firstName',
        icon: Icons.person_outline,
        highlight: true,
      ),
      _row(
        'p_last',
        'Last Name',
        p.lastName,
        section: 'personal',
        apiField: 'lastName',
        icon: Icons.person_2_outlined,
      ),
      _row(
        'p_city',
        'City',
        p.city,
        section: 'personal',
        apiField: 'city',
        icon: Icons.location_city,
      ),
      _row(
        'p_country',
        'Country',
        p.country,
        section: 'personal',
        apiField: 'country',
        icon: Icons.public,
      ),
      // Location picker button â€” opens cascading country/state/city picker
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: OutlinedButton.icon(
          icon: const Icon(Icons.edit_location_alt_outlined, size: 16),
          label: const Text('Edit Location (Country / State / City)'),
          onPressed: () => _showLocationPickerDialog(
            section: 'personal',
            currentCountry: p.country,
            currentState: '',
            currentCity: p.city,
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: _kPrimary,
            side: const BorderSide(color: _kPrimary),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
      ),
      _row(
        'p_height',
        'Height',
        p.heightName,
        section: 'personal',
        apiField: 'height_name',
        staticOptions: kHeightOptions,
        icon: Icons.height,
        highlight: true,
      ),
      _row(
        'p_dob',
        'Birth Date',
        p.birthDate,
        section: 'personal',
        apiField: 'birthDate',
        icon: Icons.cake,
      ),
      _row(
        'p_birthtime',
        'Birth Time',
        p.birthtime,
        section: 'personal',
        apiField: 'birthtime',
        icon: Icons.access_time,
      ),
      _row(
        'p_birthcity',
        'Birth City',
        p.birthcity,
        section: 'personal',
        apiField: 'birthcity',
        icon: Icons.place,
      ),
      _row(
        'p_religion',
        'Religion',
        p.religionName,
        section: 'personal',
        apiField: 'religionId',
        editValue: p.religionId > 0 ? '${p.religionId}' : '',
        icon: Icons.flag,
      ),
      _row(
        'p_community',
        'Community',
        p.communityName,
        section: 'personal',
        apiField: 'communityId',
        editValue: p.communityId > 0 ? '${p.communityId}' : '',
        religionId: p.religionId,
        icon: Icons.people,
      ),
      _row(
        'p_subcomm',
        'Sub Community',
        p.subCommunityName,
        section: 'personal',
        apiField: 'subCommunityId',
        editValue: p.subCommunityId > 0 ? '${p.subCommunityId}' : '',
        religionId: p.religionId,
        communityId: p.communityId,
        icon: Icons.people_outline,
      ),
      _row(
        'p_tongue',
        'Mother Tongue',
        p.motherTongue,
        section: 'personal',
        apiField: 'motherTongue',
        icon: Icons.language,
      ),
      _row(
        'p_blood',
        'Blood Group',
        p.bloodGroup,
        section: 'personal',
        apiField: 'bloodGroup',
        staticOptions: kBloodGroupOptions,
        icon: Icons.water_drop,
      ),
      _row(
        'p_marital',
        'Marital Status',
        p.maritalStatusName,
        section: 'personal',
        apiField: 'maritalStatusId',
        editValue: p.maritalStatusId > 0 ? '${p.maritalStatusId}' : '',
        staticLabeledOptions: kMaritalStatusIdEntries
            .map(
              (e) => ProfileFieldOption(value: e['value']!, label: e['label']!),
            )
            .toList(),
        icon: Icons.favorite_border,
      ),
      _row(
        'p_manglik',
        'Manglik',
        p.manglik,
        section: 'personal',
        apiField: 'manglik',
        staticOptions: kManglikOptions,
        icon: Icons.star_border,
      ),
      _row(
        'p_disability',
        'Disability',
        p.disability,
        section: 'personal',
        apiField: 'Disability',
        icon: Icons.accessible,
      ),
      _row(
        'p_privacy',
        'Privacy Setting',
        p.privacy,
        section: 'personal',
        apiField: 'privacy',
        staticOptions: kPrivacyOptions,
        icon: Icons.lock_outline,
      ),
    ],
  );

  Widget _buildEducation(PersonalDetail p) => _section(
    title: 'Education & Career',
    icon: Icons.school_outlined,
    color: _kEducation,
    trailing: _chipButton(
      label: 'Edit all',
      icon: Icons.edit_outlined,
      onTap: () => _openEducationBulk(p),
      color: _kEducation,
    ),
    rows: [
      _row(
        'e_type',
        'Education Type',
        p.educationType,
        section: 'personal',
        apiField: 'educationtype',
        icon: Icons.school,
        highlight: true,
      ),
      _row(
        'e_degree',
        'Degree',
        p.degree,
        section: 'personal',
        apiField: 'degree',
        icon: Icons.military_tech_outlined,
      ),
      _row(
        'e_faculty',
        'Faculty',
        p.faculty,
        section: 'personal',
        apiField: 'faculty',
        icon: Icons.book_outlined,
      ),
      _row(
        'e_medium',
        'Education Medium',
        p.educationMedium,
        section: 'personal',
        apiField: 'educationmedium',
        icon: Icons.translate,
      ),
      _row(
        'e_working',
        'Are You Working?',
        p.areYouWorking,
        section: 'personal',
        apiField: 'areyouworking',
        staticOptions: kYesNoOptions,
        icon: Icons.work_outline,
      ),
      _row(
        'e_occ',
        'Occupation Type',
        p.occupationType,
        section: 'personal',
        apiField: 'occupationtype',
        icon: Icons.business_center_outlined,
        highlight: true,
      ),
      _row(
        'e_workwith',
        'Working With',
        p.workingWith,
        section: 'personal',
        apiField: 'workingwith',
        icon: Icons.corporate_fare,
      ),
      _row(
        'e_company',
        'Company Name',
        p.companyName,
        section: 'personal',
        apiField: 'companyname',
        icon: Icons.business,
      ),
      _row(
        'e_designation',
        'Designation',
        p.designation,
        section: 'personal',
        apiField: 'designation',
        icon: Icons.badge_outlined,
      ),
      _row(
        'e_business',
        'Business Name',
        p.businessName,
        section: 'personal',
        apiField: 'businessname',
        icon: Icons.store_outlined,
      ),
      _row(
        'e_income',
        'Annual Income',
        p.annualIncome,
        section: 'personal',
        apiField: 'annualincome',
        icon: Icons.currency_rupee,
        highlight: true,
      ),
    ],
  );

  Widget _buildFamily(FamilyDetail f) => _section(
    title: 'Family Details',
    icon: Icons.family_restroom,
    color: _kFamily,
    trailing: _chipButton(
      label: 'Edit all',
      icon: Icons.edit_outlined,
      onTap: () => _openFamilyBulk(f),
      color: _kFamily,
    ),
    rows: [
      _row(
        'f_type',
        'Family Type',
        f.familyType,
        section: 'family',
        apiField: 'familytype',
        staticOptions: kFamilyTypeOptions,
        icon: Icons.home_outlined,
        highlight: true,
      ),
      _row(
        'f_background',
        'Family Background',
        f.familyBackground,
        section: 'family',
        apiField: 'familybackground',
        icon: Icons.history_edu,
      ),
      _row(
        'f_origin',
        'Family Origin',
        f.familyOrigin,
        section: 'family',
        apiField: 'familyorigin',
        icon: Icons.public,
      ),
      _row(
        'f_father_status',
        'Father Status',
        f.fatherStatus,
        section: 'family',
        apiField: 'fatherstatus',
        icon: Icons.person_outline,
      ),
      _row(
        'f_father_name',
        'Father Name',
        f.fatherName,
        section: 'family',
        apiField: 'fathername',
        icon: Icons.person,
      ),
      _row(
        'f_father_edu',
        'Father Education',
        f.fatherEducation,
        section: 'family',
        apiField: 'fathereducation',
        icon: Icons.school_outlined,
      ),
      _row(
        'f_father_occ',
        'Father Occupation',
        f.fatherOccupation,
        section: 'family',
        apiField: 'fatheroccupation',
        icon: Icons.work_outline,
      ),
      _row(
        'f_mother_status',
        'Mother Status',
        f.motherStatus,
        section: 'family',
        apiField: 'motherstatus',
        icon: Icons.person_outline,
      ),
      _row(
        'f_mother_caste',
        'Mother Caste',
        f.motherCaste,
        section: 'family',
        apiField: 'mothercaste',
        icon: Icons.people_outline,
      ),
      _row(
        'f_mother_edu',
        'Mother Education',
        f.motherEducation,
        section: 'family',
        apiField: 'mothereducation',
        icon: Icons.school_outlined,
      ),
      _row(
        'f_mother_occ',
        'Mother Occupation',
        f.motherOccupation,
        section: 'family',
        apiField: 'motheroccupation',
        icon: Icons.work_outline,
      ),
    ],
  );

  Widget _buildLifestyle(Lifestyle ls) => _section(
    title: 'Lifestyle',
    icon: Icons.emoji_food_beverage,
    color: _kLifestyle,
    trailing: _chipButton(
      label: 'Edit all',
      icon: Icons.edit_outlined,
      onTap: () => _openLifestyleBulk(ls),
      color: _kLifestyle,
    ),
    rows: [
      _row(
        'l_diet',
        'Diet',
        ls.diet,
        section: 'lifestyle',
        apiField: 'diet',
        staticOptions: kDietOptions,
        icon: Icons.restaurant,
        highlight: true,
      ),
      _row(
        'l_smoke',
        'Smoking',
        ls.smoke,
        section: 'lifestyle',
        apiField: 'smoke',
        icon: Icons.smoking_rooms,
      ),
      _row(
        'l_smoke_type',
        'Smoke Type',
        ls.smokeType,
        section: 'lifestyle',
        apiField: 'smoketype',
        icon: Icons.smoke_free,
      ),
      _row(
        'l_drinks',
        'Drinking',
        ls.drinks,
        section: 'lifestyle',
        apiField: 'drinks',
        icon: Icons.local_drink,
      ),
      _row(
        'l_drink_type',
        'Drink Type',
        ls.drinkType,
        section: 'lifestyle',
        apiField: 'drinktype',
        icon: Icons.wine_bar,
      ),
    ],
  );

  Future<void> _openBulkEditor({
    required String title,
    required Color color,
    required List<_BulkFieldConfig> fields,
    String description =
        'Update multiple fields in one go. Each section saves in one request.',
  }) async {
    final prov = context.read<UserDetailsProvider>();
    final controllers = {
      for (final f in fields)
        f.key: TextEditingController(text: _cleanInitial(f.initial)),
    };
    bool isSaving = false;
    String? error;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final viewInsets = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: viewInsets),
          child: StatefulBuilder(
            builder: (ctx, setSheetState) {
              Future<void> submit() async {
                setSheetState(() {
                  isSaving = true;
                  error = null;
                });

                final changedBySection = <String, Map<String, String>>{};
                for (final f in fields) {
                  final value = controllers[f.key]!.text.trim();
                  if (value == _cleanInitial(f.initial)) continue;
                  changedBySection.putIfAbsent(
                    f.section,
                    () => <String, String>{},
                  )[f.apiField] = value;
                }

                if (changedBySection.isEmpty) {
                  setSheetState(() => isSaving = false);
                  Navigator.pop(ctx, true);
                  return;
                }

                for (final entry in changedBySection.entries) {
                  final ok = await prov.updateSection(
                    section: entry.key,
                    fields: entry.value,
                  );
                  if (!ok) {
                    setSheetState(() {
                      error = prov.updateError.isNotEmpty
                          ? prov.updateError
                          : 'Failed to update ${entry.key} section';
                      isSaving = false;
                    });
                    return;
                  }
                }

                setSheetState(() => isSaving = false);
                Navigator.pop(ctx, true);
              }

              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.tune, size: 18, color: color),
                        const SizedBox(width: 8),
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: fields.map((f) {
                        final hasStatic =
                            f.staticOptions != null &&
                            f.staticOptions!.isNotEmpty;
                        final hasLabeled =
                            f.staticLabeledOptions != null &&
                            f.staticLabeledOptions!.isNotEmpty;
                        return SizedBox(
                          width: MediaQuery.of(ctx).size.width > 720
                              ? 320
                              : double.infinity,
                          child: hasLabeled
                              // â”€â”€ Keyed dropdown (value â‰  label) â”€â”€â”€â”€â”€â”€
                              ? StatefulBuilder(
                                  builder: (ctx2, setDropState) {
                                    final validValues = f.staticLabeledOptions!
                                        .map((o) => o.value)
                                        .toSet();
                                    String? dropValue =
                                        controllers[f.key]!.text
                                            .trim()
                                            .isNotEmpty
                                        ? controllers[f.key]!.text.trim()
                                        : null;
                                    if (dropValue != null &&
                                        !validValues.contains(dropValue)) {
                                      dropValue = null;
                                    }
                                    return DropdownButtonFormField<String>(
                                      value: dropValue,
                                      isExpanded: true,
                                      decoration: InputDecoration(
                                        labelText: f.label,
                                        filled: true,
                                        fillColor: Colors.grey.shade50,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          borderSide: const BorderSide(
                                            color: Color(0xFFE2E8F0),
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          borderSide: const BorderSide(
                                            color: Color(0xFFE2E8F0),
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          borderSide: BorderSide(color: color),
                                        ),
                                        isDense: true,
                                      ),
                                      items: f.staticLabeledOptions!
                                          .map(
                                            (o) => DropdownMenuItem<String>(
                                              value: o.value,
                                              child: Text(
                                                o.label,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (v) {
                                        if (v != null)
                                          controllers[f.key]!.text = v;
                                        setDropState(() {});
                                      },
                                    );
                                  },
                                )
                              : hasStatic
                              ? StatefulBuilder(
                                  builder: (ctx2, setDropState) {
                                    String? dropValue =
                                        controllers[f.key]!.text
                                            .trim()
                                            .isNotEmpty
                                        ? controllers[f.key]!.text.trim()
                                        : null;
                                    if (dropValue != null &&
                                        !f.staticOptions!.contains(dropValue)) {
                                      dropValue = null;
                                    }
                                    return DropdownButtonFormField<String>(
                                      value: dropValue,
                                      isExpanded: true,
                                      decoration: InputDecoration(
                                        labelText: f.label,
                                        filled: true,
                                        fillColor: Colors.grey.shade50,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          borderSide: const BorderSide(
                                            color: Color(0xFFE2E8F0),
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          borderSide: const BorderSide(
                                            color: Color(0xFFE2E8F0),
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          borderSide: BorderSide(color: color),
                                        ),
                                        isDense: true,
                                      ),
                                      items: f.staticOptions!
                                          .map(
                                            (o) => DropdownMenuItem<String>(
                                              value: o,
                                              child: Text(
                                                o,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (v) {
                                        if (v != null) {
                                          controllers[f.key]!.text = v;
                                        }
                                        setDropState(() {});
                                      },
                                    );
                                  },
                                )
                              : TextField(
                                  controller: controllers[f.key],
                                  keyboardType: f.multiline
                                      ? TextInputType.multiline
                                      : f.inputType,
                                  maxLines: f.multiline ? 3 : 1,
                                  decoration: InputDecoration(
                                    labelText: f.label,
                                    filled: true,
                                    fillColor: Colors.grey.shade50,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                        color: Color(0xFFE2E8F0),
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                        color: Color(0xFFE2E8F0),
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(color: color),
                                    ),
                                    isDense: true,
                                  ),
                                ),
                        );
                      }).toList(),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF1F2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFFECBD3)),
                        ),
                        child: Text(
                          error ?? '',
                          style: const TextStyle(
                            color: Color(0xFFB91C1C),
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: isSaving ? null : submit,
                        icon: isSaving
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save_outlined, size: 16),
                        label: Text(isSaving ? 'Saving...' : 'Save Changes'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: color,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$title updated'),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _openPartnerEdit(PartnerPreference pp) async {
    final prov = context.read<UserDetailsProvider>();
    final fields = [
      {
        'key': 'minAge',
        'label': 'Min Age',
        'api': 'minage',
        'initial': pp.minAge == 0 ? '' : pp.minAge.toString(),
        'type': TextInputType.number,
      },
      {
        'key': 'maxAge',
        'label': 'Max Age',
        'api': 'maxage',
        'initial': pp.maxAge == 0 ? '' : pp.maxAge.toString(),
        'type': TextInputType.number,
      },
      {
        'key': 'minHeight',
        'label': 'Min Height (cm)',
        'api': 'minheight',
        'initial': pp.minHeight == 0 ? '' : pp.minHeight.toString(),
        'type': TextInputType.number,
      },
      {
        'key': 'maxHeight',
        'label': 'Max Height (cm)',
        'api': 'maxheight',
        'initial': pp.maxHeight == 0 ? '' : pp.maxHeight.toString(),
        'type': TextInputType.number,
      },
      {
        'key': 'maritalStatus',
        'label': 'Marital Status',
        'api': 'maritalstatus',
        'initial': pp.maritalStatus,
        'type': TextInputType.text,
        'options': kMaritalStatusOptions,
      },
      {
        'key': 'profileWithChild',
        'label': 'Profile With Child',
        'api': 'profilewithchild',
        'initial': pp.profileWithChild,
        'type': TextInputType.text,
      },
      {
        'key': 'familyType',
        'label': 'Family Type',
        'api': 'familytype',
        'initial': pp.familyType,
        'type': TextInputType.text,
      },
      {
        'key': 'religion',
        'label': 'Religion',
        'api': 'religion',
        'initial': pp.religion,
        'type': TextInputType.text,
      },
      {
        'key': 'caste',
        'label': 'Caste',
        'api': 'caste',
        'initial': pp.caste,
        'type': TextInputType.text,
      },
      {
        'key': 'motherTongue',
        'label': 'Mother Tongue',
        'api': 'mothertoungue',
        'initial': pp.motherTongue,
        'type': TextInputType.text,
      },
      {
        'key': 'country',
        'label': 'Country',
        'api': 'country',
        'initial': pp.country,
        'type': TextInputType.text,
      },
      {
        'key': 'state',
        'label': 'State',
        'api': 'state',
        'initial': pp.state,
        'type': TextInputType.text,
      },
      {
        'key': 'city',
        'label': 'City',
        'api': 'city',
        'initial': pp.city,
        'type': TextInputType.text,
      },
      {
        'key': 'qualification',
        'label': 'Qualification',
        'api': 'qualification',
        'initial': pp.qualification,
        'type': TextInputType.text,
      },
      {
        'key': 'educationMedium',
        'label': 'Education Medium',
        'api': 'educationmedium',
        'initial': pp.educationMedium,
        'type': TextInputType.text,
      },
      {
        'key': 'profession',
        'label': 'Profession',
        'api': 'proffession',
        'initial': pp.profession,
        'type': TextInputType.text,
      },
      {
        'key': 'workingWith',
        'label': 'Working With',
        'api': 'workingwith',
        'initial': pp.workingWith,
        'type': TextInputType.text,
      },
      {
        'key': 'annualIncome',
        'label': 'Annual Income',
        'api': 'annualincome',
        'initial': pp.annualIncome,
        'type': TextInputType.text,
      },
      {
        'key': 'diet',
        'label': 'Diet',
        'api': 'diet',
        'initial': pp.diet,
        'type': TextInputType.text,
        'options': kDietOptions,
      },
      {
        'key': 'smokeAccept',
        'label': 'Smoke Acceptable',
        'api': 'smokeaccept',
        'initial': pp.smokeAccept,
        'type': TextInputType.text,
        'options': kYesNoOptions,
      },
      {
        'key': 'drinkAccept',
        'label': 'Drink Acceptable',
        'api': 'drinkaccept',
        'initial': pp.drinkAccept,
        'type': TextInputType.text,
        'options': kYesNoOptions,
      },
      {
        'key': 'disabilityAccept',
        'label': 'Disability Acceptable',
        'api': 'disabilityaccept',
        'initial': pp.disabilityAccept,
        'type': TextInputType.text,
        'options': kYesNoOptions,
      },
      {
        'key': 'complexion',
        'label': 'Complexion',
        'api': 'complexion',
        'initial': pp.complexion,
        'type': TextInputType.text,
        'options': kComplexionOptions,
      },
      {
        'key': 'bodyType',
        'label': 'Body Type',
        'api': 'bodytype',
        'initial': pp.bodyType,
        'type': TextInputType.text,
        'options': kBodyTypeOptions,
      },
      {
        'key': 'manglik',
        'label': 'Manglik',
        'api': 'manglik',
        'initial': pp.manglik,
        'type': TextInputType.text,
        'options': kManglikOptions,
      },
      {
        'key': 'hersCopeBelief',
        'label': 'Horoscope Belief',
        'api': 'herscopeblief',
        'initial': pp.hersCopeBelief,
        'type': TextInputType.text,
        'options': kHerscopeBliefOptions,
      },
      {
        'key': 'otherExpectation',
        'label': 'Other Expectations',
        'api': 'otherexpectation',
        'initial': pp.otherExpectation,
        'type': TextInputType.multiline,
      },
    ];

    final controllers = {
      for (final f in fields)
        f['key'] as String: TextEditingController(
          text:
              (f['initial'] as String).isNotEmpty &&
                  (f['initial'] as String) != 'Not available'
              ? f['initial'] as String
              : '',
        ),
    };

    bool isSaving = false;
    String? error;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final viewInsets = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: viewInsets),
          child: StatefulBuilder(
            builder: (ctx, setSheetState) {
              Future<void> submit() async {
                setSheetState(() {
                  isSaving = true;
                  error = null;
                });

                final changed = <String, String>{};
                for (final f in fields) {
                  final key = f['key'] as String;
                  final api = f['api'] as String;
                  final value = controllers[key]!.text.trim();
                  final initial = f['initial'] as String;
                  if (value == initial) continue;
                  changed[api] = value;
                }

                if (changed.isNotEmpty) {
                  final ok = await prov.updateSection(
                    section: 'partner',
                    fields: changed,
                  );
                  if (!ok) {
                    setSheetState(() {
                      error = prov.updateError.isNotEmpty
                          ? prov.updateError
                          : 'Failed to update partner section';
                      isSaving = false;
                    });
                    return;
                  }
                }

                setSheetState(() => isSaving = false);
                Navigator.pop(ctx, true);
              }

              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.favorite, size: 18, color: _kPartner),
                        SizedBox(width: 8),
                        Text(
                          'Edit Partner Preferences',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Update all partner expectations in one place. Saves as one section update.',
                      style: TextStyle(fontSize: 13, color: Color(0xFF475569)),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: fields.map((f) {
                        final key = f['key'] as String;
                        final type = f['type'] as TextInputType;
                        final opts = f['options'] as List<String>?;
                        return SizedBox(
                          width: MediaQuery.of(ctx).size.width > 720
                              ? 320
                              : double.infinity,
                          child: opts != null && opts.isNotEmpty
                              ? StatefulBuilder(
                                  builder: (ctx2, setDropState) {
                                    String? dropValue =
                                        controllers[key]!.text.trim().isNotEmpty
                                        ? controllers[key]!.text.trim()
                                        : null;
                                    if (dropValue != null &&
                                        !opts.contains(dropValue)) {
                                      dropValue = null;
                                    }
                                    return DropdownButtonFormField<String>(
                                      value: dropValue,
                                      isExpanded: true,
                                      decoration: InputDecoration(
                                        labelText: f['label'] as String,
                                        filled: true,
                                        fillColor: Colors.grey.shade50,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          borderSide: const BorderSide(
                                            color: Color(0xFFE2E8F0),
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          borderSide: const BorderSide(
                                            color: Color(0xFFE2E8F0),
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          borderSide: const BorderSide(
                                            color: _kPartner,
                                          ),
                                        ),
                                        isDense: true,
                                      ),
                                      items: opts
                                          .map(
                                            (o) => DropdownMenuItem<String>(
                                              value: o,
                                              child: Text(
                                                o,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (v) {
                                        if (v != null)
                                          controllers[key]!.text = v;
                                        setDropState(() {});
                                      },
                                    );
                                  },
                                )
                              : TextField(
                                  controller: controllers[key],
                                  keyboardType: type == TextInputType.multiline
                                      ? TextInputType.multiline
                                      : type,
                                  maxLines: type == TextInputType.multiline
                                      ? 3
                                      : 1,
                                  decoration: InputDecoration(
                                    labelText: f['label'] as String,
                                    filled: true,
                                    fillColor: Colors.grey.shade50,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                        color: Color(0xFFE2E8F0),
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                        color: Color(0xFFE2E8F0),
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                        color: _kPrimary,
                                        width: 1.4,
                                      ),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                  ),
                                  style: const TextStyle(fontSize: 13.5),
                                ),
                        );
                      }).toList(),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        error!,
                        style: const TextStyle(
                          color: _kRose,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: isSaving
                                ? null
                                : () => Navigator.pop(ctx, false),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: const BorderSide(color: Color(0xFFE2E8F0)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: isSaving ? null : submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kPartner,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              elevation: 0,
                            ),
                            child: isSaving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Save All'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    for (final ctrl in controllers.values) {
      ctrl.dispose();
    }

    if (saved == true && mounted) {
      await prov.fetchUserDetails(widget.userId, widget.myId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Partner preferences updated'),
          backgroundColor: _kPartner,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  Widget _buildPartnerMatchCard(PartnerMatch pm) {
    final pct = pm.percentage;
    final hasAny = pm.totalCount > 0;
    final barColor = pct >= 0.5
        ? const Color(0xFF10B981)
        : pct >= 0.2
        ? const Color(0xFFF59E0B)
        : const Color(0xFFEF4444);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kPartner.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kPartner.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _kPartner.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.people_alt_outlined,
                  size: 18,
                  color: _kPartner,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Partner Match Score',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasAny
                          ? '${pm.matchedCount} out of ${pm.totalCount} users match these preferences'
                          : 'Preferences not set — no match data',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: barColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: barColor.withOpacity(0.30)),
                ),
                child: Text(
                  hasAny ? '${(pct * 100).toStringAsFixed(0)}%' : '—',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: barColor,
                  ),
                ),
              ),
            ],
          ),
          if (hasAny) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 6,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              ),
            ),
          ],
          if (pm.details.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: pm.details.entries.map((e) {
                final label = e.key
                    .replaceAll('_', ' ')
                    .split(' ')
                    .map(
                      (w) =>
                          w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1),
                    )
                    .join(' ');
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _kPartner.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _kPartner.withOpacity(0.20)),
                  ),
                  child: Text(
                    '$label: ${e.value}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _kPartner,
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

  Widget _buildPartner(PartnerPreference pp, [PartnerMatch? pm]) => _section(
    title: 'Partner Preferences',
    icon: Icons.favorite,
    color: _kPartner,
    trailing: _chipButton(
      label: 'Edit all',
      icon: Icons.edit_outlined,
      onTap: () => _openPartnerEdit(pp),
      color: _kPartner,
    ),
    rows: [
      if (pm != null) _buildPartnerMatchCard(pm),
      _row(
        'pp_min_age',
        'Min Age',
        pp.minAge == 0 ? 'Not available' : pp.minAge.toString(),
        section: 'partner',
        apiField: 'minage',
        icon: Icons.calendar_today,
        highlight: true,
      ),
      _row(
        'pp_max_age',
        'Max Age',
        pp.maxAge == 0 ? 'Not available' : pp.maxAge.toString(),
        section: 'partner',
        apiField: 'maxage',
        icon: Icons.calendar_today,
      ),
      _row(
        'pp_min_height',
        'Min Height',
        pp.minHeight == 0 ? 'Not available' : pp.minHeight.toString(),
        section: 'partner',
        apiField: 'minheight',
        icon: Icons.height,
      ),
      _row(
        'pp_max_height',
        'Max Height',
        pp.maxHeight == 0 ? 'Not available' : pp.maxHeight.toString(),
        section: 'partner',
        apiField: 'maxheight',
        icon: Icons.height,
      ),
      _row(
        'pp_marital',
        'Marital Status',
        pp.maritalStatus,
        section: 'partner',
        apiField: 'maritalstatus',
        staticOptions: kMaritalStatusOptions,
        icon: Icons.favorite_border,
      ),
      _row(
        'pp_child',
        'Profile With Child',
        pp.profileWithChild,
        section: 'partner',
        apiField: 'profilewithchild',
        staticOptions: kProfileWithChildOptions,
        icon: Icons.child_care,
      ),
      _row(
        'pp_family',
        'Family Type',
        pp.familyType,
        section: 'partner',
        apiField: 'familytype',
        staticOptions: kFamilyTypeOptions,
        icon: Icons.home_outlined,
      ),
      _row(
        'pp_religion',
        'Religion',
        pp.religion,
        section: 'partner',
        apiField: 'religion',
        icon: Icons.flag,
      ),
      _row(
        'pp_caste',
        'Caste',
        pp.caste,
        section: 'partner',
        apiField: 'caste',
        icon: Icons.people,
      ),
      _row(
        'pp_tongue',
        'Mother Tongue',
        pp.motherTongue,
        section: 'partner',
        apiField: 'mothertoungue',
        icon: Icons.language,
      ),
      _row(
        'pp_country',
        'Country',
        pp.country,
        section: 'partner',
        apiField: 'country',
        icon: Icons.public,
      ),
      _row(
        'pp_state',
        'State',
        pp.state,
        section: 'partner',
        apiField: 'state',
        icon: Icons.map_outlined,
      ),
      _row(
        'pp_city',
        'City',
        pp.city,
        section: 'partner',
        apiField: 'city',
        icon: Icons.location_city,
      ),
      // Location picker button â€” opens cascading country/state/city picker
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: OutlinedButton.icon(
          icon: const Icon(Icons.edit_location_alt_outlined, size: 16),
          label: const Text('Edit Location (Country / State / City)'),
          onPressed: () => _showLocationPickerDialog(
            section: 'partner',
            currentCountry: pp.country,
            currentState: pp.state,
            currentCity: pp.city,
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: _kPartner,
            side: const BorderSide(color: _kPartner),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
      ),
      _row(
        'pp_qual',
        'Qualification',
        pp.qualification,
        section: 'partner',
        apiField: 'qualification',
        icon: Icons.school_outlined,
      ),
      _row(
        'pp_edu_medium',
        'Education Medium',
        pp.educationMedium,
        section: 'partner',
        apiField: 'educationmedium',
        icon: Icons.translate,
      ),
      _row(
        'pp_profession',
        'Profession',
        pp.profession,
        section: 'partner',
        apiField: 'proffession',
        icon: Icons.business_center_outlined,
      ),
      _row(
        'pp_workwith',
        'Working With',
        pp.workingWith,
        section: 'partner',
        apiField: 'workingwith',
        icon: Icons.corporate_fare,
      ),
      _row(
        'pp_income',
        'Annual Income',
        pp.annualIncome,
        section: 'partner',
        apiField: 'annualincome',
        icon: Icons.currency_rupee,
      ),
      _row(
        'pp_diet',
        'Diet',
        pp.diet,
        section: 'partner',
        apiField: 'diet',
        staticOptions: kDietOptions,
        icon: Icons.restaurant_menu,
      ),
      _row(
        'pp_smoke',
        'Smoke Acceptable',
        pp.smokeAccept,
        section: 'partner',
        apiField: 'smokeaccept',
        staticOptions: kYesNoOptions,
        icon: Icons.smoking_rooms,
      ),
      _row(
        'pp_drink',
        'Drink Acceptable',
        pp.drinkAccept,
        section: 'partner',
        apiField: 'drinkaccept',
        staticOptions: kYesNoOptions,
        icon: Icons.local_bar,
      ),
      _row(
        'pp_disability',
        'Disability Acceptable',
        pp.disabilityAccept,
        section: 'partner',
        apiField: 'disabilityaccept',
        staticOptions: kYesNoOptions,
        icon: Icons.accessible_forward,
      ),
      _row(
        'pp_complexion',
        'Complexion',
        pp.complexion,
        section: 'partner',
        apiField: 'complexion',
        staticOptions: kComplexionOptions,
        icon: Icons.palette_outlined,
      ),
      _row(
        'pp_body',
        'Body Type',
        pp.bodyType,
        section: 'partner',
        apiField: 'bodytype',
        staticOptions: kBodyTypeOptions,
        icon: Icons.accessibility_new,
      ),
      _row(
        'pp_manglik',
        'Manglik',
        pp.manglik,
        section: 'partner',
        apiField: 'manglik',
        staticOptions: kManglikOptions,
        icon: Icons.star_border,
      ),
      _row(
        'pp_herscope',
        'Hers Cope Belief',
        pp.hersCopeBelief,
        section: 'partner',
        apiField: 'herscopeblief',
        staticOptions: kHerscopeBliefOptions,
        icon: Icons.psychology_outlined,
      ),
      if (pp.otherExpectation.isNotEmpty &&
          pp.otherExpectation != 'Not available')
        _row(
          'pp_other',
          'Other Expectations',
          pp.otherExpectation,
          section: 'partner',
          apiField: 'otherexpectation',
          icon: Icons.notes,
        ),
    ],
  );

  Future<void> _openPersonalBulk(PersonalDetail p) {
    return _openBulkEditor(
      title: 'Edit Personal Details',
      color: _kPersonal,
      description: 'Quickly adjust core personal fields in a single sheet.',
      fields: [
        _BulkFieldConfig(
          key: 'firstName',
          label: 'First Name',
          apiField: 'firstName',
          section: 'personal',
          initial: p.firstName,
        ),
        _BulkFieldConfig(
          key: 'lastName',
          label: 'Last Name',
          apiField: 'lastName',
          section: 'personal',
          initial: p.lastName,
        ),
        _BulkFieldConfig(
          key: 'city',
          label: 'City',
          apiField: 'city',
          section: 'personal',
          initial: p.city,
        ),
        _BulkFieldConfig(
          key: 'country',
          label: 'Country',
          apiField: 'country',
          section: 'personal',
          initial: p.country,
        ),
        _BulkFieldConfig(
          key: 'height',
          label: 'Height',
          apiField: 'height_name',
          section: 'personal',
          initial: p.heightName,
          staticOptions: kHeightOptions,
        ),
        _BulkFieldConfig(
          key: 'birthDate',
          label: 'Birth Date',
          apiField: 'birthDate',
          section: 'personal',
          initial: p.birthDate,
        ),
        _BulkFieldConfig(
          key: 'birthTime',
          label: 'Birth Time',
          apiField: 'birthtime',
          section: 'personal',
          initial: p.birthtime,
        ),
        _BulkFieldConfig(
          key: 'birthCity',
          label: 'Birth City',
          apiField: 'birthcity',
          section: 'personal',
          initial: p.birthcity,
        ),
        _BulkFieldConfig(
          key: 'religion',
          label: 'Religion',
          apiField: 'religionId',
          section: 'personal',
          initial: p.religionId > 0 ? '${p.religionId}' : '',
        ),
        _BulkFieldConfig(
          key: 'community',
          label: 'Community',
          apiField: 'communityId',
          section: 'personal',
          initial: p.communityId > 0 ? '${p.communityId}' : '',
        ),
        _BulkFieldConfig(
          key: 'subCommunity',
          label: 'Sub Community',
          apiField: 'subCommunityId',
          section: 'personal',
          initial: p.subCommunityId > 0 ? '${p.subCommunityId}' : '',
        ),
        _BulkFieldConfig(
          key: 'motherTongue',
          label: 'Mother Tongue',
          apiField: 'motherTongue',
          section: 'personal',
          initial: p.motherTongue,
        ),
        _BulkFieldConfig(
          key: 'bloodGroup',
          label: 'Blood Group',
          apiField: 'bloodGroup',
          section: 'personal',
          initial: p.bloodGroup,
          staticOptions: kBloodGroupOptions,
        ),
        _BulkFieldConfig(
          key: 'maritalStatus',
          label: 'Marital Status',
          apiField: 'maritalStatusId',
          section: 'personal',
          initial: p.maritalStatusId > 0 ? '${p.maritalStatusId}' : '',
          staticLabeledOptions: kMaritalStatusIdEntries
              .map(
                (e) =>
                    ProfileFieldOption(value: e['value']!, label: e['label']!),
              )
              .toList(),
        ),
        _BulkFieldConfig(
          key: 'manglik',
          label: 'Manglik',
          apiField: 'manglik',
          section: 'personal',
          initial: p.manglik,
          staticOptions: kManglikOptions,
        ),
        _BulkFieldConfig(
          key: 'disability',
          label: 'Disability',
          apiField: 'Disability',
          section: 'personal',
          initial: p.disability,
        ),
        _BulkFieldConfig(
          key: 'privacy',
          label: 'Privacy Setting',
          apiField: 'privacy',
          section: 'personal',
          initial: p.privacy,
          staticOptions: kPrivacyOptions,
        ),
      ],
    );
  }

  Future<void> _openEducationBulk(PersonalDetail p) {
    return _openBulkEditor(
      title: 'Edit Education & Career',
      color: _kEducation,
      description: 'Bulk edit education and career information.',
      fields: [
        _BulkFieldConfig(
          key: 'educationType',
          label: 'Education Type',
          apiField: 'educationtype',
          section: 'personal',
          initial: p.educationType,
        ),
        _BulkFieldConfig(
          key: 'degree',
          label: 'Degree',
          apiField: 'degree',
          section: 'personal',
          initial: p.degree,
        ),
        _BulkFieldConfig(
          key: 'faculty',
          label: 'Faculty',
          apiField: 'faculty',
          section: 'personal',
          initial: p.faculty,
        ),
        _BulkFieldConfig(
          key: 'educationMedium',
          label: 'Education Medium',
          apiField: 'educationmedium',
          section: 'personal',
          initial: p.educationMedium,
        ),
        _BulkFieldConfig(
          key: 'areYouWorking',
          label: 'Are You Working?',
          apiField: 'areyouworking',
          section: 'personal',
          initial: p.areYouWorking,
          staticOptions: kYesNoOptions,
        ),
        _BulkFieldConfig(
          key: 'occupationType',
          label: 'Occupation Type',
          apiField: 'occupationtype',
          section: 'personal',
          initial: p.occupationType,
        ),
        _BulkFieldConfig(
          key: 'workingWith',
          label: 'Working With',
          apiField: 'workingwith',
          section: 'personal',
          initial: p.workingWith,
        ),
        _BulkFieldConfig(
          key: 'companyName',
          label: 'Company Name',
          apiField: 'companyname',
          section: 'personal',
          initial: p.companyName,
        ),
        _BulkFieldConfig(
          key: 'designation',
          label: 'Designation',
          apiField: 'designation',
          section: 'personal',
          initial: p.designation,
        ),
        _BulkFieldConfig(
          key: 'businessName',
          label: 'Business Name',
          apiField: 'businessname',
          section: 'personal',
          initial: p.businessName,
        ),
        _BulkFieldConfig(
          key: 'annualIncome',
          label: 'Annual Income',
          apiField: 'annualincome',
          section: 'personal',
          initial: p.annualIncome,
        ),
      ],
    );
  }

  Future<void> _openFamilyBulk(FamilyDetail f) {
    return _openBulkEditor(
      title: 'Edit Family Details',
      color: _kFamily,
      description: 'Manage family background fields together.',
      fields: [
        _BulkFieldConfig(
          key: 'familyType',
          label: 'Family Type',
          apiField: 'familytype',
          section: 'family',
          initial: f.familyType,
          staticOptions: kFamilyTypeOptions,
        ),
        _BulkFieldConfig(
          key: 'familyBackground',
          label: 'Family Background',
          apiField: 'familybackground',
          section: 'family',
          initial: f.familyBackground,
        ),
        _BulkFieldConfig(
          key: 'familyOrigin',
          label: 'Family Origin',
          apiField: 'familyorigin',
          section: 'family',
          initial: f.familyOrigin,
        ),
        _BulkFieldConfig(
          key: 'fatherStatus',
          label: 'Father Status',
          apiField: 'fatherstatus',
          section: 'family',
          initial: f.fatherStatus,
        ),
        _BulkFieldConfig(
          key: 'fatherName',
          label: 'Father Name',
          apiField: 'fathername',
          section: 'family',
          initial: f.fatherName,
        ),
        _BulkFieldConfig(
          key: 'fatherEducation',
          label: 'Father Education',
          apiField: 'fathereducation',
          section: 'family',
          initial: f.fatherEducation,
        ),
        _BulkFieldConfig(
          key: 'fatherOccupation',
          label: 'Father Occupation',
          apiField: 'fatheroccupation',
          section: 'family',
          initial: f.fatherOccupation,
        ),
        _BulkFieldConfig(
          key: 'motherStatus',
          label: 'Mother Status',
          apiField: 'motherstatus',
          section: 'family',
          initial: f.motherStatus,
        ),
        _BulkFieldConfig(
          key: 'motherCaste',
          label: 'Mother Caste',
          apiField: 'mothercaste',
          section: 'family',
          initial: f.motherCaste,
        ),
        _BulkFieldConfig(
          key: 'motherEducation',
          label: 'Mother Education',
          apiField: 'mothereducation',
          section: 'family',
          initial: f.motherEducation,
        ),
        _BulkFieldConfig(
          key: 'motherOccupation',
          label: 'Mother Occupation',
          apiField: 'motheroccupation',
          section: 'family',
          initial: f.motherOccupation,
        ),
      ],
    );
  }

  Future<void> _openLifestyleBulk(Lifestyle ls) {
    return _openBulkEditor(
      title: 'Edit Lifestyle',
      color: _kLifestyle,
      description: 'Update diet, smoking and drinking choices together.',
      fields: [
        _BulkFieldConfig(
          key: 'diet',
          label: 'Diet',
          apiField: 'diet',
          section: 'lifestyle',
          initial: ls.diet,
          staticOptions: kDietOptions,
        ),
        _BulkFieldConfig(
          key: 'smoke',
          label: 'Smoking',
          apiField: 'smoke',
          section: 'lifestyle',
          initial: ls.smoke,
        ),
        _BulkFieldConfig(
          key: 'smokeType',
          label: 'Smoke Type',
          apiField: 'smoketype',
          section: 'lifestyle',
          initial: ls.smokeType,
        ),
        _BulkFieldConfig(
          key: 'drinks',
          label: 'Drinking',
          apiField: 'drinks',
          section: 'lifestyle',
          initial: ls.drinks,
        ),
        _BulkFieldConfig(
          key: 'drinkType',
          label: 'Drink Type',
          apiField: 'drinktype',
          section: 'lifestyle',
          initial: ls.drinkType,
        ),
      ],
    );
  }

  // â”€â”€ documents section â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildDocumentsSection() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kDocs.withOpacity(0.12)),
      ),
      child: Consumer<DocumentsProvider>(
        builder: (_, dp, __) {
          if (dp.isLoading) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }

          final docs = dp.documentsForUser(widget.userId);
          final pending = docs.where((d) => d.isPending).length;
          final approved = docs.where((d) => d.isApproved).length;
          final rejected = docs.where((d) => d.isRejected).length;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Documents',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: _kDocs,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: dp.isLoading ? null : () => dp.fetchDocuments(),
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: _kDocs.withOpacity(0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.refresh, size: 15, color: _kDocs),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _miniInfoChip(
                    icon: Icons.inventory_2_outlined,
                    label: '${docs.length} total',
                    color: _kDocs,
                  ),
                  _miniInfoChip(
                    icon: Icons.pending_actions_outlined,
                    label: '$pending pending',
                    color: pending > 0 ? _kAmber : _kEmerald,
                  ),
                  _miniInfoChip(
                    icon: Icons.verified_outlined,
                    label: '$approved approved',
                    color: _kEmerald,
                  ),
                  _miniInfoChip(
                    icon: Icons.cancel_outlined,
                    label: '$rejected rejected',
                    color: _kRose,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (docs.isEmpty)
                InkWell(
                  onTap: _showUploadDocumentDialog,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    decoration: BoxDecoration(
                      color: _kDocs.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _kDocs.withOpacity(0.14)),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.upload_file_outlined,
                            color: _kDocs,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'No documents yet',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 560;
                    final medium = constraints.maxWidth >= 360;
                    final crossAxisCount = wide ? 5 : (medium ? 4 : 3);
                    final itemCount = docs.length + 1;

                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: itemCount,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        mainAxisSpacing: 6,
                        crossAxisSpacing: 6,
                        childAspectRatio: wide ? 0.85 : (medium ? 0.80 : 0.78),
                      ),
                      itemBuilder: (_, i) {
                        if (i == 0) {
                          return InkWell(
                            onTap: _showUploadDocumentDialog,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              decoration: BoxDecoration(
                                color: _kDocs.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _kDocs.withOpacity(0.14),
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.add,
                                      color: _kDocs,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Add Document',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        final doc = docs[i - 1];
                        return _docCard(doc);
                      },
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildUploadControlPanel({
    required String title,
    required String description,
    required Color accent,
    required List<Widget> stats,
    required Widget primaryAction,
    Widget? secondaryAction,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withOpacity(0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.cloud_upload_outlined,
                  size: 18,
                  color: accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: Colors.blueGrey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (stats.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: stats),
          ],
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final stackButtons = constraints.maxWidth < 420;
              if (stackButtons) {
                return Column(
                  children: [
                    SizedBox(width: double.infinity, child: primaryAction),
                    if (secondaryAction != null) ...[
                      const SizedBox(height: 10),
                      SizedBox(width: double.infinity, child: secondaryAction),
                    ],
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: primaryAction),
                  if (secondaryAction != null) ...[
                    const SizedBox(width: 10),
                    Expanded(child: secondaryAction),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _miniInfoChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _docCard(Document doc) {
    final statusColor = doc.isApproved
        ? const Color(0xFF10B981)
        : doc.isRejected
        ? const Color(0xFFEF4444)
        : const Color(0xFFF59E0B);
    final statusIcon = doc.isApproved
        ? Icons.verified_outlined
        : doc.isRejected
        ? Icons.cancel_outlined
        : Icons.pending_outlined;

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(10),
              topRight: Radius.circular(10),
            ),
            child: InkWell(
              onTap: () => _showDocPreview(doc.fullPhotoUrl),
              child: SizedBox(
                height: 52,
                width: double.infinity,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Image.network(
                        doc.fullPhotoUrl,
                        fit: BoxFit.cover,
                        loadingBuilder: (_, child, prog) {
                          if (prog == null) return child;
                          return const Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        },
                        errorBuilder: (_, __, ___) => Center(
                          child: Icon(
                            Icons.insert_drive_file_outlined,
                            size: 26,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.94),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(statusIcon, size: 11, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(
                              doc.status.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      right: 6,
                      top: 4,
                      child: PopupMenuButton<String>(
                        tooltip: 'Document actions',
                        padding: EdgeInsets.zero,
                        icon: const Icon(
                          Icons.more_vert_rounded,
                          size: 17,
                          color: Colors.white,
                        ),
                        color: Colors.white,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black45,
                          minimumSize: const Size(26, 26),
                        ),
                        onSelected: (value) {
                          final dp = context.read<DocumentsProvider>();
                          if (value == 'approve') {
                            _approveDocFromProfile(doc, dp);
                          } else if (value == 'reject') {
                            _rejectDocFromProfile(doc, dp);
                          }
                        },
                        itemBuilder: (_) => [
                          if (doc.isPending)
                            const PopupMenuItem(
                              value: 'approve',
                              child: Text('Approve'),
                            ),
                          if (doc.isPending)
                            const PopupMenuItem(
                              value: 'reject',
                              child: Text('Reject'),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doc.documentType.isNotEmpty ? doc.documentType : 'â€”',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    doc.documentIdNumber.isNotEmpty
                        ? doc.documentIdNumber
                        : 'â€”',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: Colors.grey.shade700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (doc.isRejected && doc.rejectReason.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      doc.rejectReason,
                      style: const TextStyle(
                        fontSize: 9.5,
                        color: Color(0xFF64748B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const Spacer(),
                  Consumer<DocumentsProvider>(
                    builder: (_, dp, __) => Row(
                      children: [
                        Expanded(
                          child: Text(
                            doc.isPending
                                ? 'Approve or reject from menu'
                                : doc.isApproved
                                ? 'Verified document'
                                : 'Rejected document',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 9.5,
                              color: Colors.blueGrey.shade600,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (dp.isActionLoading && doc.isPending)
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        if (doc.isApproved) ...[
                          const SizedBox(width: 6),
                          Tooltip(
                            message:
                                'Document is permanently locked after verification',
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF10B981,
                                ).withOpacity(0.08),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: const Color(
                                    0xFF10B981,
                                  ).withOpacity(0.25),
                                ),
                              ),
                              child: const Icon(
                                Icons.lock_rounded,
                                size: 12,
                                color: Color(0xFF10B981),
                              ),
                            ),
                          ),
                        ],
                      ],
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

  Widget _docActionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(6),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    ),
  );

  void _showDocPreview(String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.82,
                maxWidth: MediaQuery.of(context).size.width * 0.9,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Expanded(
                    child: InteractiveViewer(
                      panEnabled: true,
                      minScale: 0.5,
                      maxScale: 4,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                        child: Image.network(
                          url,
                          fit: BoxFit.contain,
                          loadingBuilder: (_, child, prog) {
                            if (prog == null) return child;
                            return Center(
                              child: CircularProgressIndicator(
                                value: prog.expectedTotalBytes != null
                                    ? prog.cumulativeBytesLoaded /
                                          prog.expectedTotalBytes!
                                    : null,
                              ),
                            );
                          },
                          errorBuilder: (_, __, ___) => Container(
                            color: Colors.grey[100],
                            child: const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.broken_image,
                                    size: 48,
                                    color: Colors.grey,
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'Image not available',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, size: 16),
                        label: const Text('Close'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kPrimary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _approveDocFromProfile(
    Document doc,
    DocumentsProvider dp,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          'Approve Document',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: const Text('Approve this document?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
            ),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await dp.updateDocumentStatus(
      documentId: doc.documentId,
      action: 'approve',
    );
    if (mounted) {
      if (ok) {
        // Sync the isVerified badge in the profile header.
        context.read<UserDetailsProvider>().fetchUserDetails(
          widget.userId,
          widget.myId,
        );
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'Document approved' : 'Failed: ${dp.error}'),
          backgroundColor: ok
              ? const Color(0xFF10B981)
              : const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  Future<void> _rejectDocFromProfile(Document doc, DocumentsProvider dp) async {
    _rejectDocCtrl.clear();
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          'Reject Document',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Reason for rejection:',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _rejectDocCtrl,
              maxLines: 3,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Enter rejection reasonâ€¦',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (_rejectDocCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a rejection reason'),
                    backgroundColor: Color(0xFFEF4444),
                  ),
                );
                return;
              }
              Navigator.pop(context);
              if (!mounted) return;
              final ok = await dp.updateDocumentStatus(
                documentId: doc.documentId,
                action: 'reject',
                rejectReason: _rejectDocCtrl.text.trim(),
              );
              if (mounted) {
                if (ok) {
                  // Sync the isVerified badge in the profile header.
                  context.read<UserDetailsProvider>().fetchUserDetails(
                    widget.userId,
                    widget.myId,
                  );
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      ok ? 'Document rejected' : 'Failed: ${dp.error}',
                    ),
                    backgroundColor: ok
                        ? const Color(0xFFF59E0B)
                        : const Color(0xFFEF4444),
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.all(16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }

  // â”€â”€ loading / error â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildLoading() => const Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 44,
          height: 44,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation<Color>(_kPrimary),
          ),
        ),
        SizedBox(height: 16),
        Text(
          'Loading Profileâ€¦',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: Colors.grey,
          ),
        ),
      ],
    ),
  );

  Widget _buildError(UserDetailsProvider prov) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
          const SizedBox(height: 16),
          Text(
            prov.error,
            style: const TextStyle(fontSize: 15, color: Colors.red),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry'),
            onPressed: () => prov.fetchUserDetails(widget.userId, widget.myId),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    ),
  );

  // â”€â”€ build â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildBody(UserDetailsProvider provider, UserDetailsData data) {
    final p = data.personalDetail;
    final contact = data.contactDetail.withFallback(
      email: widget.email,
      phone: widget.phone,
      whatsapp: widget.whatsapp,
    );
    return SingleChildScrollView(
      controller: _pageScrollController,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black.withOpacity(0.06)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _buildHeader(p, contact),
                _buildGalleryReview(provider),
                const Divider(height: 1, thickness: 1),
                Container(key: _personalKey, child: _buildPersonal(p)),
                const Divider(height: 1, thickness: 1),
                Container(key: _educationKey, child: _buildEducation(p)),
                const Divider(height: 1, thickness: 1),
                Container(
                  key: _familyKey,
                  child: _buildFamily(data.familyDetail),
                ),
                const Divider(height: 1, thickness: 1),
                Container(
                  key: _lifestyleKey,
                  child: _buildLifestyle(data.lifestyle),
                ),
                const Divider(height: 1, thickness: 1),
                Container(
                  key: _partnerKey,
                  child: _buildPartner(data.partner, provider.partnerMatch),
                ),
                const Divider(height: 1, thickness: 1),
                UserPackageSection(userId: widget.userId),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<UserDetailsProvider>();

    return Scaffold(
      backgroundColor: _kPageBg,
      appBar: AppBar(
        title: const Text(
          'User Profile',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.grey.shade800,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () =>
                provider.fetchUserDetails(widget.userId, widget.myId),
          ),
        ],
      ),
      body: provider.isLoading
          ? _buildLoading()
          : provider.error.isNotEmpty
          ? _buildError(provider)
          : provider.userDetails != null
          ? _buildBody(provider, provider.userDetails!)
          : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.person_off, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  const Text(
                    'No data available',
                    style: TextStyle(fontSize: 15, color: Colors.grey),
                  ),
                ],
              ),
            ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Gallery Lightbox â€” full-size viewer with prev/next navigation
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _GalleryLightbox extends StatefulWidget {
  const _GalleryLightbox({required this.photos, required this.initialIndex});

  final List<UserGalleryPhoto> photos;
  final int initialIndex;

  @override
  State<_GalleryLightbox> createState() => _GalleryLightboxState();
}

class _GalleryLightboxState extends State<_GalleryLightbox> {
  late int _index;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.photos.length - 1);
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int newIndex) {
    final clamped = newIndex.clamp(0, widget.photos.length - 1);
    _pageController.animateToPage(
      clamped,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
    setState(() => _index = clamped);
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return const Color(0xFF10B981);
      case 'rejected':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFFF59E0B);
    }
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photos[_index];
    final hasPrev = _index > 0;
    final hasNext = _index < widget.photos.length - 1;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0B1220),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.16)),
            ),
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Index counter
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${_index + 1} / ${widget.photos.length}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                // Photo viewer (PageView for swipe support)
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 920,
                    maxHeight: 560,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: widget.photos.length,
                      onPageChanged: (i) => setState(() => _index = i),
                      itemBuilder: (_, idx) {
                        final p = widget.photos[idx];
                        return InteractiveViewer(
                          minScale: 1,
                          maxScale: 5,
                          child: Image.network(
                            p.imageUrl,
                            fit: BoxFit.contain,
                            loadingBuilder: (_, child, progress) {
                              if (progress == null) return child;
                              return const SizedBox(
                                height: 280,
                                child: Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white54,
                                  ),
                                ),
                              );
                            },
                            errorBuilder: (_, __, ___) => const SizedBox(
                              height: 280,
                              child: Center(
                                child: Icon(
                                  Icons.broken_image,
                                  size: 54,
                                  color: Colors.white38,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                // Status + reason
                if (photo.status.isNotEmpty ||
                    (photo.rejectReason ?? '').isNotEmpty)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _statusColor(photo.status),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              photo.status.toUpperCase(),
                              style: TextStyle(
                                color: _statusColor(photo.status),
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        if ((photo.rejectReason ?? '').isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            photo.rejectReason!,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11.5,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
          // Close button
          Positioned(
            top: 4,
            right: 4,
            child: Material(
              color: Colors.black.withOpacity(0.40),
              shape: const CircleBorder(),
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 18),
                splashRadius: 18,
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
          // Prev arrow
          if (hasPrev)
            Positioned(
              left: -18,
              top: 0,
              bottom: 0,
              child: Center(
                child: Material(
                  color: Colors.black.withOpacity(0.55),
                  shape: const CircleBorder(),
                  child: IconButton(
                    icon: const Icon(
                      Icons.chevron_left_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                    splashRadius: 22,
                    onPressed: () => _goTo(_index - 1),
                  ),
                ),
              ),
            ),
          // Next arrow
          if (hasNext)
            Positioned(
              right: -18,
              top: 0,
              bottom: 0,
              child: Center(
                child: Material(
                  color: Colors.black.withOpacity(0.55),
                  shape: const CircleBorder(),
                  child: IconButton(
                    icon: const Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                    splashRadius: 22,
                    onPressed: () => _goTo(_index + 1),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
