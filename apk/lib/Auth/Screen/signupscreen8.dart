import 'package:flutter/material.dart';
import 'package:ms2026/Auth/Screen/signupscreen9.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../../ReUsable/dropdownwidget.dart';
import '../../ReUsable/registration_progress.dart';
import '../../ReUsable/enhanced_form_fields.dart';
import '../../constant/app_colors.dart';
import '../../service/updatepage.dart';
import 'package:ms2026/config/app_endpoints.dart';

class LifestylePage extends StatefulWidget {
  const LifestylePage({
    super.key,
    this.isEditMode = false,
    this.initialData,
  });

  final bool isEditMode;
  final Map<String, dynamic>? initialData;

  @override
  State<LifestylePage> createState() => _LifestylePageState();
}

class _LifestylePageState extends State<LifestylePage> {
  bool submitted = false;
  bool _isLoading = false;

  // Form variables
  String? _selectedDiet;
  String? _selectedDrink;
  String? _selectedDrinkType;
  String? _selectedSmoke;
  String? _selectedSmokeType;

  // Error messages
  final Map<String, String> _errors = {
    'diet': '',
    'drink': '',
    'drinkType': '',
    'smoke': '',
    'smokeType': '',
  };

  // Dropdown options
  final List<String> _dietOptions = [
    'Vegetarian',
    'Non-Vegetarian',
    'Eggetarian',
    'Vegan',
    'Jain',
    'Other'
  ];

  final List<String> _drinkOptions = [
    'Yes',
    'No',
    'SomeTime',
  ];

  final List<String> _drinkTypeOptions = [
    'Beer',
    'Wine',
    'Whiskey',
    'Vodka',
    'Rum',
    'Other',
    'Non-Alcoholic'
  ];

  final List<String> _smokeOptions = [
    'Yes',
    'No',
    'Occasionally',
    'Socially'
  ];

  final List<String> _smokeTypeOptions = [
    'Cigarettes',
    'Cigars',
    'Vape',
    'Hookah',
    'Other'
  ];

  @override
  void initState() {
    super.initState();
    if (widget.isEditMode && widget.initialData != null) {
      _populateFromInitialData(widget.initialData!);
    }
  }

  String? _getValidValue(dynamic value, List<String> options) {
    if (value == null) return null;
    final str = value.toString();
    if (str.isEmpty) return null;
    try {
      return options.firstWhere(
        (o) => o.toLowerCase() == str.toLowerCase(),
      );
    } catch (_) {
      return str;
    }
  }

  void _populateFromInitialData(Map<String, dynamic> data) {
    _selectedDiet = _getValidValue(data['diet'], _dietOptions);
    _selectedDrink = _getValidValue(data['drinks'], _drinkOptions);
    _selectedDrinkType = _getValidValue(data['drinktype'], _drinkTypeOptions);
    _selectedSmoke = _getValidValue(data['smoke'], _smokeOptions);
    _selectedSmokeType = _getValidValue(data['smoketype'], _smokeTypeOptions);
  }

  @override
  void dispose() {
    super.dispose();
  }

  // Validation methods
  bool _validateRequired(String? value, String fieldName) {
    if (value == null || value.isEmpty) {
      _errors[fieldName] = 'This field is required';
      return false;
    }
    _errors[fieldName] = '';
    return true;
  }

  bool _validateForm() {
    bool isValid = true;

    // Clear all errors
    _errors.forEach((key, value) {
      _errors[key] = '';
    });

    if (!_validateRequired(_selectedDiet, 'diet')) {
      isValid = false;
    }

    if (!_validateRequired(_selectedDrink, 'drink')) {
      isValid = false;
    }

    // Drink type validation (only if not "No")
    if (_selectedDrink != "No" && !_validateRequired(_selectedDrinkType, 'drinkType')) {
      isValid = false;
    }

    if (!_validateRequired(_selectedSmoke, 'smoke')) {
      isValid = false;
    }

    // Smoke type validation (only if not "No")
    if (_selectedSmoke != "No" && !_validateRequired(_selectedSmokeType, 'smokeType')) {
      isValid = false;
    }

    setState(() {});
    return isValid;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: RegistrationStepContainer(
          onBack: () => Navigator.pop(context),
          onStepBack: () => Navigator.pop(context), // Allow step-by-step back navigation
          onContinue: _validateAndSubmit,
          isLoading: _isLoading,
          canContinue: !_isLoading,
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                RegistrationStepHeader(
                  title: 'Lifestyle Preferences',
                  subtitle: 'Share your lifestyle choices and daily habits',
                  currentStep: 9,
                  totalSteps: 11,
                  onBack: () => Navigator.pop(context),
                  onStepBack: () => Navigator.pop(context), // Allow step-by-step back navigation
                ),
                const SizedBox(height: 32),

                // Skip Button
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _isLoading ? null : _skipPage,
                    icon: const Icon(Icons.skip_next, size: 18),
                    label: const Text('Skip this step'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Diet Section
                const SectionHeader(
                  title: 'Diet Preference',
                  subtitle: 'What type of diet do you follow?',
                  icon: Icons.restaurant_rounded,
                ),
                const SizedBox(height: 20),

                EnhancedDropdown<String>(
                  label: 'Your Diet',
                  value: _selectedDiet,
                  items: _dietOptions,
                  itemLabel: (item) => item,
                  hint: 'Select your diet preference',
                  onChanged: (value) {
                    setState(() {
                      _selectedDiet = value;
                      _errors['diet'] = '';
                    });
                  },
                  hasError: submitted && _errors['diet']!.isNotEmpty,
                  errorText: _errors['diet'],
                  isRequired: true,
                  prefixIcon: Icons.food_bank_outlined,
                ),
                const SizedBox(height: 32),

                // Drink Section
                const SectionHeader(
                  title: 'Drinking Habits',
                  subtitle: 'Do you consume alcohol?',
                  icon: Icons.local_bar_outlined,
                ),
                const SizedBox(height: 20),

                EnhancedDropdown<String>(
                  label: 'Drink Alcohol',
                  value: _selectedDrink,
                  items: _drinkOptions,
                  itemLabel: (item) => item,
                  hint: 'Select drink habit',
                  onChanged: (value) {
                    setState(() {
                      _selectedDrink = value;
                      _errors['drink'] = '';
                      // Reset drink type if "No" is selected
                      if (value == "No") {
                        _selectedDrinkType = null;
                        _errors['drinkType'] = '';
                      }
                    });
                  },
                  hasError: submitted && _errors['drink']!.isNotEmpty,
                  errorText: _errors['drink'],
                  isRequired: true,
                ),

                // Drink Type (only show if not "No")
                if (_selectedDrink != null && _selectedDrink != "No") ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.shadowLight,
                          blurRadius: 12,
                          offset: const Offset(0, 4),
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
                                gradient: AppColors.primaryGradient,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.liquor_outlined,
                                size: 20,
                                color: AppColors.white,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Drink Preference',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        EnhancedDropdown<String>(
                          label: 'Type of Drink',
                          value: _selectedDrinkType,
                          items: _drinkTypeOptions,
                          itemLabel: (item) => item,
                          hint: 'Select drink type',
                          onChanged: (value) {
                            setState(() {
                              _selectedDrinkType = value;
                              _errors['drinkType'] = '';
                            });
                          },
                          hasError: submitted && _errors['drinkType']!.isNotEmpty,
                          errorText: _errors['drinkType'],
                          isRequired: true,
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 32),

                // Smoke Section
                const SectionHeader(
                  title: 'Smoking Habits',
                  subtitle: 'Do you smoke?',
                  icon: Icons.smoke_free_outlined,
                ),
                const SizedBox(height: 20),

                EnhancedDropdown<String>(
                  label: 'Smoke',
                  value: _selectedSmoke,
                  items: _smokeOptions,
                  itemLabel: (item) => item,
                  hint: 'Select smoke habit',
                  onChanged: (value) {
                    setState(() {
                      _selectedSmoke = value;
                      _errors['smoke'] = '';
                      // Reset smoke type if "No" is selected
                      if (value == "No") {
                        _selectedSmokeType = null;
                        _errors['smokeType'] = '';
                      }
                    });
                  },
                  hasError: submitted && _errors['smoke']!.isNotEmpty,
                  errorText: _errors['smoke'],
                  isRequired: true,
                ),

                // Smoke Type (only show if not "No")
                if (_selectedSmoke != null && _selectedSmoke != "No") ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.shadowLight,
                          blurRadius: 12,
                          offset: const Offset(0, 4),
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
                                gradient: AppColors.primaryGradient,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.smoking_rooms_outlined,
                                size: 20,
                                color: AppColors.white,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Smoke Preference',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        EnhancedDropdown<String>(
                          label: 'Type of Smoke',
                          value: _selectedSmokeType,
                          items: _smokeTypeOptions,
                          itemLabel: (item) => item,
                          hint: 'Select smoke type',
                          onChanged: (value) {
                            setState(() {
                              _selectedSmokeType = value;
                              _errors['smokeType'] = '';
                            });
                          },
                          hasError: submitted && _errors['smokeType']!.isNotEmpty,
                          errorText: _errors['smokeType'],
                          isRequired: true,
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 32),
              ],
            ),
        ),
      ),
    );
  }

  void _skipPage() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.info_outline, color: AppColors.primary),
              SizedBox(width: 12),
              Text(
                "Skip Lifestyle Details?",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: const Text(
            "You can fill in your lifestyle preferences later from your profile settings.",
            style: TextStyle(fontSize: 15),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "Cancel",
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _proceedWithoutLifestyle();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                "Skip",
                style: TextStyle(color: AppColors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  void _proceedWithoutLifestyle() {
    print("Lifestyle section skipped");
    // Navigate to next page without saving lifestyle data
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const PartnerPreferencesPage()),
    );
  }

  void _validateAndSubmit() async {
    setState(() {
      submitted = true;
    });

    if (!_validateForm()) {
      _showError("Please fill all required fields correctly");
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');

      if (userDataString == null) {
        _showError("User data not found. Please login again.");
        return;
      }

      final userData = jsonDecode(userDataString);
      final userId = int.tryParse(userData["id"].toString());

      if (userId == null) {
        _showError("Invalid user ID");
        return;
      }

      // Prepare data - handle null values properly
      Map<String, String> body = {
        "userid": userId.toString(),
        "diet": _selectedDiet!,
        "drinks": _selectedDrink!,
        "drinktype": _selectedDrink != "No" ? _selectedDrinkType ?? "" : "",
        "smoke": _selectedSmoke!,
        "smoketype": _selectedSmoke != "No" ? _selectedSmokeType ?? "" : "",
      };

      // Remove empty values to avoid sending null to API
      body.removeWhere((key, value) => value.isEmpty);

      // API URL
      String url = "${kApiBaseUrl}/Api2/user_lifestyle.php";

      print("Submitting data: $body");

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: body,
      ).timeout(const Duration(seconds: 30));

      // Log full response details
      print("HTTP Status: ${response.statusCode}");
      print("Response headers: ${response.headers}");
      final rawBody = response.body.trim();
      print("Raw body (first 500 chars): ${rawBody.substring(0, rawBody.length.clamp(0, 500))}");

      // Check HTTP status code
      if (response.statusCode != 200) {
        print("Non-200 status code: ${response.statusCode}");
        _showError("Server error (${response.statusCode}). Please try again.");
        return;
      }

      // Check if body is empty
      if (rawBody.isEmpty) {
        print("Empty response body received");
        _showError("Server returned empty response. Please try again.");
        return;
      }

      // Check if response looks like HTML (common error response format)
      if (rawBody.startsWith('<') || rawBody.toLowerCase().contains('<!doctype') || rawBody.toLowerCase().contains('<html')) {
        print("HTML response detected instead of JSON");
        _showError("Server returned an error page. Please contact support.");
        return;
      }

      // Attempt to extract JSON even if PHP warning/notice text is prepended
      final jsonStart = rawBody.indexOf('{');
      final jsonEnd = rawBody.lastIndexOf('}');

      if (jsonStart == -1 || jsonEnd == -1 || jsonEnd <= jsonStart) {
        print("No valid JSON object found in response");
        _showError("Invalid server response format. Please try again.");
        return;
      }

      final jsonCandidate = rawBody.substring(jsonStart, jsonEnd + 1);

      if (jsonCandidate != rawBody) {
        print("Non-JSON prefix detected. Extracted candidate: $jsonCandidate");
      }

      // Parse JSON with error handling
      final dynamic data;
      try {
        data = json.decode(jsonCandidate);
        print("API Response: $data");
      } on FormatException catch (e) {
        print("FormatException: $e");
        print("JSON candidate that failed: $jsonCandidate");
        _showError("Server returned invalid JSON. Please try again or contact support.");
        return;
      }

      // Validate response is a Map
      if (data is! Map<String, dynamic>) {
        print("Unexpected response type: ${data.runtimeType}");
        _showError("Unexpected response format. Please try again.");
        return;
      }

      if (data['status'] == 'success') {
        _showSuccess(data['message'] ?? "Lifestyle details saved successfully!");

        if (widget.isEditMode) {
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) Navigator.pop(context);
          });
        } else {
          // Update page number
          await UpdateService.updatePageNumber(
            userId: userId.toString(),
            pageNo: 7,
          );

          // Navigate to next page
          Future.delayed(const Duration(seconds: 1), () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const PartnerPreferencesPage()),
            );
          });
        }
      } else {
        _showError(data['message'] ?? "Submission failed. Please try again.");
      }
    } catch (e) {
      _showError("Network error: $e");
      print("Error details: $e");
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showError(String message) {
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
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showSuccess(String message) {
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
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
