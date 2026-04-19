// Professional Redesigned Personal Details Page - Step 3
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:ms2026/Auth/Screen/signupscreen3.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../constant/app_colors.dart';
import '../../ReUsable/registration_progress.dart';
import '../../ReUsable/enhanced_form_fields.dart';
import '../../ReUsable/dropdownwidget.dart';
import '../../ReUsable/smart_scroll_behavior.dart';
import '../../service/personal_details_api.dart';
import '../../service/updatepage.dart';
import 'package:ms2026/config/app_endpoints.dart';

class PersonalDetailsPage extends StatefulWidget {
  const PersonalDetailsPage({super.key});

  @override
  State<PersonalDetailsPage> createState() => _PersonalDetailsPageState();
}

class _PersonalDetailsPageState extends State<PersonalDetailsPage>
    with SmartScrollBehavior {
  // Form state
  String? _selectedMaritalStatus;
  String? _selectedHeight;
  String? _selectedWeight;
  bool _hasSpecs = false;
  bool _hasDisability = false;
  String _childStatus = '';
  String _childLiveWith = '';
  final TextEditingController _disabilityController = TextEditingController();
  String? _selectedBloodGroup;
  String? _selectedComplexion;
  String? _selectedBodyType;

  // Validation
  bool _hasValidationErrors = false;
  Map<String, String?> _fieldErrors = {};
  bool _isSubmitting = false;

  // Animation

  // Dropdown options
  final List<String> _maritalStatusOptions = [
    'Still Unmarried',
    'Widowed',
    'Divorced',
    'Waiting Divorce',
  ];

  final List<String> _bloodGroupOptions = [
    'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'
  ];

  final List<String> _complexionOptions = [
    'Very Fair', 'Fair', 'Wheatish', 'Olive', 'Brown', 'Dark'
  ];

  final List<String> _bodyTypeOptions = [
    'Slim', 'Athletic', 'Average', 'Heavy', 'Muscular'
  ];

  late final List<String> _heightOptions;
  late final List<String> _weightOptions;

  @override
  void initState() {
    super.initState();

    // Cache large lists once to avoid repeated generation during build
    _heightOptions = List.generate(121, (index) {
      int cm = 100 + index;
      double totalInches = cm / 2.54;
      int feet = totalInches ~/ 12;
      int inches = (totalInches % 12).round();
      return "$cm cm ($feet' $inches\")";
    });
    _weightOptions = List.generate(121, (index) {
      int kg = 30 + index;
      return "$kg kg";
    });

  }

  @override
  void dispose() {
    _disabilityController.dispose();
    super.dispose();
  }

  // Validation
  bool _validateForm() {
    setState(() {
      _fieldErrors = {
        'maritalStatus': _selectedMaritalStatus == null ? 'Please select marital status' : null,
        'height': _selectedHeight == null ? 'Please select height' : null,
        'weight': _selectedWeight == null ? 'Please select weight' : null,
        'bloodGroup': _selectedBloodGroup == null ? 'Please select blood group' : null,
        'complexion': _selectedComplexion == null ? 'Please select complexion' : null,
        'bodyType': _selectedBodyType == null ? 'Please select body type' : null,
        'childStatus': (_selectedMaritalStatus == 'Divorced' || _selectedMaritalStatus == 'Widowed' || _selectedMaritalStatus == 'Waiting Divorce')
            && _childStatus.isEmpty ? 'Please select children status' : null,
        'childLiveWith': (_childStatus == 'One' || _childStatus == 'Two +')
            && _childLiveWith.isEmpty ? 'Please select where children live' : null,
      };
      _hasValidationErrors = _fieldErrors.values.any((error) => error != null);
    });

    return !_hasValidationErrors;
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _validateAndSubmit() async {
    if (!_validateForm()) {
      _showSnackBar('Please fill all required fields correctly', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');

      if (userDataString == null) {
        _showSnackBar('Session expired. Please login again', isError: true);
        setState(() => _isSubmitting = false);
        return;
      }

      final userData = jsonDecode(userDataString);
      final userId = int.tryParse(userData["id"].toString());

      if (userId == null) {
        _showSnackBar('Invalid user data', isError: true);
        setState(() => _isSubmitting = false);
        return;
      }

      final service = UserPersonalDetailService(
        baseUrl: '${kApiBaseUrl}/Api2/save_personal_detail.php',
      );

      final result = await service.saveUserPersonalDetail(
        userId: userId,
        maritalStatusId: _maritalStatusOptions.indexOf(_selectedMaritalStatus!) + 1,
        heightName: _selectedHeight,
        weightName: _selectedWeight,
        haveSpecs: _hasSpecs ? 1 : 0,
        anyDisability: _hasDisability ? 1 : 0,
        disability: _disabilityController.text.isNotEmpty ? _disabilityController.text : null,
        bloodGroup: _selectedBloodGroup,
        complexion: _selectedComplexion,
        bodyType: _selectedBodyType,
        aboutMe: 'Hello I am a MS User',
        childStatus: _childStatus.isNotEmpty ? _childStatus : null,
        childLiveWith: _childLiveWith.isNotEmpty ? _childLiveWith : null,
      );

      setState(() => _isSubmitting = false);

      if (result['status'] == 'success') {
        await UpdateService.updatePageNumber(
          userId: userId.toString(),
          pageNo: 1,
        );

        _showSnackBar('Personal details saved successfully!');

        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const CommunityDetailsPage()),
        );
      } else {
        _showSnackBar(result['message'] ?? "Something went wrong", isError: true);
      }
    } catch (e) {
      setState(() => _isSubmitting = false);
      _showSnackBar(e.toString(), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: RegistrationStepContainer(
            scrollController: scrollController,
            onContinue: _isSubmitting ? null : _validateAndSubmit,
            onBack: () => Navigator.pop(context),
            onStepBack: () => Navigator.pop(context), // Allow step-by-step back navigation
            continueText: 'Continue',
            canContinue: !_isSubmitting,
            isLoading: _isSubmitting,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                RegistrationStepHeader(
                  title: 'Personal Details',
                  subtitle: 'Share your personal information to help us find the perfect match for you.',
                  currentStep: 3,
                  totalSteps: 11,
                  onBack: () => Navigator.pop(context),
                  onStepBack: () => Navigator.pop(context), // Allow step-by-step back navigation
                ),

                const SizedBox(height: 32),

                // Marital Status Section
                SectionHeader(
                  title: 'Marital Status',
                  subtitle: 'Your current relationship status',
                  icon: Icons.favorite_outline,
                ),

                const SizedBox(height: 16),

                EnhancedDropdown<String>(
                  label: 'Marital Status',
                  value: _selectedMaritalStatus,
                  items: _maritalStatusOptions,
                  itemLabel: (status) => status,
                  hint: 'Select marital status',
                  prefixIcon: Icons.favorite_border,
                  hasError: _fieldErrors['maritalStatus'] != null,
                  errorText: _fieldErrors['maritalStatus'],
                  isRequired: true,
                  onChanged: (value) {
                    setState(() {
                      _selectedMaritalStatus = value;
                      if (_hasValidationErrors) {
                        _fieldErrors['maritalStatus'] = null;
                      }
                      // Reset child status if not divorced/widowed/waiting divorce
                      if (value != 'Divorced' && value != 'Widowed' && value != 'Waiting Divorce') {
                        _childStatus = '';
                        _childLiveWith = '';
                      }
                    });
                  },
                ),

                // Children Status (only for Divorced/Widowed/Waiting Divorce)
                if (_selectedMaritalStatus == 'Divorced' || _selectedMaritalStatus == 'Widowed' || _selectedMaritalStatus == 'Waiting Divorce') ...[
                  const SizedBox(height: 24),

                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8, left: 4),
                        child: Row(
                          children: [
                            Text(
                              'Children Status',
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
                              label: 'No Child',
                              value: 'No Child',
                              groupValue: _childStatus,
                              onChanged: (value) {
                                setState(() {
                                  _childStatus = value ?? '';
                                  _childLiveWith = '';
                                  if (_hasValidationErrors) {
                                    _fieldErrors['childStatus'] = null;
                                    _fieldErrors['childLiveWith'] = null;
                                  }
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: EnhancedRadioOption<String>(
                              label: 'One Child',
                              value: 'One',
                              groupValue: _childStatus,
                              onChanged: (value) {
                                setState(() {
                                  _childStatus = value ?? '';
                                  if (_hasValidationErrors) {
                                    _fieldErrors['childStatus'] = null;
                                  }
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      EnhancedRadioOption<String>(
                        label: 'Two or More Children',
                        value: 'Two +',
                        groupValue: _childStatus,
                        onChanged: (value) {
                          setState(() {
                            _childStatus = value ?? '';
                            if (_hasValidationErrors) {
                              _fieldErrors['childStatus'] = null;
                            }
                          });
                        },
                      ),
                      if (_fieldErrors['childStatus'] != null) ...[
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline,
                                size: 14,
                                color: AppColors.error,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _fieldErrors['childStatus']!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.error,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ],

                // Where children live (only if has children)
                if (_childStatus == 'One' || _childStatus == 'Two +') ...[
                  const SizedBox(height: 24),

                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8, left: 4),
                        child: Row(
                          children: [
                            Text(
                              'Children Live With',
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
                      Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: EnhancedRadioOption<String>(
                                  label: 'With Me',
                                  value: 'With Me',
                                  groupValue: _childLiveWith,
                                  icon: Icons.home,
                                  onChanged: (value) {
                                    setState(() {
                                      _childLiveWith = value ?? '';
                                      if (_hasValidationErrors) {
                                        _fieldErrors['childLiveWith'] = null;
                                      }
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: EnhancedRadioOption<String>(
                                  label: 'With Ex',
                                  value: 'With Ex Husband',
                                  groupValue: _childLiveWith,
                                  icon: Icons.person_outline,
                                  onChanged: (value) {
                                    setState(() {
                                      _childLiveWith = value ?? '';
                                      if (_hasValidationErrors) {
                                        _fieldErrors['childLiveWith'] = null;
                                      }
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          EnhancedRadioOption<String>(
                            label: 'Others',
                            value: 'Others',
                            groupValue: _childLiveWith,
                            icon: Icons.people_outline,
                            onChanged: (value) {
                              setState(() {
                                _childLiveWith = value ?? '';
                                if (_hasValidationErrors) {
                                  _fieldErrors['childLiveWith'] = null;
                                }
                              });
                            },
                          ),
                        ],
                      ),
                      if (_fieldErrors['childLiveWith'] != null) ...[
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline,
                                size: 14,
                                color: AppColors.error,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _fieldErrors['childLiveWith']!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.error,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ],

                const SizedBox(height: 32),

                // Physical Attributes Section
                SectionHeader(
                  title: 'Physical Attributes',
                  subtitle: 'Your physical characteristics',
                  icon: Icons.accessibility_new,
                ),

                const SizedBox(height: 16),

                // Height and Weight
                Row(
                  children: [
                    Expanded(
                      child: TypingDropdown<String>(
                        title: 'Height',
                        items: _heightOptions,
                        itemLabel: (height) => height,
                        hint: 'Select height',
                        selectedItem: _selectedHeight,
                        showError: _fieldErrors['height'] != null,
                        errorText: _fieldErrors['height'],
                        prefixIcon: Icons.height,
                        onChanged: (value) {
                          setState(() {
                            _selectedHeight = value;
                            if (_hasValidationErrors) {
                              _fieldErrors['height'] = null;
                            }
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TypingDropdown<String>(
                        title: 'Weight',
                        items: _weightOptions,
                        itemLabel: (weight) => weight,
                        hint: 'Select weight',
                        selectedItem: _selectedWeight,
                        showError: _fieldErrors['weight'] != null,
                        errorText: _fieldErrors['weight'],
                        prefixIcon: Icons.monitor_weight_outlined,
                        onChanged: (value) {
                          setState(() {
                            _selectedWeight = value;
                            if (_hasValidationErrors) {
                              _fieldErrors['weight'] = null;
                            }
                          });
                        },
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Blood Group
                EnhancedDropdown<String>(
                  label: 'Blood Group',
                  value: _selectedBloodGroup,
                  items: _bloodGroupOptions,
                  itemLabel: (group) => group,
                  hint: 'Select blood group',
                  prefixIcon: Icons.bloodtype,
                  hasError: _fieldErrors['bloodGroup'] != null,
                  errorText: _fieldErrors['bloodGroup'],
                  isRequired: true,
                  onChanged: (value) {
                    setState(() {
                      _selectedBloodGroup = value;
                      if (_hasValidationErrors) {
                        _fieldErrors['bloodGroup'] = null;
                      }
                    });
                  },
                ),

                const SizedBox(height: 16),

                // Complexion
                EnhancedDropdown<String>(
                  label: 'Complexion',
                  value: _selectedComplexion,
                  items: _complexionOptions,
                  itemLabel: (complexion) => complexion,
                  hint: 'Select complexion',
                  prefixIcon: Icons.face,
                  hasError: _fieldErrors['complexion'] != null,
                  errorText: _fieldErrors['complexion'],
                  isRequired: true,
                  onChanged: (value) {
                    setState(() {
                      _selectedComplexion = value;
                      if (_hasValidationErrors) {
                        _fieldErrors['complexion'] = null;
                      }
                    });
                  },
                ),

                const SizedBox(height: 16),

                // Body Type
                EnhancedDropdown<String>(
                  label: 'Body Type',
                  value: _selectedBodyType,
                  items: _bodyTypeOptions,
                  itemLabel: (bodyType) => bodyType,
                  hint: 'Select body type',
                  prefixIcon: Icons.fitness_center,
                  hasError: _fieldErrors['bodyType'] != null,
                  errorText: _fieldErrors['bodyType'],
                  isRequired: true,
                  onChanged: (value) {
                    setState(() {
                      _selectedBodyType = value;
                      if (_hasValidationErrors) {
                        _fieldErrors['bodyType'] = null;
                      }
                    });
                  },
                ),

                const SizedBox(height: 32),

                // Additional Information Section
                SectionHeader(
                  title: 'Additional Information',
                  subtitle: 'Specs and health information',
                  icon: Icons.medical_information_outlined,
                ),

                const SizedBox(height: 16),

                // Specs/Lenses
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8, left: 4),
                      child: Text(
                        'Do you wear specs/lenses?',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: EnhancedRadioOption<bool>(
                            label: 'Yes',
                            value: true,
                            groupValue: _hasSpecs,
                            icon: Icons.visibility,
                            onChanged: (value) {
                              setState(() => _hasSpecs = value ?? false);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: EnhancedRadioOption<bool>(
                            label: 'No',
                            value: false,
                            groupValue: _hasSpecs,
                            icon: Icons.visibility_off,
                            onChanged: (value) {
                              setState(() => _hasSpecs = value ?? false);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Disability
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8, left: 4),
                      child: Text(
                        'Do you have any disability?',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: EnhancedRadioOption<bool>(
                            label: 'Yes',
                            value: true,
                            groupValue: _hasDisability,
                            icon: Icons.accessible,
                            onChanged: (value) {
                              FocusScope.of(context).unfocus();
                              setState(() => _hasDisability = value ?? false);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: EnhancedRadioOption<bool>(
                            label: 'No',
                            value: false,
                            groupValue: _hasDisability,
                            icon: Icons.accessibility_new,
                            onChanged: (value) {
                              FocusScope.of(context).unfocus();
                              setState(() => _hasDisability = value ?? false);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // Disability description
                if (_hasDisability) ...[
                  const SizedBox(height: 16),
                  EnhancedTextField(
                    label: 'Disability Description',
                    hint: 'Please describe your disability',
                    controller: _disabilityController,
                    prefixIcon: Icons.info_outline,
                    maxLines: 3,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => FocusScope.of(context).unfocus(),
                    onChanged: (value) {},
                  ),
                ],

                const SizedBox(height: 32),

                // Info Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.secondary.withOpacity(0.1),
                        AppColors.secondaryLight.withOpacity(0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.secondary.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.secondary.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.privacy_tip_outlined,
                          color: AppColors.secondary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Your personal information is confidential and only visible to compatible matches.',
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

                const SizedBox(height: 24),
              ],
            ),
          ),
      ),
    );
  }
}
