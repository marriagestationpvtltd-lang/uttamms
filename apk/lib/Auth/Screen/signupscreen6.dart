import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ms2026/Auth/Screen/signupscreen7.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../ReUsable/dropdownwidget.dart';
import '../../ReUsable/registration_progress.dart';
import '../../ReUsable/enhanced_form_fields.dart';
import '../../constant/app_colors.dart';
import '../../service/updatepage.dart';
import 'package:ms2026/config/app_endpoints.dart';

class EducationCareerPage extends StatefulWidget {
  const EducationCareerPage({
    super.key,
    this.isEditMode = false,
    this.initialData,
  });

  final bool isEditMode;
  final Map<String, dynamic>? initialData;

  @override
  State<EducationCareerPage> createState() => _EducationCareerPageState();
}

class _EducationCareerPageState extends State<EducationCareerPage> {
  bool submitted = false;
  bool isLoading = false;

  // Education Section
  String? _selectedEducationMedium;
  String? _selectedEducationType;
  String? _selectedFaculty;
  String? _selectedEducationDegree;

  // Career Section
  bool? _isWorking;
  String? _occupationType;

  // Job Details
  final TextEditingController _companyNameController = TextEditingController();
  final TextEditingController _designationController = TextEditingController();
  String? _selectedWorkingWith;
  String? _selectedAnnualIncome;

  // Business Details
  final TextEditingController _businessNameController = TextEditingController();
  final TextEditingController _businessDesignationController = TextEditingController();
  String? _selectedBusinessWorkingWith;
  String? _selectedBusinessAnnualIncome;

  // Designation dropdown
  String? _selectedDesignation;

  // Error messages
  final Map<String, String> _errors = {
    'educationMedium': '',
    'educationType': '',
    'faculty': '',
    'educationDegree': '',
    'isWorking': '',
    'occupationType': '',
    'companyName': '',
    'designation': '',
    'workingWith': '',
    'annualIncome': '',
    'businessName': '',
    'businessWorkingWith': '',
    'businessAnnualIncome': '',
  };

  // Dropdown options
  final List<String> _educationMediumOptions = [
    'English',
    'Nepali',
    'Hindi',
    'Other'
  ];

  final List<String> _educationTypeOptions = [
    'Regular',
    'Distance Learning',
    'Online',
    'Correspondence',
    'Other'
  ];

  final List<String> _facultyOptions = [
    'Science',
    'Management',
    'Humanities',
    'Education',
    'Engineering',
    'Medicine',
    'Law',
    'Agriculture',
    'Forestry',
    'Computer Science',
    'Other'
  ];

  final List<String> _educationDegreeOptions = [
    'SEE/SLC',
    '+2/Intermediate',
    'Diploma',
    'Bachelor',
    'Master',
    'PhD',
    'Post Doctoral',
    'Other'
  ];

  final List<String> _workingWithOptions = [
    'Private Company',
    'Government',
    'NGO/INGO',
    'Self Employed',
    'Family Business',
    'Startup',
    'Other'
  ];

  final List<String> _annualIncomeOptions = [
    'Below 2 Lakhs',
    '2-5 Lakhs',
    '5-10 Lakhs',
    '10-20 Lakhs',
    '20-50 Lakhs',
    '50 Lakhs - 1 Crore',
    'Above 1 Crore'
  ];

  final List<String> _designationOptions = [
    "Software Developer",
    "Senior Software Developer",
    "Mobile App Developer",
    "Flutter Developer",
    "Backend Developer",
    "Full Stack Developer",
    "Frontend Developer",
    "UI/UX Designer",
    "Graphic Designer",
    "Web Designer",
    "Project Manager",
    "Product Manager",
    "Team Lead",
    "CEO",
    "CTO",
    "COO",
    "Founder",
    "Co-Founder",
    "Business Analyst",
    "Data Analyst",
    "Data Scientist",
    "Machine Learning Engineer",
    "AI Engineer",
    "Cloud Engineer",
    "DevOps Engineer",
    "QA Tester",
    "QA Engineer",
    "Digital Marketer",
    "SEO Specialist",
    "Content Writer",
    "Copywriter",
    "Accountant",
    "Finance Manager",
    "HR Manager",
    "HR Executive",
    "Marketing Manager",
    "Sales Executive",
    "Sales Manager",
    "Customer Support",
    "Receptionist",
    "Teacher",
    "Professor",
    "Doctor",
    "Nurse",
    "Engineer",
    "Civil Engineer",
    "Mechanical Engineer",
    "Electrical Engineer",
    "Driver",
    "Security Guard",
    "Chef",
    "Entrepreneur",
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
    _selectedEducationMedium = _getValidValue(data['educationmedium'], _educationMediumOptions);
    _selectedEducationType = _getValidValue(data['educationtype'], _educationTypeOptions);
    _selectedFaculty = _getValidValue(data['faculty'], _facultyOptions);
    _selectedEducationDegree = _getValidValue(data['degree'], _educationDegreeOptions);

    final areYouWorking = data['areyouworking']?.toString().toLowerCase() ?? '';
    _isWorking = areYouWorking == 'yes' || areYouWorking == '1' || areYouWorking == 'true';
    _occupationType = data['occupationtype']?.toString();

    _companyNameController.text = data['companyname']?.toString() ?? '';
    _designationController.text = '';
    _selectedDesignation = _getValidValue(data['designation'], _designationOptions);
    if (_selectedDesignation == null && (data['designation']?.toString() ?? '').isNotEmpty) {
      _designationController.text = data['designation'].toString();
    }
    _selectedWorkingWith = _getValidValue(data['workingwith'], _workingWithOptions);
    _selectedAnnualIncome = _getValidValue(data['annualincome'], _annualIncomeOptions);

    if (_occupationType == 'Business') {
      _businessNameController.text = data['businessname']?.toString() ?? '';
      _selectedBusinessWorkingWith = _getValidValue(data['workingwith'], _workingWithOptions);
      _selectedBusinessAnnualIncome = _getValidValue(data['annualincome'], _annualIncomeOptions);
    }
  }

  @override
  void dispose() {
    _companyNameController.dispose();
    _designationController.dispose();
    _businessNameController.dispose();
    _businessDesignationController.dispose();
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

  bool _validateWorkingDetails() {
    bool isValid = true;

    if (_isWorking == true) {
      if (!_validateRequired(_occupationType, 'occupationType')) {
        isValid = false;
      }

      if (_occupationType == "Job") {
        if (!_validateRequired(_companyNameController.text.trim(), 'companyName')) {
          isValid = false;
        }
        if (!_validateRequired(_selectedDesignation, 'designation')) {
          isValid = false;
        }
        if (!_validateRequired(_selectedWorkingWith, 'workingWith')) {
          isValid = false;
        }
        if (!_validateRequired(_selectedAnnualIncome, 'annualIncome')) {
          isValid = false;
        }
      } else if (_occupationType == "Business") {
        if (!_validateRequired(_businessNameController.text.trim(), 'businessName')) {
          isValid = false;
        }
        if (!_validateRequired(_selectedDesignation, 'designation')) {
          isValid = false;
        }
        if (!_validateRequired(_selectedBusinessWorkingWith, 'businessWorkingWith')) {
          isValid = false;
        }
        if (!_validateRequired(_selectedBusinessAnnualIncome, 'businessAnnualIncome')) {
          isValid = false;
        }
      }
    }

    return isValid;
  }

  bool _validateForm() {
    bool isValid = true;

    // Clear all errors
    _errors.forEach((key, value) {
      _errors[key] = '';
    });

    // Education validation
    if (!_validateRequired(_selectedEducationMedium, 'educationMedium')) {
      isValid = false;
    }
    if (!_validateRequired(_selectedEducationType, 'educationType')) {
      isValid = false;
    }
    if (!_validateRequired(_selectedFaculty, 'faculty')) {
      isValid = false;
    }
    if (!_validateRequired(_selectedEducationDegree, 'educationDegree')) {
      isValid = false;
    }

    // Career validation
    if (_isWorking == null) {
      _errors['isWorking'] = 'Please select if you are working';
      isValid = false;
    } else {
      _errors['isWorking'] = '';
    }

    // Validate working details
    if (!_validateWorkingDetails()) {
      isValid = false;
    }

    setState(() {});
    return isValid;
  }

  // Handler methods
  void _handleEducationMediumChange(String? value) {
    setState(() {
      _selectedEducationMedium = value;
      _errors['educationMedium'] = '';
    });
  }

  void _handleEducationTypeChange(String? value) {
    setState(() {
      _selectedEducationType = value;
      _errors['educationType'] = '';
    });
  }

  void _handleFacultyChange(String? value) {
    setState(() {
      _selectedFaculty = value;
      _errors['faculty'] = '';
    });
  }

  void _handleEducationDegreeChange(String? value) {
    setState(() {
      _selectedEducationDegree = value;
      _errors['educationDegree'] = '';
    });
  }

  void _handleIsWorkingChange(bool? value) {
    setState(() {
      _isWorking = value;
      _errors['isWorking'] = '';
      // Clear occupation type when changing working status
      _occupationType = null;
      _errors['occupationType'] = '';
    });
  }

  void _handleOccupationTypeChange(String? value) {
    FocusScope.of(context).unfocus();
    setState(() {
      _occupationType = value;
      _errors['occupationType'] = '';
    });
  }

  void _handleDesignationChange(String? value) {
    setState(() {
      _selectedDesignation = value;
      _errors['designation'] = '';
    });
  }

  void _handleWorkingWithChange(String? value) {
    setState(() {
      _selectedWorkingWith = value;
      _errors['workingWith'] = '';
    });
  }

  void _handleAnnualIncomeChange(String? value) {
    setState(() {
      _selectedAnnualIncome = value;
      _errors['annualIncome'] = '';
    });
  }

  void _handleBusinessWorkingWithChange(String? value) {
    setState(() {
      _selectedBusinessWorkingWith = value;
      _errors['businessWorkingWith'] = '';
    });
  }

  void _handleBusinessAnnualIncomeChange(String? value) {
    setState(() {
      _selectedBusinessAnnualIncome = value;
      _errors['businessAnnualIncome'] = '';
    });
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
          isLoading: isLoading,
          canContinue: !isLoading,
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                RegistrationStepHeader(
                  title: 'Education & Career',
                  subtitle: 'Tell us about your educational background and professional life',
                  currentStep: 7,
                  totalSteps: 11,
                  onBack: () => Navigator.pop(context),
                  onStepBack: () => Navigator.pop(context), // Allow step-by-step back navigation
                ),
                const SizedBox(height: 32),

                // Education Section
                const SectionHeader(
                  title: 'Education Details',
                  subtitle: 'Share your educational background',
                  icon: Icons.school_rounded,
                ),
                const SizedBox(height: 20),

                EnhancedDropdown<String>(
                  label: 'Education Medium',
                  value: _selectedEducationMedium,
                  items: _educationMediumOptions,
                  itemLabel: (item) => item,
                  hint: 'Select medium of education',
                  onChanged: _handleEducationMediumChange,
                  hasError: submitted && _errors['educationMedium']!.isNotEmpty,
                  errorText: _errors['educationMedium'],
                  isRequired: true,
                ),
                const SizedBox(height: 16),

                EnhancedDropdown<String>(
                  label: 'Education Type',
                  value: _selectedEducationType,
                  items: _educationTypeOptions,
                  itemLabel: (item) => item,
                  hint: 'Select type of education',
                  onChanged: _handleEducationTypeChange,
                  hasError: submitted && _errors['educationType']!.isNotEmpty,
                  errorText: _errors['educationType'],
                  isRequired: true,
                ),
                const SizedBox(height: 16),

                EnhancedDropdown<String>(
                  label: 'Faculty',
                  value: _selectedFaculty,
                  items: _facultyOptions,
                  itemLabel: (item) => item,
                  hint: 'Select your faculty',
                  onChanged: _handleFacultyChange,
                  hasError: submitted && _errors['faculty']!.isNotEmpty,
                  errorText: _errors['faculty'],
                  isRequired: true,
                ),
                const SizedBox(height: 16),

                EnhancedDropdown<String>(
                  label: 'Education Degree',
                  value: _selectedEducationDegree,
                  items: _educationDegreeOptions,
                  itemLabel: (item) => item,
                  hint: 'Select your highest degree',
                  onChanged: _handleEducationDegreeChange,
                  hasError: submitted && _errors['educationDegree']!.isNotEmpty,
                  errorText: _errors['educationDegree'],
                  isRequired: true,
                ),
                const SizedBox(height: 32),

                // Career Section
                const SectionHeader(
                  title: 'Career Details',
                  subtitle: 'Tell us about your professional life',
                  icon: Icons.work_rounded,
                ),
                const SizedBox(height: 20),

                // Working Status
                _buildFieldLabel('Are You Currently Working?', isRequired: true),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: EnhancedRadioOption<bool>(
                        label: 'Yes',
                        value: true,
                        groupValue: _isWorking,
                        onChanged: _handleIsWorkingChange,
                        icon: Icons.check_circle_outline,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: EnhancedRadioOption<bool>(
                        label: 'No',
                        value: false,
                        groupValue: _isWorking,
                        onChanged: _handleIsWorkingChange,
                        icon: Icons.cancel_outlined,
                      ),
                    ),
                  ],
                ),
                if (submitted && _errors['isWorking']!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildErrorText(_errors['isWorking']!),
                ],

                // Show occupation type only if working
                if (_isWorking == true) ...[
                  const SizedBox(height: 24),
                  _buildFieldLabel('Occupation Type', isRequired: true),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: EnhancedRadioOption<String>(
                          label: 'Job',
                          value: 'Job',
                          groupValue: _occupationType,
                          onChanged: _handleOccupationTypeChange,
                          icon: Icons.business_center_outlined,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: EnhancedRadioOption<String>(
                          label: 'Business',
                          value: 'Business',
                          groupValue: _occupationType,
                          onChanged: _handleOccupationTypeChange,
                          icon: Icons.storefront_outlined,
                        ),
                      ),
                    ],
                  ),
                  if (submitted && _errors['occupationType']!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _buildErrorText(_errors['occupationType']!),
                  ],

                  // Show Job Details
                  if (_occupationType == "Job") ...[
                    const SizedBox(height: 24),
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
                                  Icons.work_outline,
                                  size: 20,
                                  color: AppColors.white,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'Job Details',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          EnhancedTextField(
                            label: 'Company Name',
                            controller: _companyNameController,
                            hint: 'Enter your company name',
                            prefixIcon: Icons.apartment_rounded,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => FocusScope.of(context).unfocus(),
                            hasError: submitted && _errors['companyName']!.isNotEmpty,
                            errorText: _errors['companyName'],
                            validator: (value) => '',
                          ),
                          const SizedBox(height: 16),
                          EnhancedDropdown<String>(
                            label: 'Designation',
                            value: _selectedDesignation,
                            items: _designationOptions,
                            itemLabel: (item) => item,
                            hint: 'Select your designation',
                            onChanged: _handleDesignationChange,
                            hasError: submitted && _errors['designation']!.isNotEmpty,
                            errorText: _errors['designation'],
                            isRequired: true,
                          ),
                          const SizedBox(height: 16),
                          EnhancedDropdown<String>(
                            label: 'Working With',
                            value: _selectedWorkingWith,
                            items: _workingWithOptions,
                            itemLabel: (item) => item,
                            hint: 'Select organization type',
                            onChanged: _handleWorkingWithChange,
                            hasError: submitted && _errors['workingWith']!.isNotEmpty,
                            errorText: _errors['workingWith'],
                            isRequired: true,
                          ),
                          const SizedBox(height: 16),
                          EnhancedDropdown<String>(
                            label: 'Annual Income',
                            value: _selectedAnnualIncome,
                            items: _annualIncomeOptions,
                            itemLabel: (item) => item,
                            hint: 'Select income range',
                            onChanged: _handleAnnualIncomeChange,
                            hasError: submitted && _errors['annualIncome']!.isNotEmpty,
                            errorText: _errors['annualIncome'],
                            isRequired: true,
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Show Business Details
                  if (_occupationType == "Business") ...[
                    const SizedBox(height: 24),
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
                                  Icons.business_outlined,
                                  size: 20,
                                  color: AppColors.white,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'Business Details',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          EnhancedTextField(
                            label: 'Business Name',
                            controller: _businessNameController,
                            hint: 'Enter your business name',
                            prefixIcon: Icons.storefront_rounded,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => FocusScope.of(context).unfocus(),
                            hasError: submitted && _errors['businessName']!.isNotEmpty,
                            errorText: _errors['businessName'],
                            validator: (value) => '',
                          ),
                          const SizedBox(height: 16),
                          EnhancedDropdown<String>(
                            label: 'Designation',
                            value: _selectedDesignation,
                            items: _designationOptions,
                            itemLabel: (item) => item,
                            hint: 'Select your role',
                            onChanged: _handleDesignationChange,
                            hasError: submitted && _errors['designation']!.isNotEmpty,
                            errorText: _errors['designation'],
                            isRequired: true,
                          ),
                          const SizedBox(height: 16),
                          EnhancedDropdown<String>(
                            label: 'Business Type',
                            value: _selectedBusinessWorkingWith,
                            items: _workingWithOptions,
                            itemLabel: (item) => item,
                            hint: 'Select business type',
                            onChanged: _handleBusinessWorkingWithChange,
                            hasError: submitted && _errors['businessWorkingWith']!.isNotEmpty,
                            errorText: _errors['businessWorkingWith'],
                            isRequired: true,
                          ),
                          const SizedBox(height: 16),
                          EnhancedDropdown<String>(
                            label: 'Annual Income',
                            value: _selectedBusinessAnnualIncome,
                            items: _annualIncomeOptions,
                            itemLabel: (item) => item,
                            hint: 'Select income range',
                            onChanged: _handleBusinessAnnualIncomeChange,
                            hasError: submitted && _errors['businessAnnualIncome']!.isNotEmpty,
                            errorText: _errors['businessAnnualIncome'],
                            isRequired: true,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],

                const SizedBox(height: 32),
              ],
            ),
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String label, {bool isRequired = false}) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        if (isRequired) ...[
          const SizedBox(width: 4),
          const Text(
            '*',
            style: TextStyle(
              color: AppColors.error,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildErrorText(String error) {
    return Row(
      children: [
        const Icon(
          Icons.error_outline,
          size: 14,
          color: AppColors.error,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            error,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.error,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
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
      isLoading = true;
    });

    await _submitEducationCareerData();

    setState(() {
      isLoading = false;
    });
  }

  _submitEducationCareerData() async {
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

      // Prepare request body based on occupation type
      Map<String, String> requestBody = {
        "userid": userId.toString(),
        "educationmedium": _selectedEducationMedium ?? "",
        "educationtype": _selectedEducationType ?? "",
        "faculty": _selectedFaculty ?? "",
        "degree": _selectedEducationDegree ?? "",
        "areyouworking": _isWorking == true ? "Yes" : "No",
        "occupationtype": _occupationType ?? "",
        "companyname": _companyNameController.text.trim(),
        "designation": _selectedDesignation ?? "",
        "workingwith": _selectedWorkingWith ?? _selectedBusinessWorkingWith ?? "",
        "annualincome": _selectedAnnualIncome ?? _selectedBusinessAnnualIncome ?? "",
        "businessname": _businessNameController.text.trim(),
      };

      print("Sending request: $requestBody");

      var response = await http.post(
        Uri.parse("${kApiBaseUrl}/Api2/educationcareer.php"),
        body: requestBody,
      ).timeout(const Duration(seconds: 30));

      print("Response status: ${response.statusCode}");
      print("Response body: ${response.body}");

      if (response.statusCode == 200) {
        var data;
        try {
          data = jsonDecode(response.body);
        } catch (e) {
          _showError("Invalid response from server");
          return;
        }

        if (data['status'] == 'success') {
          // Update page number only in signup flow
          if (!widget.isEditMode) {
            bool updated = await UpdateService.updatePageNumber(
              userId: userId.toString(),
              pageNo: 5,
            );

            if (updated) {
              _showSuccess("Education & career details saved successfully!");
              // Navigate after a short delay
              Future.delayed(const Duration(seconds: 1), () {
                Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => AstrologicDetailsPage())
                );
              });
            } else {
              _showError("Failed to update progress");
            }
          } else {
            _showSuccess("Education & career details saved successfully!");
            Future.delayed(const Duration(seconds: 1), () {
              if (mounted) Navigator.pop(context);
            });
          }
        } else {
          _showError(data['message'] ?? "Failed to save data");
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
