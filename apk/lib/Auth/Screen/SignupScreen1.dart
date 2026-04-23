// Professional Redesigned Your Details Page - Step 2
import 'package:country_code_picker/country_code_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ms2026/Auth/Screen/signupscreen2.dart';

import '../../constant/app_colors.dart';
import '../../constant/app_dimensions.dart';
import '../../constant/app_text_styles.dart';
import '../../ReUsable/registration_progress.dart';
import '../../ReUsable/enhanced_form_fields.dart';
import '../../ReUsable/dropdownwidget.dart';
import '../../ReUsable/dateconverter.dart';
import '../../ReUsable/smart_scroll_behavior.dart';
import '../SuignupModel/signup_model.dart';

class YourDetailsPage extends StatefulWidget {
  const YourDetailsPage({super.key});

  @override
  State<YourDetailsPage> createState() => _YourDetailsPageState();
}

class _YourDetailsPageState extends State<YourDetailsPage>
    with SmartScrollBehavior {
  // Form controllers
  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _emailController;
  late TextEditingController _passwordController;
  late TextEditingController _confirmPasswordController;
  late TextEditingController _phoneController;

  // Focus nodes for smart scrolling
  late FocusNode _firstNameFocus;
  late FocusNode _lastNameFocus;
  late FocusNode _emailFocus;
  late FocusNode _passwordFocus;
  late FocusNode _confirmPasswordFocus;
  late FocusNode _phoneFocus;

  // Global keys for smart scrolling
  final GlobalKey _firstNameKey = GlobalKey();
  final GlobalKey _lastNameKey = GlobalKey();
  final GlobalKey _emailKey = GlobalKey();
  final GlobalKey _passwordKey = GlobalKey();
  final GlobalKey _confirmPasswordKey = GlobalKey();
  final GlobalKey _phoneKey = GlobalKey();

  // Form state
  String selectedNationality = "";
  String _confirmPassword = '';
  String completeNumberr = '';
  String? countryCode = '+977';

  // Date selection state
  String selectedADMonth = "";
  String selectedADDay = "";
  String selectedADYear = "";
  String selectedBSMonth = "";
  String selectedBSDay = "";
  String selectedBSYear = "";
  bool isAD = true;

  // Languages
  List<String> selectedLanguages = ["Nepali"];

  // Password visibility
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  // Validation state
  bool _hasValidationErrors = false;
  Map<String, String?> _fieldErrors = {};

  // Animation
// Date options
  final List<String> adMonths = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  final List<String> bsMonths = NepaliDateConverter.nepaliMonthsEnglish;

  final languagesList = [
    "Nepali", "English", "Hindi", "Chinese", "Spanish", "French",
    "German", "Japanese", "Korean", "Arabic", "Russian", "Portuguese",
    "Italian", "Turkish"
  ];

  final List<String> nationalityList = [
    "Nepali", "Indian", "American", "Chinese", "British", "Canadian",
    "Australian", "Japanese", "Korean", "French", "German", "Spanish",
    "Italian", "Brazilian", "Mexican", "Russian"
  ];

  List<String> get adYears {
    final now = DateTime.now();
    final maxYear = now.year - 21; // Minimum age: 21 years
    final minYear = now.year - 80; // Maximum age: 80 years
    final years = <String>[];
    for (int year = minYear; year <= maxYear; year++) {
      years.add(year.toString());
    }
    return years.reversed.toList();
  }

  List<String> get bsYears => NepaliDateConverter.getBsYearsList();

  List<String> get currentAdDays {
    try {
      if (selectedADYear.isEmpty || selectedADMonth.isEmpty) {
        return List.generate(31, (index) => (index + 1).toString().padLeft(2, '0'));
      }
      final year = int.tryParse(selectedADYear);
      final month = adMonths.indexOf(selectedADMonth) + 1;
      if (year != null && month > 0) {
        final daysInMonth = DateTime(year, month + 1, 0).day;
        return List.generate(daysInMonth, (index) => (index + 1).toString().padLeft(2, '0'));
      }
    } catch (e) {
      print('Error getting AD days: $e');
    }
    return List.generate(31, (index) => (index + 1).toString().padLeft(2, '0'));
  }

  List<String> get currentBsDays {
    try {
      if (selectedBSYear.isEmpty || selectedBSMonth.isEmpty) {
        return List.generate(32, (index) => (index + 1).toString().padLeft(2, '0'));
      }
      final year = int.tryParse(selectedBSYear);
      final month = bsMonths.indexOf(selectedBSMonth) + 1;
      if (year != null && month > 0) {
        return NepaliDateConverter.getBsDaysList(year, month);
      }
    } catch (e) {
      print('Error getting BS days: $e');
    }
    return List.generate(32, (index) => (index + 1).toString().padLeft(2, '0'));
  }

  @override
  void initState() {
    super.initState();

    _firstNameController = TextEditingController();
    _lastNameController = TextEditingController();
    _emailController = TextEditingController();
    _passwordController = TextEditingController();
    _confirmPasswordController = TextEditingController();
    _phoneController = TextEditingController();

    // Initialize focus nodes
    _firstNameFocus = FocusNode();
    _lastNameFocus = FocusNode();
    _emailFocus = FocusNode();
    _passwordFocus = FocusNode();
    _confirmPasswordFocus = FocusNode();
    _phoneFocus = FocusNode();

    // Register fields for smart scrolling
    registerField(_firstNameFocus, _firstNameKey);
    registerField(_lastNameFocus, _lastNameKey);
    registerField(_emailFocus, _emailKey);
    registerField(_passwordFocus, _passwordKey);
    registerField(_confirmPasswordFocus, _confirmPasswordKey);
    registerField(_phoneFocus, _phoneKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final model = context.read<SignupModel>();
      if (model.languages.isEmpty) {
        model.setLanguages(selectedLanguages.join(', '));
      }
      // Removed auto-focus to prevent keyboard from opening automatically
      // User can tap on field to open keyboard when ready
    });
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _phoneController.dispose();

    // Dispose focus nodes
    _firstNameFocus.dispose();
    _lastNameFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmPasswordFocus.dispose();
    _phoneFocus.dispose();
super.dispose();
  }

  // Validation methods
  String? _validateFirstName(String? value) {
    if (value == null || value.isEmpty) return 'First name is required';
    if (value.length < 2) return 'Name must be at least 2 characters';
    return null;
  }

  String? _validateLastName(String? value) {
    if (value == null || value.isEmpty) return 'Last name is required';
    if (value.length < 2) return 'Name must be at least 2 characters';
    return null;
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) return 'Email is required';
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value)) return 'Enter a valid email';
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (value.length < 6) return 'Password must be at least 6 characters';
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) return 'Please confirm password';
    if (value != _passwordController.text) return 'Passwords do not match';
    return null;
  }

  String? _validateDateOfBirth() {
    // Check if all date fields are filled
    if (selectedADYear.isEmpty || selectedADMonth.isEmpty || selectedADDay.isEmpty) {
      return 'Date of birth is required';
    }

    // Parse the selected date
    final year = int.tryParse(selectedADYear);
    final monthIndex = adMonths.indexOf(selectedADMonth) + 1;
    final day = int.tryParse(selectedADDay);

    if (year == null || monthIndex <= 0 || day == null) {
      return 'Invalid date selected';
    }

    try {
      final selectedDate = DateTime(year, monthIndex, day);
      final now = DateTime.now();
      final age = now.year - selectedDate.year;
      final hasHadBirthdayThisYear = now.month > selectedDate.month ||
          (now.month == selectedDate.month && now.day >= selectedDate.day);

      final actualAge = hasHadBirthdayThisYear ? age : age - 1;

      // Minimum age validation (21 years)
      if (actualAge < 21) {
        return 'You are not of eligible age for marriage';
      }

      // Maximum age validation (80 years)
      if (actualAge > 80) {
        return 'Your age is over 80 years';
      }
    } catch (e) {
      return 'Invalid date';
    }

    return null;
  }

  bool _validateForm() {
    setState(() {
      _fieldErrors = {
        'firstName': _validateFirstName(_firstNameController.text),
        'lastName': _validateLastName(_lastNameController.text),
        'email': _validateEmail(_emailController.text),
        'password': _validatePassword(_passwordController.text),
        'confirmPassword': _validateConfirmPassword(_confirmPasswordController.text),
        'phone': completeNumberr.isEmpty ? 'Phone number is required' : null,
        'dob': _validateDateOfBirth(),
        'languages': selectedLanguages.isEmpty ? 'Select at least one language' : null,
        'nationality': selectedNationality.isEmpty ? 'Nationality is required' : null,
      };
      _hasValidationErrors = _fieldErrors.values.any((error) => error != null);
    });

    return !_hasValidationErrors;
  }

  // Date conversion methods
  void _convertBsToAdAndUpdate() {
    try {
      final year = int.tryParse(selectedBSYear);
      final month = bsMonths.indexOf(selectedBSMonth) + 1;
      final day = int.tryParse(selectedBSDay);

      if (year != null && month > 0 && day != null) {
        final adDate = NepaliDateConverter.bsToAd(year, month, day);
        if (adDate != null) {
          setState(() {
            selectedADYear = adDate.year.toString();
            selectedADMonth = adMonths[adDate.month - 1];
            selectedADDay = adDate.day.toString().padLeft(2, '0');
          });
          _updateDobToProvider();
        }
      }
    } catch (e) {
      print('Error converting BS to AD: $e');
    }
  }

  void _updateDobToProvider() {
    final model = context.read<SignupModel>();
    if (selectedADYear.isNotEmpty && selectedADMonth.isNotEmpty && selectedADDay.isNotEmpty) {
      final monthIndex = adMonths.indexOf(selectedADMonth) + 1;
      final monthS = monthIndex.toString().padLeft(2, '0');
      final dayS = selectedADDay.padLeft(2, '0');
      final dob = '$selectedADYear-$monthS-$dayS';
      model.setDateOfBirth(dob);

      setState(() {
        _fieldErrors['dob'] = _validateDateOfBirth();
      });
    }
  }

  // Image picker methods
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

  void _showLanguagePicker() {
    FocusScope.of(context).unfocus();
    List<String> available = languagesList
        .where((lang) => !selectedLanguages.contains(lang))
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              decoration: const BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: const EdgeInsets.all(20),
              height: MediaQuery.of(context).size.height * 0.70,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.language, color: AppColors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        "Select Languages",
                        style: AppTextStyles.heading3,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Selected languages chips
                  if (selectedLanguages.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: selectedLanguages.map((lang) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                lang,
                                style: AppTextStyles.whiteBody.copyWith(fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    selectedLanguages.remove(lang);
                                    context.read<SignupModel>().setLanguages(
                                      selectedLanguages.join(', '),
                                    );
                                    _fieldErrors['languages'] = selectedLanguages.isEmpty
                                        ? 'Select at least one language' : null;
                                  });
                                  setSheetState(() {
                                    available = languagesList
                                        .where((l) => !selectedLanguages.contains(l))
                                        .toList();
                                  });
                                },
                                child: const Icon(Icons.close, size: 16, color: AppColors.white),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),

                  const SizedBox(height: 16),

                  // Search field
                  TextField(
                    autofocus: false,
                    decoration: InputDecoration(
                      hintText: "Search languages...",
                      prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onChanged: (value) {
                      setSheetState(() {
                        available = languagesList
                            .where((lang) =>
                                !selectedLanguages.contains(lang) &&
                                lang.toLowerCase().contains(value.toLowerCase()))
                            .toList();
                      });
                    },
                  ),

                  const SizedBox(height: 16),

                  // Available languages list
                  Expanded(
                    child: available.isEmpty
                        ? Center(
                            child: Text(
                              "No languages available",
                              style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textSecondary),
                            ),
                          )
                        : ListView.builder(
                            itemCount: available.length,
                            itemBuilder: (_, index) {
                              String item = available[index];
                              return ListTile(
                                title: Text(
                                  item,
                                  style: AppTextStyles.bodyLarge,
                                ),
                                trailing: const Icon(Icons.add, color: AppColors.primary),
                                onTap: () {
                                  setState(() {
                                    selectedLanguages.add(item);
                                    context.read<SignupModel>().setLanguages(
                                      selectedLanguages.join(', '),
                                    );
                                    _fieldErrors['languages'] = null;
                                  });
                                  Navigator.pop(context);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    ).then((_) {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) FocusManager.instance.primaryFocus?.unfocus();
        });
      }
    });
  }

  Future<void> _submitSignup() async {
    if (!_validateForm()) {
      _showSnackBar('Please fill all required fields correctly', isError: true);
      return;
    }

    final model = context.read<SignupModel>();
    final success = await model.submitSignup();

    if (success) {
      _showSnackBar('Profile created successfully!');
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const PersonalDetailsPage()),
      );
    } else {
      _showSnackBar(model.error ?? 'Signup failed', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SignupModel>(
      builder: (context, model, child) {
        return Scaffold(
          backgroundColor: AppColors.background,
          resizeToAvoidBottomInset: true,
          body: SafeArea(
            child: RegistrationStepContainer(
                scrollController: scrollController,
                onContinue: model.isSubmitting ? null : _submitSignup,
                onBack: () => Navigator.pop(context),
                onStepBack: () => Navigator.pop(context), // Allow step-by-step back navigation
                continueText: 'Continue',
                canContinue: !model.isSubmitting,
                isLoading: model.isSubmitting,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    RegistrationStepHeader(
                      title: 'Your Details',
                      subtitle: 'Tell us about yourself. This information helps us find your perfect match.',
                      currentStep: 2,
                      totalSteps: 11,
                      onBack: () => Navigator.pop(context),
                      onStepBack: () => Navigator.pop(context), // Allow step-by-step back navigation
                    ),

                    const SizedBox(height: 32),

                    // Basic Information Section
                    SectionHeader(
                      title: 'Basic Information',
                      subtitle: 'Your name and contact details',
                      icon: Icons.person_outline,
                    ),

                    const SizedBox(height: 16),

                    // First Name and Last Name
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            key: _firstNameKey,
                            child: EnhancedTextField(
                              label: 'First Name',
                              hint: 'Enter first name',
                              controller: _firstNameController,
                              focusNode: _firstNameFocus,
                              prefixIcon: Icons.person_outline,
                              hasError: _fieldErrors['firstName'] != null,
                              errorText: _fieldErrors['firstName'],
                              textInputAction: TextInputAction.next,
                              onSubmitted: (_) => FocusScope.of(context).requestFocus(_lastNameFocus),
                              onChanged: (value) {
                                model.setFirstName(value);
                                if (_hasValidationErrors) {
                                  setState(() {
                                    _fieldErrors['firstName'] = _validateFirstName(value);
                                  });
                                }
                              },
                              validator: _validateFirstName,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            key: _lastNameKey,
                            child: EnhancedTextField(
                              label: 'Last Name',
                              hint: 'Enter last name',
                              controller: _lastNameController,
                              focusNode: _lastNameFocus,
                              prefixIcon: Icons.person_outline,
                              hasError: _fieldErrors['lastName'] != null,
                              errorText: _fieldErrors['lastName'],
                              textInputAction: TextInputAction.next,
                              onSubmitted: (_) => FocusScope.of(context).requestFocus(_emailFocus),
                              onChanged: (value) {
                                model.setLastName(value);
                                if (_hasValidationErrors) {
                                  setState(() {
                                    _fieldErrors['lastName'] = _validateLastName(value);
                                  });
                                }
                              },
                              validator: _validateLastName,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Email
                    Container(
                      key: _emailKey,
                      child: EnhancedTextField(
                        label: 'Email Address',
                        hint: 'your.email@example.com',
                        controller: _emailController,
                        focusNode: _emailFocus,
                        prefixIcon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => FocusScope.of(context).requestFocus(_passwordFocus),
                        hasError: _fieldErrors['email'] != null,
                        errorText: _fieldErrors['email'],
                        onChanged: (value) {
                          model.setEmail(value);
                          if (_hasValidationErrors) {
                            setState(() {
                              _fieldErrors['email'] = _validateEmail(value);
                            });
                          }
                        },
                        validator: _validateEmail,
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Password
                    Container(
                      key: _passwordKey,
                      child: EnhancedTextField(
                        label: 'Password',
                        hint: 'Create a strong password',
                        controller: _passwordController,
                        focusNode: _passwordFocus,
                        prefixIcon: Icons.lock_outline,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => FocusScope.of(context).requestFocus(_confirmPasswordFocus),
                        hasError: _fieldErrors['password'] != null,
                        errorText: _fieldErrors['password'],
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off : Icons.visibility,
                            color: AppColors.textSecondary,
                          ),
                          onPressed: () {
                            setState(() => _obscurePassword = !_obscurePassword);
                          },
                        ),
                        onChanged: (value) {
                          model.setPassword(value);
                          if (_hasValidationErrors) {
                            setState(() {
                              _fieldErrors['password'] = _validatePassword(value);
                              if (_confirmPasswordController.text.isNotEmpty) {
                                _fieldErrors['confirmPassword'] =
                                    _validateConfirmPassword(_confirmPasswordController.text);
                              }
                            });
                          }
                        },
                        validator: _validatePassword,
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Confirm Password
                    Container(
                      key: _confirmPasswordKey,
                      child: EnhancedTextField(
                        label: 'Confirm Password',
                        hint: 'Re-enter your password',
                        controller: _confirmPasswordController,
                        focusNode: _confirmPasswordFocus,
                        prefixIcon: Icons.lock_outline,
                        obscureText: _obscureConfirm,
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => FocusScope.of(context).requestFocus(_phoneFocus),
                        hasError: _fieldErrors['confirmPassword'] != null,
                        errorText: _fieldErrors['confirmPassword'],
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirm ? Icons.visibility_off : Icons.visibility,
                            color: AppColors.textSecondary,
                          ),
                          onPressed: () {
                            setState(() => _obscureConfirm = !_obscureConfirm);
                          },
                        ),
                        onChanged: (value) {
                          _confirmPassword = value;
                          if (_hasValidationErrors) {
                            setState(() {
                              _fieldErrors['confirmPassword'] = _validateConfirmPassword(value);
                            });
                          }
                        },
                        validator: _validateConfirmPassword,
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Phone Number
                    Container(
                      key: _phoneKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8, left: 4),
                            child: Row(
                              children: [
                                Text(
                                  'Phone Number',
                                  style: AppTextStyles.labelMedium,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '*',
                                  style: AppTextStyles.labelMedium.copyWith(color: AppColors.error),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            children: [
                              Container(
                                height: 56,
                                decoration: BoxDecoration(
                                  color: AppColors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: _fieldErrors['phone'] != null
                                        ? AppColors.error
                                        : AppColors.border,
                                    width: 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _fieldErrors['phone'] != null
                                          ? AppColors.error.withOpacity(0.1)
                                          : AppColors.shadowLight,
                                      blurRadius: 10,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: CountryCodePicker(
                                  onChanged: (country) {
                                    setState(() {
                                      countryCode = country.dialCode ?? '+977';
                                    });
                                  },
                                  initialSelection: 'NP',
                                  favorite: const ['+977', 'IN', 'US'],
                                  showCountryOnly: false,
                                  showOnlyCountryWhenClosed: false,
                                  alignLeft: false,
                                  padding: EdgeInsets.zero,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Container(
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: AppColors.white,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: _fieldErrors['phone'] != null
                                          ? AppColors.error
                                          : AppColors.border,
                                      width: 1.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: _fieldErrors['phone'] != null
                                            ? AppColors.error.withOpacity(0.1)
                                            : AppColors.shadowLight,
                                        blurRadius: 10,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: TextField(
                                    controller: _phoneController,
                                    focusNode: _phoneFocus,
                                    autofocus: false,
                                    keyboardType: TextInputType.phone,
                                    textInputAction: TextInputAction.done,
                                    onSubmitted: (_) => FocusScope.of(context).unfocus(),
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(15),
                                    ],
                                    style: AppTextStyles.labelMedium.copyWith(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  decoration: InputDecoration(
                                    hintText: 'Phone number',
                                    hintStyle: AppTextStyles.bodyMedium.copyWith(
                                      color: AppColors.textHint,
                                    ),
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 16,
                                    ),
                                  ),
                                  onChanged: (value) {
                                    String completeNumber = '$countryCode$value';
                                    setState(() {
                                      completeNumberr = completeNumber;
                                      if (_hasValidationErrors) {
                                        _fieldErrors['phone'] = value.isEmpty
                                            ? 'Phone number is required' : null;
                                      }
                                    });
                                    model.setContactNo(completeNumber);
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_fieldErrors['phone'] != null) ...[
                          const SizedBox(height: 6),
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
                                  _fieldErrors['phone']!,
                                  style: AppTextStyles.caption.copyWith(
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
                    ),

                    const SizedBox(height: 32),

                    // Date of Birth Section
                    SectionHeader(
                      title: 'Date of Birth',
                      subtitle: 'Select your date of birth',
                      icon: Icons.cake_outlined,
                    ),

                    const SizedBox(height: 16),

                    // AD / BS Toggle
                    Row(
                      children: [
                        Expanded(
                          child: EnhancedRadioOption<bool>(
                            label: 'AD (English)',
                            value: true,
                            groupValue: isAD,
                            icon: Icons.calendar_today,
                            onChanged: (value) {
                              setState(() {
                                isAD = true;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: EnhancedRadioOption<bool>(
                            label: 'BS (Nepali)',
                            value: false,
                            groupValue: isAD,
                            icon: Icons.calendar_month,
                            onChanged: (value) {
                              setState(() {
                                isAD = false;
                              });
                            },
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    if (isAD)
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TypingDropdown<String>(
                              title: 'Year',
                              items: adYears,
                              itemLabel: (year) => year,
                              hint: 'Year',
                              selectedItem: selectedADYear.isNotEmpty ? selectedADYear : null,
                              showError: _fieldErrors['dob'] != null && selectedADYear.isEmpty,
                              onChanged: (value) {
                                setState(() {
                                  selectedADYear = value ?? '';
                                  final days = currentAdDays;
                                  if (!days.contains(selectedADDay)) {
                                    selectedADDay = days.isNotEmpty ? days.first : '01';
                                  }
                                });
                                _updateDobToProvider();
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: EnhancedDropdown<String>(
                              label: 'Month',
                              value: selectedADMonth.isNotEmpty ? selectedADMonth : null,
                              items: adMonths,
                              itemLabel: (month) => month,
                              hint: 'Month',
                              hasError: _fieldErrors['dob'] != null && selectedADMonth.isEmpty,
                              onChanged: (value) {
                                setState(() {
                                  selectedADMonth = value ?? '';
                                  final days = currentAdDays;
                                  if (!days.contains(selectedADDay)) {
                                    selectedADDay = days.isNotEmpty ? days.first : '01';
                                  }
                                });
                                _updateDobToProvider();
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 1,
                            child: EnhancedDropdown<String>(
                              label: 'Day',
                              value: selectedADDay.isNotEmpty ? selectedADDay : null,
                              items: currentAdDays,
                              itemLabel: (day) => day,
                              hint: 'Day',
                              hasError: _fieldErrors['dob'] != null && selectedADDay.isEmpty,
                              onChanged: (value) {
                                setState(() => selectedADDay = value ?? '');
                                _updateDobToProvider();
                              },
                            ),
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TypingDropdown<String>(
                              title: 'Year',
                              items: bsYears,
                              itemLabel: (year) => year,
                              hint: 'Year',
                              selectedItem: selectedBSYear.isNotEmpty ? selectedBSYear : null,
                              showError: _fieldErrors['dob'] != null && selectedBSYear.isEmpty,
                              onChanged: (value) {
                                setState(() {
                                  selectedBSYear = value ?? '';
                                  final days = currentBsDays;
                                  if (!days.contains(selectedBSDay)) {
                                    selectedBSDay = days.isNotEmpty ? days.first : '01';
                                  }
                                });
                                _convertBsToAdAndUpdate();
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: EnhancedDropdown<String>(
                              label: 'Month',
                              value: selectedBSMonth.isNotEmpty ? selectedBSMonth : null,
                              items: bsMonths,
                              itemLabel: (month) => month,
                              hint: 'Month',
                              hasError: _fieldErrors['dob'] != null && selectedBSMonth.isEmpty,
                              onChanged: (value) {
                                setState(() {
                                  selectedBSMonth = value ?? '';
                                  final days = currentBsDays;
                                  if (!days.contains(selectedBSDay)) {
                                    selectedBSDay = days.isNotEmpty ? days.first : '01';
                                  }
                                });
                                _convertBsToAdAndUpdate();
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 1,
                            child: EnhancedDropdown<String>(
                              label: 'Day',
                              value: selectedBSDay.isNotEmpty ? selectedBSDay : null,
                              items: currentBsDays,
                              itemLabel: (day) => day,
                              hint: 'Day',
                              hasError: _fieldErrors['dob'] != null && selectedBSDay.isEmpty,
                              onChanged: (value) {
                                setState(() => selectedBSDay = value ?? '');
                                _convertBsToAdAndUpdate();
                              },
                            ),
                          ),
                        ],
                      ),

                    if (_fieldErrors['dob'] != null) ...[
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
                              _fieldErrors['dob']!,
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.error,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Show converted date
                    if (!isAD && selectedADYear.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.success.withOpacity(0.1),
                              AppColors.success.withOpacity(0.05),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.success.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppColors.success.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(
                                Icons.check_circle_outline,
                                color: AppColors.success,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Converted: $selectedADYear-${(adMonths.indexOf(selectedADMonth) + 1).toString().padLeft(2, '0')}-$selectedADDay (AD)',
                                style: AppTextStyles.caption.copyWith(
                                  color: AppColors.success,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 32),

                    // Additional Information Section
                    SectionHeader(
                      title: 'Additional Information',
                      subtitle: 'Languages and nationality',
                      icon: Icons.language,
                    ),

                    const SizedBox(height: 16),

                    // Languages
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8, left: 4),
                          child: Row(
                            children: [
                              Text(
                                'Languages',
                                style: AppTextStyles.labelMedium,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '*',
                                style: AppTextStyles.labelMedium.copyWith(color: AppColors.error),
                              ),
                            ],
                          ),
                        ),
                        InkWell(
                          onTap: _showLanguagePicker,
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: AppColors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: _fieldErrors['languages'] != null
                                    ? AppColors.error
                                    : AppColors.border,
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: _fieldErrors['languages'] != null
                                      ? AppColors.error.withOpacity(0.1)
                                      : AppColors.shadowLight,
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.language,
                                      color: AppColors.textSecondary,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        selectedLanguages.isEmpty
                                            ? 'Select languages you speak'
                                            : '${selectedLanguages.length} language${selectedLanguages.length > 1 ? 's' : ''} selected',
                                        style: AppTextStyles.bodyLarge.copyWith(
                                          color: selectedLanguages.isEmpty
                                              ? AppColors.textHint
                                              : AppColors.textPrimary,
                                          fontWeight: selectedLanguages.isEmpty
                                              ? FontWeight.w400
                                              : FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    const Icon(
                                      Icons.keyboard_arrow_down,
                                      color: AppColors.textSecondary,
                                    ),
                                  ],
                                ),
                                if (selectedLanguages.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: selectedLanguages.map((lang) {
                                      return Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          gradient: AppColors.primaryGradient,
                                          borderRadius: BorderRadius.circular(20),
                                          boxShadow: [
                                            BoxShadow(
                                              color: AppColors.primary.withOpacity(0.3),
                                              blurRadius: 4,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Text(
                                          lang,
                                          style: AppTextStyles.bodySmall.copyWith(
                                            fontWeight: FontWeight.w500,
                                            color: AppColors.white,
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        if (_fieldErrors['languages'] != null) ...[
                          const SizedBox(height: 6),
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
                                  _fieldErrors['languages']!,
                                  style: AppTextStyles.caption.copyWith(
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

                    const SizedBox(height: 16),

                    // Nationality
                    EnhancedDropdown<String>(
                      label: 'Nationality',
                      value: selectedNationality.isNotEmpty ? selectedNationality : null,
                      items: nationalityList,
                      itemLabel: (nationality) => nationality,
                      hint: 'Select your nationality',
                      prefixIcon: Icons.flag_outlined,
                      hasError: _fieldErrors['nationality'] != null,
                      errorText: _fieldErrors['nationality'],
                      isRequired: true,
                      onChanged: (value) {
                        setState(() {
                          selectedNationality = value ?? '';
                          if (_hasValidationErrors) {
                            _fieldErrors['nationality'] = selectedNationality.isEmpty
                                ? 'Nationality is required' : null;
                          }
                        });
                        model.setNationality(value ?? '');
                      },
                    ),

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
                              Icons.security,
                              color: AppColors.secondary,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Your information is secure and encrypted. We never share your data with third parties.',
                              style: AppTextStyles.bodySmall.copyWith(height: 1.4),
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
      },
    );
  }
}
