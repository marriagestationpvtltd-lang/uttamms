import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:ms2026/Auth/Screen/signupscreen6.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../ReUsable/dropdownwidget.dart';
import '../../ReUsable/registration_progress.dart';
import '../../ReUsable/enhanced_form_fields.dart';
import '../../constant/app_colors.dart';
import '../../service/updatepage.dart';
import 'package:ms2026/config/app_endpoints.dart';

class FamilyDetailsPage extends StatefulWidget {
  const FamilyDetailsPage({super.key});

  @override
  State<FamilyDetailsPage> createState() => _FamilyDetailsPageState();
}

class _FamilyDetailsPageState extends State<FamilyDetailsPage> {
  bool submitted = false;
  bool isLoading = false;

  // Form variables
  String? _selectedFamilyType;
  String? _selectedFamilyBackground;
  String? _fatherStatus;
  String? _motherStatus;
  String? _hasOtherFamilyMembers = '';
  String? _selectedFamilyOrigin;

  // Father details
  final TextEditingController _fatherNameController = TextEditingController();
  String? _fatherEducation;
  String? _fatherOccupation;

  // Mother details
  final TextEditingController _motherCastController = TextEditingController();
  final TextEditingController _motherContactController = TextEditingController();
  String? _motherEducation;
  String? _motherOccupation;

  // Other family members
  final List<FamilyMember> _familyMembers = [];
  String? _selectedMemberType;
  String? _selectedMemberMaritalStatus;
  String? _memberLivesWithUs = '';

  // Animation

  // Dropdown options
  final List<String> _familyTypeOptions = [
    'Joint Family',
    'Nuclear Family',
    'Single Parent Family',
    'Extended Family',
    'Other'
  ];

  final List<String> _familyBackgroundOptions = [
    'Upper Class',
    'Upper Middle Class',
    'Middle Class',
    'Lower Middle Class',
    'Lower Class',
    'Other'
  ];

  final List<String> _familyOriginOptions = [
    'Urban',
    'Suburban',
    'Rural',
    'Metropolitan',
    'Other'
  ];

  final List<String> _educationOptions = [
    'Illiterate',
    'Primary School',
    'Secondary School',
    'High School',
    'Diploma',
    'Bachelor',
    'Master',
    'PhD',
    'Other'
  ];

  final List<String> _occupationOptions = [
    'Government Job',
    'Private Job',
    'Business',
    'Farmer',
    'Teacher',
    'Doctor',
    'Engineer',
    'Student',
    'Housewife',
    'Retired',
    'Unemployed',
    'Other'
  ];

  final List<String> _memberTypeOptions = [
    'Brother',
    'Sister',
    'Grandfather',
    'Grandmother',
    'Uncle',
    'Aunt',
    'Cousin',
    'Other Relative'
  ];

  final List<String> _maritalStatusOptions = [
    'Single',
    'Married',
    'Divorced',
    'Widowed'
  ];

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _fatherNameController.dispose();
    _motherCastController.dispose();
    _motherContactController.dispose();
    super.dispose();
  }

  bool get _canContinue {
    return _selectedFamilyType != null &&
        _selectedFamilyBackground != null &&
        _fatherStatus != null &&
        _motherStatus != null &&
        _selectedFamilyOrigin != null &&
        _hasOtherFamilyMembers != null &&
        _hasOtherFamilyMembers!.isNotEmpty &&
        (_hasOtherFamilyMembers == 'NO' || _familyMembers.isNotEmpty) &&
        (_fatherStatus != 'Lives with us' ||
            (_fatherNameController.text.isNotEmpty &&
                _fatherEducation != null &&
                _fatherOccupation != null)) &&
        (_motherStatus != 'Lives with us' ||
            (_motherCastController.text.isNotEmpty &&
                _motherEducation != null &&
                _motherOccupation != null));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Stack(
          children: [
            RegistrationStepContainer(
              onBack: () => Navigator.pop(context),
              onStepBack: () => Navigator.pop(context), // Allow step-by-step back navigation
              onContinue: _validateAndSubmit,
              isLoading: isLoading,
              canContinue: _canContinue,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  RegistrationStepHeader(
                    title: 'Family Details',
                    subtitle: 'Tell us about your family background',
                    currentStep: 6,
                    totalSteps: 11,
                    onBack: () => Navigator.pop(context),
                    onStepBack: () => Navigator.pop(context), // Allow step-by-step back navigation
                  ),
                  const SizedBox(height: 32),

                  // Family Type Section
                  SectionHeader(
                    title: 'Family Information',
                    subtitle: 'Basic family structure and background',
                    icon: Icons.family_restroom_rounded,
                  ),
                  const SizedBox(height: 20),

                  // Family Type
                  EnhancedDropdown<String>(
                    label: 'Family Type',
                    value: _selectedFamilyType,
                    items: _familyTypeOptions,
                    itemLabel: (item) => item,
                    hint: 'Select family type',
                    isRequired: true,
                    hasError: submitted && _selectedFamilyType == null,
                    errorText: submitted && _selectedFamilyType == null
                        ? 'Please select family type'
                        : null,
                    onChanged: (value) {
                      setState(() {
                        _selectedFamilyType = value;
                      });
                    },
                    prefixIcon: Icons.home_rounded,
                  ),
                  const SizedBox(height: 20),

                  // Family Background
                  EnhancedDropdown<String>(
                    label: 'Family Background',
                    value: _selectedFamilyBackground,
                    items: _familyBackgroundOptions,
                    itemLabel: (item) => item,
                    hint: 'Select family background',
                    isRequired: true,
                    hasError: submitted && _selectedFamilyBackground == null,
                    errorText: submitted && _selectedFamilyBackground == null
                        ? 'Please select family background'
                        : null,
                    onChanged: (value) {
                      setState(() {
                        _selectedFamilyBackground = value;
                      });
                    },
                    prefixIcon: Icons.account_balance_rounded,
                  ),
                  const SizedBox(height: 20),

                  // Family Origin
                  EnhancedDropdown<String>(
                    label: 'Family Origin',
                    value: _selectedFamilyOrigin,
                    items: _familyOriginOptions,
                    itemLabel: (item) => item,
                    hint: 'Select family origin',
                    isRequired: true,
                    hasError: submitted && _selectedFamilyOrigin == null,
                    errorText: submitted && _selectedFamilyOrigin == null
                        ? 'Please select family origin'
                        : null,
                    onChanged: (value) {
                      setState(() {
                        _selectedFamilyOrigin = value;
                      });
                    },
                    prefixIcon: Icons.location_city_rounded,
                  ),
                  const SizedBox(height: 32),

                  // Father Section
                  const Divider(height: 1, thickness: 1, color: AppColors.border),
                  const SizedBox(height: 32),

                  SectionHeader(
                    title: "Father's Information",
                    subtitle: 'Details about your father',
                    icon: Icons.person_rounded,
                  ),
                  const SizedBox(height: 20),

                  // Father Status
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12, left: 4),
                    child: Row(
                      children: [
                        Text(
                          'Father Status',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        SizedBox(width: 4),
                        Text(
                          '*',
                          style: TextStyle(
                            color: AppColors.error,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: EnhancedRadioOption<String>(
                          label: 'Lives with us',
                          value: 'Lives with us',
                          groupValue: _fatherStatus,
                          onChanged: (value) {
                            FocusScope.of(context).unfocus();
                            setState(() {
                              _fatherStatus = value;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: EnhancedRadioOption<String>(
                          label: 'Passed Away',
                          value: 'Passed Away',
                          groupValue: _fatherStatus,
                          onChanged: (value) {
                            FocusScope.of(context).unfocus();
                            setState(() {
                              _fatherStatus = value;
                            });
                          },
                        ),
                      ),
                    ],
                  ),

                  if (_fatherStatus == "Lives with us") ...[
                    const SizedBox(height: 20),
                    EnhancedTextField(
                      label: "Father's Name",
                      controller: _fatherNameController,
                      hint: "Enter father's name",
                      hasError: submitted && _fatherNameController.text.isEmpty,
                      errorText: submitted && _fatherNameController.text.isEmpty
                          ? 'Please enter father\'s name'
                          : null,
                      prefixIcon: Icons.badge_rounded,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => FocusScope.of(context).unfocus(),
                      validator: (value) => value?.isEmpty == true ? '' : null,
                    ),
                    const SizedBox(height: 20),
                    EnhancedDropdown<String>(
                      label: 'Education',
                      value: _fatherEducation,
                      items: _educationOptions,
                      itemLabel: (item) => item,
                      hint: 'Select education',
                      isRequired: true,
                      hasError: submitted && _fatherEducation == null,
                      errorText: submitted && _fatherEducation == null
                          ? 'Please select education'
                          : null,
                      onChanged: (value) {
                        setState(() {
                          _fatherEducation = value;
                        });
                      },
                      prefixIcon: Icons.school_rounded,
                    ),
                    const SizedBox(height: 20),
                    EnhancedDropdown<String>(
                      label: 'Occupation',
                      value: _fatherOccupation,
                      items: _occupationOptions,
                      itemLabel: (item) => item,
                      hint: 'Select occupation',
                      isRequired: true,
                      hasError: submitted && _fatherOccupation == null,
                      errorText: submitted && _fatherOccupation == null
                          ? 'Please select occupation'
                          : null,
                      onChanged: (value) {
                        setState(() {
                          _fatherOccupation = value;
                        });
                      },
                      prefixIcon: Icons.work_rounded,
                    ),
                  ],

                  const SizedBox(height: 32),

                  // Mother Section
                  const Divider(height: 1, thickness: 1, color: AppColors.border),
                  const SizedBox(height: 32),

                  SectionHeader(
                    title: "Mother's Information",
                    subtitle: 'Details about your mother',
                    icon: Icons.person_rounded,
                  ),
                  const SizedBox(height: 20),

                  // Mother Status
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12, left: 4),
                    child: Row(
                      children: [
                        Text(
                          'Mother Status',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        SizedBox(width: 4),
                        Text(
                          '*',
                          style: TextStyle(
                            color: AppColors.error,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: EnhancedRadioOption<String>(
                          label: 'Lives with us',
                          value: 'Lives with us',
                          groupValue: _motherStatus,
                          onChanged: (value) {
                            FocusScope.of(context).unfocus();
                            setState(() {
                              _motherStatus = value;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: EnhancedRadioOption<String>(
                          label: 'Passed Away',
                          value: 'Passed Away',
                          groupValue: _motherStatus,
                          onChanged: (value) {
                            FocusScope.of(context).unfocus();
                            setState(() {
                              _motherStatus = value;
                            });
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),
                  EnhancedTextField(
                    label: "Family Contact Number",
                    controller: _motherContactController,
                    hint: "Enter family contact number",
                    keyboardType: TextInputType.phone,
                    prefixIcon: Icons.phone_rounded,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => FocusScope.of(context).unfocus(),
                  ),

                  if (_motherStatus == "Lives with us") ...[
                    const SizedBox(height: 20),
                    EnhancedTextField(
                      label: "Mother's Caste",
                      controller: _motherCastController,
                      hint: "Enter mother's caste",
                      hasError: submitted && _motherCastController.text.isEmpty,
                      errorText: submitted && _motherCastController.text.isEmpty
                          ? 'Please enter mother\'s caste'
                          : null,
                      prefixIcon: Icons.badge_rounded,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => FocusScope.of(context).unfocus(),
                      validator: (value) => value?.isEmpty == true ? '' : null,
                    ),
                    const SizedBox(height: 20),
                    EnhancedDropdown<String>(
                      label: 'Education',
                      value: _motherEducation,
                      items: _educationOptions,
                      itemLabel: (item) => item,
                      hint: 'Select education',
                      isRequired: true,
                      hasError: submitted && _motherEducation == null,
                      errorText: submitted && _motherEducation == null
                          ? 'Please select education'
                          : null,
                      onChanged: (value) {
                        setState(() {
                          _motherEducation = value;
                        });
                      },
                      prefixIcon: Icons.school_rounded,
                    ),
                    const SizedBox(height: 20),
                    EnhancedDropdown<String>(
                      label: 'Occupation',
                      value: _motherOccupation,
                      items: _occupationOptions,
                      itemLabel: (item) => item,
                      hint: 'Select occupation',
                      isRequired: true,
                      hasError: submitted && _motherOccupation == null,
                      errorText: submitted && _motherOccupation == null
                          ? 'Please select occupation'
                          : null,
                      onChanged: (value) {
                        setState(() {
                          _motherOccupation = value;
                        });
                      },
                      prefixIcon: Icons.work_rounded,
                    ),
                  ],

                  const SizedBox(height: 32),

                  // Other Family Members Section
                  const Divider(height: 1, thickness: 1, color: AppColors.border),
                  const SizedBox(height: 32),

                  SectionHeader(
                    title: 'Other Family Members',
                    subtitle: 'Add siblings and other family members',
                    icon: Icons.groups_rounded,
                  ),
                  const SizedBox(height: 20),

                  // Do you have other family members
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12, left: 4),
                    child: Row(
                      children: [
                        Text(
                          'Do You Have Any Other Family Member?',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        SizedBox(width: 4),
                        Text(
                          '*',
                          style: TextStyle(
                            color: AppColors.error,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: EnhancedRadioOption<String>(
                          label: 'Yes',
                          value: 'Yes',
                          groupValue: _hasOtherFamilyMembers,
                          onChanged: (value) {
                            setState(() {
                              _hasOtherFamilyMembers = value;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: EnhancedRadioOption<String>(
                          label: 'No',
                          value: 'NO',
                          groupValue: _hasOtherFamilyMembers,
                          onChanged: (value) {
                            setState(() {
                              _hasOtherFamilyMembers = value;
                              _familyMembers.clear();
                              _selectedMemberType = null;
                              _selectedMemberMaritalStatus = null;
                              _memberLivesWithUs = null;
                            });
                          },
                        ),
                      ),
                    ],
                  ),

                  if (_hasOtherFamilyMembers == 'Yes') ...[
                    const SizedBox(height: 24),

                    // Add Member Card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.primary.withOpacity(0.03),
                            AppColors.secondary.withOpacity(0.03),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.primary.withOpacity(0.1),
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.person_add_rounded,
                                color: AppColors.primary,
                                size: 24,
                              ),
                              SizedBox(width: 12),
                              Text(
                                'Add Family Member',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          EnhancedDropdown<String>(
                            label: 'Member Type',
                            value: _selectedMemberType,
                            items: _memberTypeOptions,
                            itemLabel: (item) => item,
                            hint: 'Select family member type',
                            isRequired: true,
                            hasError:
                                submitted && _familyMembers.isEmpty && _selectedMemberType == null,
                            errorText: submitted &&
                                    _familyMembers.isEmpty &&
                                    _selectedMemberType == null
                                ? 'Please select member type'
                                : null,
                            onChanged: (value) {
                              setState(() {
                                _selectedMemberType = value;
                              });
                            },
                            prefixIcon: Icons.people_outline_rounded,
                          ),
                          const SizedBox(height: 16),
                          EnhancedDropdown<String>(
                            label: 'Marital Status',
                            value: _selectedMemberMaritalStatus,
                            items: _maritalStatusOptions,
                            itemLabel: (item) => item,
                            hint: 'Select marital status',
                            isRequired: true,
                            hasError: submitted &&
                                _familyMembers.isEmpty &&
                                _selectedMemberMaritalStatus == null,
                            errorText: submitted &&
                                    _familyMembers.isEmpty &&
                                    _selectedMemberMaritalStatus == null
                                ? 'Please select marital status'
                                : null,
                            onChanged: (value) {
                              setState(() {
                                _selectedMemberMaritalStatus = value;
                              });
                            },
                            prefixIcon: Icons.favorite_rounded,
                          ),
                          const SizedBox(height: 16),
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12, left: 4),
                            child: Row(
                              children: [
                                Text(
                                  'Lives With Us?',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                SizedBox(width: 4),
                                Text(
                                  '*',
                                  style: TextStyle(
                                    color: AppColors.error,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: EnhancedRadioOption<String>(
                                  label: 'Yes',
                                  value: 'Yes',
                                  groupValue: _memberLivesWithUs,
                                  onChanged: (value) {
                                    setState(() {
                                      _memberLivesWithUs = value;
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: EnhancedRadioOption<String>(
                                  label: 'No',
                                  value: 'NO',
                                  groupValue: _memberLivesWithUs,
                                  onChanged: (value) {
                                    setState(() {
                                      _memberLivesWithUs = value;
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Container(
                            decoration: BoxDecoration(
                              gradient: AppColors.primaryGradient,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withOpacity(0.3),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: _addFamilyMember,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.add, color: AppColors.white, size: 22),
                                      SizedBox(width: 8),
                                      Text(
                                        'Add Member',
                                        style: TextStyle(
                                          color: AppColors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Added Family Members List
                    if (_familyMembers.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12, left: 4),
                        child: Text(
                          'Added Members',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      ..._familyMembers.asMap().entries.map((entry) {
                        int index = entry.key;
                        FamilyMember member = entry.value;
                        return _buildFamilyMemberCard(member, index);
                      }).toList(),
                    ],

                    // Show warning if no members added
                    if (_familyMembers.isEmpty &&
                        submitted &&
                        _hasOtherFamilyMembers == 'Yes')
                      Container(
                        margin: const EdgeInsets.only(top: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.error.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.error.withOpacity(0.2),
                            width: 1,
                          ),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.warning_rounded, color: AppColors.error, size: 20),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Please add at least one family member or select \'No\'',
                                style: TextStyle(
                                  color: AppColors.error,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),

            // Loading overlay
            if (isLoading)
              Container(
                color: Colors.black.withOpacity(0.3),
                child: const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFamilyMemberCard(FamilyMember member, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.border,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowLight,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    color: AppColors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                // Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        member.type,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.favorite_rounded,
                            size: 14,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            member.maritalStatus,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            member.livesWithUs == 'Yes'
                                ? Icons.home_rounded
                                : Icons.home_work_rounded,
                            size: 14,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Lives with us: ${member.livesWithUs}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Delete button
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
                    onPressed: () => _removeFamilyMember(index),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _addFamilyMember() {
    setState(() {
      submitted = true;
    });

    if (_selectedMemberType == null) {
      _showError('Please select member type');
      return;
    }

    if (_selectedMemberMaritalStatus == null) {
      _showError('Please select marital status');
      return;
    }

    if (_memberLivesWithUs == null) {
      _showError('Please select if member lives with you');
      return;
    }

    setState(() {
      _familyMembers.add(FamilyMember(
        type: _selectedMemberType!,
        maritalStatus: _selectedMemberMaritalStatus!,
        livesWithUs: _memberLivesWithUs!,
      ));

      // Reset form
      _selectedMemberType = null;
      _selectedMemberMaritalStatus = null;
      _memberLivesWithUs = null;
      submitted = false;
    });

    _showSuccess('Family member added successfully!');
  }

  void _removeFamilyMember(int index) {
    setState(() {
      _familyMembers.removeAt(index);
    });
    _showSuccess('Family member removed');
  }

  void _validateAndSubmit() async {
    setState(() {
      submitted = true;
    });

    if (_selectedFamilyType == null) {
      _showError("Please select family type");
      return;
    }

    if (_selectedFamilyBackground == null) {
      _showError("Please select family background");
      return;
    }

    if (_selectedFamilyOrigin == null) {
      _showError("Please select family origin");
      return;
    }

    if (_fatherStatus == null) {
      _showError("Please select father status");
      return;
    }

    if (_fatherStatus == "Lives with us") {
      if (_fatherNameController.text.isEmpty) {
        _showError("Please enter father's name");
        return;
      }
      if (_fatherEducation == null) {
        _showError("Please select father's education");
        return;
      }
      if (_fatherOccupation == null) {
        _showError("Please select father's occupation");
        return;
      }
    }

    if (_motherStatus == null) {
      _showError("Please select mother status");
      return;
    }

    if (_motherStatus == "Lives with us") {
      if (_motherCastController.text.isEmpty) {
        _showError("Please enter mother's caste");
        return;
      }
      if (_motherEducation == null) {
        _showError("Please select mother's education");
        return;
      }
      if (_motherOccupation == null) {
        _showError("Please select mother's occupation");
        return;
      }
    }

    if (_hasOtherFamilyMembers == null || _hasOtherFamilyMembers!.isEmpty) {
      _showError("Please select if you have other family members");
      return;
    }

    if (_hasOtherFamilyMembers == 'Yes' && _familyMembers.isEmpty) {
      _showError("Please add at least one family member or select 'No'");
      return;
    }

    setState(() {
      isLoading = true;
    });

    await _submitFamilyData();

    setState(() {
      isLoading = false;
    });
  }

  _submitFamilyData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');

      if (userDataString == null) {
        _showError("User data not found. Please login again.");
        return;
      }

      final userData = jsonDecode(userDataString);
      final userId = int.tryParse(userData["id"]?.toString() ?? '0');

      if (userId == null || userId == 0) {
        _showError("Invalid user ID");
        return;
      }

      // Prepare family members data
      List<Map<String, String>> members = _familyMembers.map((m) {
        return {
          "membertype": m.type,
          "maritalstatus": m.maritalStatus,
          "livestatus": m.livesWithUs,
        };
      }).toList();

      // Prepare request body with proper null handling
      Map<String, String> requestBody = {
        "userid": userId.toString(),
        "familytype": _selectedFamilyType ?? "",
        "familybackground": _selectedFamilyBackground ?? "",
        "fatherstatus": _fatherStatus ?? "",
        "fathername":
            _fatherStatus == "Lives with us" ? (_fatherNameController.text.trim()) : "",
        "fathereducation": _fatherStatus == "Lives with us" ? (_fatherEducation ?? "") : "",
        "fatheroccupation": _fatherStatus == "Lives with us" ? (_fatherOccupation ?? "") : "",
        "motherstatus": _motherStatus ?? "",
        "mothercaste":
            _motherStatus == "Lives with us" ? (_motherCastController.text.trim()) : "",
        "mothercontact": _motherContactController.text.trim(),
        "mothereducation": _motherStatus == "Lives with us" ? (_motherEducation ?? "") : "",
        "motheroccupation": _motherStatus == "Lives with us" ? (_motherOccupation ?? "") : "",
        "familyorigin": _selectedFamilyOrigin ?? "",
        "members": jsonEncode(members),
      };

      var response = await http
          .post(
            Uri.parse("${kApiBaseUrl}/Api2/updatefamily.php"),
            body: requestBody,
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        var data;
        try {
          data = jsonDecode(response.body);
        } catch (e) {
          _showError("Invalid response from server");
          return;
        }

        if (data['status'] == 'success') {
          bool updated = await UpdateService.updatePageNumber(
            userId: userId.toString(),
            pageNo: 4,
          );

          if (updated) {
            _showSuccess("Family details saved successfully!");
            Future.delayed(const Duration(seconds: 1), () {
              if (mounted) {
                Navigator.push(context,
                    MaterialPageRoute(builder: (context) => EducationCareerPage()));
              }
            });
          } else {
            _showError("Failed to update progress");
          }
        } else {
          _showError(data['message'] ?? "Failed to save family details");
        }
      } else {
        _showError("Server error: ${response.statusCode}");
      }
    } on http.ClientException catch (e) {
      _showError("Network error: ${e.message}");
    } on TimeoutException catch (e) {
      _showError("Request timeout. Please try again.");
    } catch (e) {
      _showError("Unexpected error: $e");
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

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: AppColors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

class FamilyMember {
  final String type;
  final String maritalStatus;
  final String livesWithUs;

  FamilyMember({
    required this.type,
    required this.maritalStatus,
    required this.livesWithUs,
  });
}
