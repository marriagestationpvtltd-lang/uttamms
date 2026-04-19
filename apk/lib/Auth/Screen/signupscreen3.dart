import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ms2026/Auth/Screen/signupscreen4.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../ReUsable/dropdownwidget.dart';
import '../../ReUsable/registration_progress.dart';
import '../../ReUsable/enhanced_form_fields.dart';
import '../../constant/app_colors.dart';
import '../../service/updatepage.dart';
import 'package:ms2026/config/app_endpoints.dart';

class CommunityDetailsPage extends StatefulWidget {
  const CommunityDetailsPage({super.key});

  @override
  State<CommunityDetailsPage> createState() => _CommunityDetailsPageState();
}

class _CommunityDetailsPageState extends State<CommunityDetailsPage> {
  // Form variables
  String? _selectedReligion;
  bool submitted = false;

  String? _selectedCommunity;
  String? _selectedSubcommunity;
  String? _selectedCastLanguage;

  bool _isLoading = false;

  // Sample data for dropdowns
  final List<String> _religionOptions = [
    'Hindu',
    'Muslim',
    'Christian',
    'Sikh',
    'Buddhist',
    'Jain',
    'Other'
  ];

  final List<String> _communityOptions = [
    'Brahmin',
    'Chhetri',
    'Newar',
    'Gurung',
    'Tamang',
    'Rai',
    'Limbu',
    'Magar',
    'Tharu',
    'Sherpa',
    'Other'
  ];

  final List<String> _subcommunityOptions = [
    'Purbiya',
    'Kumai',
    'Upadhaya',
    'Jaisi',
    'Other'
  ];

  final List<String> _castLanguageOptions = [
    'Nepali',
    'Maithili',
    'Bhojpuri',
    'Tharu',
    'Tamang',
    'Newari',
    'Magar',
    'Gurung',
    'Limbu',
    'Rai',
    'Sherpa',
    'Other'
  ];

  // ------------------ ID Mapping ------------------
  final Map<String, int> religionMap = {
    'Hindu': 1,
    'Muslim': 2,
    'Christian': 3,
    'Sikh': 4,
    'Buddhist': 5,
    'Jain': 6,
    'Other': 7,
  };

  final Map<String, int> communityMap = {
    'Brahmin': 1,
    'Chhetri': 2,
    'Newar': 3,
    'Gurung': 4,
    'Tamang': 5,
    'Rai': 6,
    'Limbu': 7,
    'Magar': 8,
    'Tharu': 9,
    'Sherpa': 10,
    'Other': 11,
  };

  final Map<String, int> subcommunityMap = {
    'Purbiya': 1,
    'Kumai': 2,
    'Upadhaya': 3,
    'Jaisi': 4,
    'Other': 5,
  };

  bool get _canContinue {
    return _selectedReligion != null &&
        _selectedCommunity != null &&
        _selectedSubcommunity != null &&
        _selectedCastLanguage != null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: RegistrationStepContainer(
          onBack: () => Navigator.pop(context),
          onStepBack: () => Navigator.pop(context), // Allow step-by-step back navigation
          onContinue: _validateAndSubmit,
          isLoading: _isLoading,
          canContinue: _canContinue,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              RegistrationStepHeader(
                title: 'Community Details',
                subtitle: 'Tell us about your religious and community background',
                currentStep: 4,
                totalSteps: 11,
                onBack: () => Navigator.pop(context),
                onStepBack: () => Navigator.pop(context), // Allow step-by-step back navigation
              ),
              const SizedBox(height: 32),

              // Religious Section
              SectionHeader(
                title: 'Religious Information',
                subtitle: 'Your religious and cultural details',
                icon: Icons.temple_hindu_rounded,
              ),
              const SizedBox(height: 20),

              // Religion Dropdown
              EnhancedDropdown<String>(
                label: 'Religion',
                value: _selectedReligion,
                items: _religionOptions,
                itemLabel: (item) => item,
                hint: 'Select your religion',
                isRequired: true,
                hasError: submitted && _selectedReligion == null,
                errorText: submitted && _selectedReligion == null
                    ? 'Please select your religion'
                    : null,
                onChanged: (value) {
                  setState(() {
                    _selectedReligion = value;
                  });
                },
                prefixIcon: Icons.self_improvement_rounded,
              ),
              const SizedBox(height: 20),

              // Community Dropdown
              EnhancedDropdown<String>(
                label: 'Community',
                value: _selectedCommunity,
                items: _communityOptions,
                itemLabel: (item) => item,
                hint: 'Select your community',
                isRequired: true,
                hasError: submitted && _selectedCommunity == null,
                errorText: submitted && _selectedCommunity == null
                    ? 'Please select your community'
                    : null,
                onChanged: (value) {
                  setState(() {
                    _selectedCommunity = value;
                    if (_selectedSubcommunity != null &&
                        !_subcommunityOptions.contains(_selectedSubcommunity)) {
                      _selectedSubcommunity = null;
                    }
                  });
                },
                prefixIcon: Icons.people_rounded,
              ),
              const SizedBox(height: 20),

              // Subcommunity Dropdown
              EnhancedDropdown<String>(
                label: 'Subcommunity',
                value: _selectedSubcommunity,
                items: _subcommunityOptions,
                itemLabel: (item) => item,
                hint: 'Select your subcommunity',
                isRequired: true,
                hasError: submitted && _selectedSubcommunity == null,
                errorText: submitted && _selectedSubcommunity == null
                    ? 'Please select your subcommunity'
                    : null,
                onChanged: (value) {
                  setState(() {
                    _selectedSubcommunity = value;
                  });
                },
                prefixIcon: Icons.family_restroom_rounded,
              ),
              const SizedBox(height: 32),

              // Language Section
              SectionHeader(
                title: 'Language Information',
                subtitle: 'Your primary caste language',
                icon: Icons.language_rounded,
              ),
              const SizedBox(height: 20),

              // Cast Language Dropdown
              EnhancedDropdown<String>(
                label: 'Caste Language',
                value: _selectedCastLanguage,
                items: _castLanguageOptions,
                itemLabel: (item) => item,
                hint: 'Select your caste language',
                isRequired: true,
                hasError: submitted && _selectedCastLanguage == null,
                errorText: submitted && _selectedCastLanguage == null
                    ? 'Please select your caste language'
                    : null,
                onChanged: (value) {
                  setState(() {
                    _selectedCastLanguage = value;
                  });
                },
                prefixIcon: Icons.translate_rounded,
              ),
              const SizedBox(height: 32),

              // Info Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary.withOpacity(0.05),
                      AppColors.secondary.withOpacity(0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primary.withOpacity(0.1),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.info_outline,
                        color: AppColors.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Your community details help us find the most compatible matches for you.',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          height: 1.4,
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
    );
  }

  // ------------------ Validation & Submit ------------------
  void _validateAndSubmit() async {
    setState(() {
      submitted = true;
    });

    if (_selectedReligion == null) {
      _showError("Please select religion");
      return;
    }
    if (_selectedCommunity == null) {
      _showError("Please select community");
      return;
    }
    if (_selectedSubcommunity == null) {
      _showError("Please select subcommunity");
      return;
    }
    if (_selectedCastLanguage == null) {
      _showError("Please select caste language");
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('user_data');
    final userData = jsonDecode(userDataString!);
    final userId = int.tryParse(userData["id"].toString());

    final result = await _updateReligionDetails(
      userId: userId!,
      religionId: religionMap[_selectedReligion!]!,
      communityId: communityMap[_selectedCommunity!]!,
      subCommunityId: subcommunityMap[_selectedSubcommunity!]!,
      castLanguage: _selectedCastLanguage!,
    );

    setState(() {
      _isLoading = false;
    });

    if (result['status'] == 'success') {
      bool updated = await UpdateService.updatePageNumber(
        userId: userId.toString(),
        pageNo: 2,
      );

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => LivingStatusPage()),
        );
      }
    } else {
      _showError(result['message'] ?? "Failed to save details");
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: AppColors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ------------------ API SERVICE ------------------
  Future<Map<String, dynamic>> _updateReligionDetails({
    required int userId,
    required int religionId,
    required int communityId,
    required int subCommunityId,
    required String castLanguage,
  }) async {
    final url = Uri.parse("${kApiBaseUrl}/Api2/update_religion.php");

    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {
          "user_id": userId.toString(),
          "religionId": religionId.toString(),
          "communityId": communityId.toString(),
          "subCommunityId": subCommunityId.toString(),
          "castlanguage": castLanguage,
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {
          "status": "error",
          "message": "Server returned status ${response.statusCode}"
        };
      }
    } catch (e) {
      return {"status": "error", "message": e.toString()};
    }
  }
}
