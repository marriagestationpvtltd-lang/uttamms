// Professional Redesigned Introduce Yourself Page - Step 1
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constant/app_colors.dart';
import '../../constant/app_dimensions.dart';
import '../../constant/app_text_styles.dart';
import '../../ReUsable/registration_progress.dart';
import '../../ReUsable/enhanced_form_fields.dart';
import '../SuignupModel/signup_model.dart';
import 'SignupScreen1.dart';

class IntroduceYourselfPage extends StatefulWidget {
  const IntroduceYourselfPage({Key? key}) : super(key: key);

  @override
  State<IntroduceYourselfPage> createState() => _IntroduceYourselfPageState();
}

class _IntroduceYourselfPageState extends State<IntroduceYourselfPage> {
  // Profile options
  final List<Map<String, dynamic>> _profileForOptions = [
    {'label': 'Myself', 'icon': Icons.person},
    {'label': 'Son', 'icon': Icons.boy},
    {'label': 'Daughter', 'icon': Icons.girl},
    {'label': 'Sister', 'icon': Icons.woman},
    {'label': 'Brother', 'icon': Icons.man},
    {'label': 'Friend', 'icon': Icons.people},
    {'label': 'Relative', 'icon': Icons.family_restroom},
  ];

  String _selectedProfileFor = 'Myself';

  // Gender options
  final List<Map<String, dynamic>> _genderOptions = [
    {'label': 'Male', 'icon': Icons.male, 'value': 'Male'},
    {'label': 'Female', 'icon': Icons.female, 'value': 'Female'},
    {'label': 'Other', 'icon': Icons.transgender, 'value': 'Other'},
  ];

  String _gender = '';

  // Validation
  bool _hasValidationError = false;
  String _errorMessage = '';

  // Mapping to numeric profileForId expected by API
  final Map<String, int> _profileForMap = {
    'Myself': 1,
    'Son': 2,
    'Daughter': 3,
    'Sister': 4,
    'Friend': 5,
    'Relative': 6,
    'Brother': 7,
  };


  @override
  void initState() {
    super.initState();

    // Push initial defaults into provider after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final model = context.read<SignupModel>();
      model.setProfileForId(_profileForMap[_selectedProfileFor] ?? 1);
      _autoSelectGender();
      if (_gender.isNotEmpty) {
        model.setGender(_gender);
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  // Auto-select gender based on profile selection
  void _autoSelectGender() {
    setState(() {
      if (_selectedProfileFor == 'Son' || _selectedProfileFor == 'Brother') {
        _gender = 'Male';
      } else if (_selectedProfileFor == 'Daughter' || _selectedProfileFor == 'Sister') {
        _gender = 'Female';
      }
      // For Myself, Friend, Relative - keep the previously selected gender or empty
    });
  }

  // Validate form
  bool _validateForm() {
    bool isValid = true;
    String errorMessage = '';

    // Check if gender is selected
    if (_gender.isEmpty) {
      isValid = false;
      errorMessage = 'Please select a gender';
    }

    // Additional validation for specific profiles
    if ((_selectedProfileFor == 'Son' || _selectedProfileFor == 'Brother') && _gender != 'Male') {
      isValid = false;
      errorMessage = 'Please select Male gender for $_selectedProfileFor';
    } else if ((_selectedProfileFor == 'Daughter' || _selectedProfileFor == 'Sister') && _gender != 'Female') {
      isValid = false;
      errorMessage = 'Please select Female gender for $_selectedProfileFor';
    }

    setState(() {
      _hasValidationError = !isValid;
      _errorMessage = errorMessage;
    });

    return isValid;
  }

  void _handleContinue() {
    if (_validateForm()) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const YourDetailsPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      // Keyboard should not resize the scaffold — the action buttons stay at
      // the bottom and the scroll area handles the keyboard inset independently.
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: RegistrationStepContainer(
            onContinue: _handleContinue,
            continueText: 'Continue',
            canContinue: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with progress
                RegistrationStepHeader(
                  title: 'Introduce Yourself',
                  subtitle: 'Let\'s start by getting to know who you are creating this profile for.',
                  currentStep: 1,
                  totalSteps: 11,
                  onBack: () => Navigator.pop(context),
                ),

                const SizedBox(height: 24),

                // Attractive step-indicator header (replaces image)
                Center(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary.withOpacity(0.08),
                          AppColors.primaryLight.withOpacity(0.04),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.primary.withOpacity(0.12),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: const [
                        _StepIcon(
                          icon: Icons.person_pin_rounded,
                          label: 'About You',
                          isActive: true,
                        ),
                        _StepDivider(),
                        _StepIcon(
                          icon: Icons.edit_note_rounded,
                          label: 'Your Details',
                          isActive: false,
                        ),
                        _StepDivider(),
                        _StepIcon(
                          icon: Icons.favorite_rounded,
                          label: 'Find Match',
                          isActive: false,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Section: Profile For
                SectionHeader(
                  title: 'This Profile Is For',
                  subtitle: 'Select who you are creating this profile for',
                  icon: Icons.person_pin,
                ),

                const SizedBox(height: 16),

                // Profile selection chips
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: _profileForOptions.map((option) {
                    final bool selected = _selectedProfileFor == option['label'];
                    return EnhancedChipOption(
                      label: option['label'] as String,
                      icon: option['icon'] as IconData,
                      isSelected: selected,
                      onTap: () {
                        setState(() {
                          _selectedProfileFor = option['label'] as String;
                          _autoSelectGender();
                          _hasValidationError = false;
                        });

                        // Update provider
                        final model = context.read<SignupModel>();
                        model.setProfileForId(_profileForMap[option['label']] ?? 1);
                        if (_gender.isNotEmpty) {
                          model.setGender(_gender);
                        }
                      },
                    );
                  }).toList(),
                ),

                const SizedBox(height: 24),

                // Section: Gender
                SectionHeader(
                  title: 'Select Gender',
                  subtitle: 'Choose the appropriate gender',
                  icon: Icons.wc,
                ),

                const SizedBox(height: 16),

                // Gender selection
                ..._genderOptions.map((option) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: EnhancedRadioOption<String>(
                      label: option['label'] as String,
                      icon: option['icon'] as IconData,
                      value: option['value'] as String,
                      groupValue: _gender,
                      onChanged: (value) {
                        setState(() {
                          _gender = value ?? '';
                          _hasValidationError = false;
                        });
                        // Update provider
                        context.read<SignupModel>().setGender(value ?? '');
                      },
                    ),
                  );
                }).toList(),

                // Error message
                if (_hasValidationError && _errorMessage.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.error.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: AppColors.error,
                          size: 22,
                        ),
                        const SizedBox(width: AppDimensions.spacingSM),
                        Expanded(
                          child: Text(
                            _errorMessage,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.error,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Info card
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
                          Icons.info_outline,
                          color: AppColors.secondary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: AppDimensions.spacingSM),
                      Expanded(
                        child: Text(
                          'Your information is secure and will only be visible to verified users.',
                          style: AppTextStyles.bodySmall.copyWith(height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppDimensions.spacingLG),
              ],
            ),
          ),
      ),
    );
  }
}

/// A small icon + label widget used in the registration step indicator
class _StepIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;

  const _StepIcon({
    required this.icon,
    required this.label,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: isActive ? AppColors.primary : AppColors.primary.withOpacity(0.08),
            shape: BoxShape.circle,
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.30),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [],
          ),
          child: Icon(
            icon,
            color: isActive ? AppColors.white : AppColors.primary.withOpacity(0.45),
            size: 24,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            color: isActive ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// Dashed divider line between step icons
class _StepDivider extends StatelessWidget {
  const _StepDivider();

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.15),
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }
}
