import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:ms2026/Auth/Screen/signupscreen7.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../../../ReUsable/dropdownwidget.dart';
import 'package:ms2026/config/app_endpoints.dart';

class EducationCareerPagee extends StatefulWidget {
  const EducationCareerPagee({
    super.key,
    this.initialData,
  });

  final Map<String, dynamic>? initialData;

  @override
  State<EducationCareerPagee> createState() => _EducationCareerPageeState();
}

class _EducationCareerPageeState extends State<EducationCareerPagee> {
  bool submitted = false;
  bool isLoading = false;
  bool isDataLoaded = false;

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

  String? _selectedDesignation;

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

  // Key for forcing dropdown refresh
  final GlobalKey _refreshKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialData != null && widget.initialData!.isNotEmpty) {
        _applySavedData(widget.initialData!);
        setState(() {
          isDataLoaded = true;
        });
      } else {
        _loadSavedData();
      }
    });
  }

  Future<void> _loadSavedData() async {
    try {
      setState(() {
        isLoading = true;
      });

      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');
      final userData = jsonDecode(userDataString!);
      final userId = int.tryParse(userData["id"].toString());

      if (userId == null) {
        _showError("User not found");
        return;
      }

      print("Loading data for user ID: $userId");

      // Call GET API
      var url = Uri.parse("${kApiBaseUrl}/Api2/get_educationcareer.php?userid=$userId");
      var response = await http.get(url);

      print("API Response Status: ${response.statusCode}");
      print("API Response Body: ${response.body}");

      if (response.statusCode == 200) {
        var data = json.decode(response.body);

        if (data['status'] == 'success' && data['data'] != null) {
          final savedData = data['data'];
          print("Loaded Data: $savedData");
          _applySavedData(savedData);
          setState(() {
            isDataLoaded = true;
          });

          print("Data loaded successfully!");
          print("Education Medium: $_selectedEducationMedium");
          print("Education Type: $_selectedEducationType");
          print("Faculty: $_selectedFaculty");
          print("Degree: $_selectedEducationDegree");
          print("Is Working: $_isWorking");
          print("Occupation Type: $_occupationType");
          print("Designation: $_selectedDesignation");

          _showSuccess("Data loaded successfully");
        } else {
          // No data found for this user
          print("No saved data found");
          setState(() {
            isDataLoaded = true;
            // Reset all fields
            _selectedEducationMedium = null;
            _selectedEducationType = null;
            _selectedFaculty = null;
            _selectedEducationDegree = null;
            _isWorking = null;
            _occupationType = null;
            _selectedDesignation = null;
            _selectedWorkingWith = null;
            _selectedAnnualIncome = null;
            _selectedBusinessWorkingWith = null;
            _selectedBusinessAnnualIncome = null;
            _companyNameController.clear();
            _businessNameController.clear();
            _designationController.clear();
            _businessDesignationController.clear();
          });
          _showInfo("No saved data found. Please fill the form.");
        }
      } else {
        print("Failed to load data: ${response.statusCode}");
        _showError("Failed to load data: ${response.statusCode}");
      }
    } catch (e) {
      print("Error loading data: $e");
      _showError("Error loading data: $e");
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  // Helper method to get valid value
  String? _getValidValue(dynamic value) {
    if (value == null || value.toString().trim().isEmpty) {
      return null;
    }
    return value.toString();
  }

  void _applySavedData(Map<String, dynamic> savedData) {
    setState(() {
      _selectedEducationMedium = _getValidValue(savedData['educationmedium']);
      _selectedEducationType = _getValidValue(savedData['educationtype']);
      _selectedFaculty = _getValidValue(savedData['faculty']);
      _selectedEducationDegree = _getValidValue(savedData['degree']);

      final areYouWorking = savedData['areyouworking']?.toString().toLowerCase() ?? '';
      _isWorking = areYouWorking == "yes" || areYouWorking == "1" || areYouWorking == "true";
      _occupationType = _getValidValue(savedData['occupationtype']);

      _companyNameController.clear();
      _businessNameController.clear();
      _designationController.clear();
      _businessDesignationController.clear();

      if (_occupationType == "Job" || _occupationType == null) {
        _companyNameController.text = savedData['companyname']?.toString() ?? '';
        _selectedDesignation = _getValidValue(savedData['designation']);
        _selectedWorkingWith = _getValidValue(savedData['workingwith']);
        _selectedAnnualIncome = _getValidValue(savedData['annualincome']);
        _selectedBusinessWorkingWith = null;
        _selectedBusinessAnnualIncome = null;
      } else if (_occupationType == "Business") {
        _businessNameController.text = savedData['businessname']?.toString() ?? '';
        _selectedDesignation = _getValidValue(savedData['designation']);
        _selectedBusinessWorkingWith = _getValidValue(savedData['workingwith']);
        _selectedBusinessAnnualIncome = _getValidValue(savedData['annualincome']);
        _selectedWorkingWith = null;
        _selectedAnnualIncome = null;
      } else {
        _selectedDesignation = _getValidValue(savedData['designation']);
        _selectedWorkingWith = _getValidValue(savedData['workingwith']);
        _selectedAnnualIncome = _getValidValue(savedData['annualincome']);
        _selectedBusinessWorkingWith = null;
        _selectedBusinessAnnualIncome = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _refreshKey, // Add key to force refresh
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Education & Career', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFFE64B37),
        elevation: 0,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  const Center(
                    child: Text(
                      "Education & Career",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFE64B37),
                      ),
                    ),
                  ),

                  const SizedBox(height: 25),

                  // Education Section
                  _buildSectionTitle("Education Medium*"),
                  const SizedBox(height: 8),
                  Container(
                    child: TypingDropdown<String>(
                      key: ValueKey('educationmedium_$_selectedEducationMedium'), // Force rebuild
                      items: _educationMediumOptions,
                      selectedItem: _selectedEducationMedium,
                      itemLabel: (item) => item,
                      hint: "Medium*",
                      onChanged: (value) {
                        setState(() {
                          _selectedEducationMedium = value;
                        });
                      },
                      title: 'Medium',
                      showError: submitted,
                    ),
                  ),

                  const SizedBox(height: 15),

                  _buildSectionTitle("Education Type*"),
                  const SizedBox(height: 8),
                  Container(
                    child: TypingDropdown<String>(
                      key: ValueKey('educationtype_$_selectedEducationType'), // Force rebuild
                      items: _educationTypeOptions,
                      selectedItem: _selectedEducationType,
                      itemLabel: (item) => item,
                      hint: "Education Type*",
                      onChanged: (value) {
                        setState(() {
                          _selectedEducationType = value;
                        });
                      },
                      title: 'Education type',
                      showError: submitted,
                    ),
                  ),

                  const SizedBox(height: 15),

                  _buildSectionTitle("Faculty*"),
                  const SizedBox(height: 8),
                  Container(
                    child: TypingDropdown<String>(
                      key: ValueKey('faculty_$_selectedFaculty'), // Force rebuild
                      items: _facultyOptions,
                      selectedItem: _selectedFaculty,
                      itemLabel: (item) => item,
                      hint: "Faculty*",
                      onChanged: (value) {
                        setState(() {
                          _selectedFaculty = value;
                        });
                      },
                      title: 'Faculty',
                      showError: submitted,
                    ),
                  ),

                  const SizedBox(height: 15),

                  _buildSectionTitle("Education Degree*"),
                  const SizedBox(height: 8),
                  Container(
                    child: TypingDropdown<String>(
                      key: ValueKey('degree_$_selectedEducationDegree'), // Force rebuild
                      items: _educationDegreeOptions,
                      selectedItem: _selectedEducationDegree,
                      itemLabel: (item) => item,
                      hint: "Education Degree*",
                      onChanged: (value) {
                        setState(() {
                          _selectedEducationDegree = value;
                        });
                      },
                      title: 'Education degree',
                      showError: submitted,
                    ),
                  ),

                  const SizedBox(height: 25),
                  _buildDivider(),
                  const SizedBox(height: 25),

                  // Career Section
                  _buildSectionTitle("Career Details*"),
                  const SizedBox(height: 12),

                  _buildSectionTitle("Are You Working?*"),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildRadioOption(
                          value: true,
                          groupValue: _isWorking,
                          label: "Yes",
                          onChanged: (value) {
                            setState(() {
                              _isWorking = value;
                              _occupationType = null;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: _buildRadioOption(
                          value: false,
                          groupValue: _isWorking,
                          label: "No",
                          onChanged: (value) {
                            setState(() {
                              _isWorking = value;
                              _occupationType = null;
                            });
                          },
                        ),
                      ),
                    ],
                  ),

                  // Show occupation type only if working
                  if (_isWorking == true) ...[
                    const SizedBox(height: 20),
                    _buildSectionTitle("Occupation Type?"),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildRadioOption(
                            value: "Job",
                            groupValue: _occupationType,
                            label: "Job",
                            onChanged: (value) {
                              setState(() {
                                _occupationType = value;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: _buildRadioOption(
                            value: "Business",
                            groupValue: _occupationType,
                            label: "Business",
                            onChanged: (value) {
                              setState(() {
                                _occupationType = value;
                              });
                            },
                          ),
                        ),
                      ],
                    ),

                    // Show Job Details
                    if (_occupationType == "Job") ...[
                      const SizedBox(height: 25),
                      _buildSectionTitle("Company Name*"),
                      const SizedBox(height: 8),
                      _buildTextField(
                        _companyNameController,
                        "Enter company name",
                      ),

                      const SizedBox(height: 15),

                      _buildSectionTitle("Designation*"),
                      const SizedBox(height: 8),
                      Container(
                        child: TypingDropdown<String>(
                          key: ValueKey('designation_job_$_selectedDesignation'), // Force rebuild
                          items: _designationOptions,
                          selectedItem: _selectedDesignation,
                          itemLabel: (item) => item,
                          hint: "Designation*",
                          onChanged: (value) {
                            setState(() {
                              _selectedDesignation = value;
                            });
                          },
                          title: 'Designation',
                          showError: submitted,
                        ),
                      ),

                      const SizedBox(height: 15),

                      _buildSectionTitle("Working With*"),
                      const SizedBox(height: 8),
                      Container(
                        child: TypingDropdown<String>(
                          key: ValueKey('workingwith_job_$_selectedWorkingWith'), // Force rebuild
                          items: _workingWithOptions,
                          selectedItem: _selectedWorkingWith,
                          itemLabel: (item) => item,
                          hint: "Select working with*",
                          onChanged: (value) {
                            setState(() {
                              _selectedWorkingWith = value;
                            });
                          },
                          title: 'Working with',
                          showError: submitted,
                        ),
                      ),

                      const SizedBox(height: 15),

                      _buildSectionTitle("Annual Income*"),
                      const SizedBox(height: 8),
                      Container(
                        child: TypingDropdown<String>(
                          key: ValueKey('income_job_$_selectedAnnualIncome'), // Force rebuild
                          items: _annualIncomeOptions,
                          selectedItem: _selectedAnnualIncome,
                          itemLabel: (item) => item,
                          hint: "Select annual income*",
                          onChanged: (value) {
                            setState(() {
                              _selectedAnnualIncome = value;
                            });
                          },
                          title: 'Annual incomes',
                          showError: submitted,
                        ),
                      ),
                    ],

                    // Show Business Details
                    if (_occupationType == "Business") ...[
                      const SizedBox(height: 25),
                      _buildSectionTitle("Business Name*"),
                      const SizedBox(height: 8),
                      _buildTextField(
                        _businessNameController,
                        "Enter business name",
                      ),

                      const SizedBox(height: 15),

                      _buildSectionTitle("Designation*"),
                      const SizedBox(height: 8),
                      Container(
                        child: TypingDropdown<String>(
                          key: ValueKey('designation_business_$_selectedDesignation'), // Force rebuild
                          items: _designationOptions,
                          selectedItem: _selectedDesignation,
                          itemLabel: (item) => item,
                          hint: "Enter your designation",
                          onChanged: (value) {
                            setState(() {
                              _selectedDesignation = value;
                            });
                          },
                          title: 'Designation',
                          showError: submitted,
                        ),
                      ),

                      const SizedBox(height: 15),

                      _buildSectionTitle("Working With*"),
                      const SizedBox(height: 8),
                      Container(
                        child: TypingDropdown<String>(
                          key: ValueKey('workingwith_business_$_selectedBusinessWorkingWith'), // Force rebuild
                          items: _workingWithOptions,
                          selectedItem: _selectedBusinessWorkingWith,
                          itemLabel: (item) => item,
                          hint: "Select working with",
                          onChanged: (value) {
                            setState(() {
                              _selectedBusinessWorkingWith = value;
                            });
                          },
                          title: 'Working with',
                          showError: submitted,
                        ),
                      ),

                      const SizedBox(height: 15),

                      _buildSectionTitle("Annual Income*"),
                      const SizedBox(height: 8),
                      Container(
                        child: TypingDropdown<String>(
                          key: ValueKey('income_business_$_selectedBusinessAnnualIncome'), // Force rebuild
                          items: _annualIncomeOptions,
                          selectedItem: _selectedBusinessAnnualIncome,
                          itemLabel: (item) => item,
                          hint: "Select annual income",
                          onChanged: (value) {
                            setState(() {
                              _selectedBusinessAnnualIncome = value;
                            });
                          },
                          title: 'Annual income',
                          showError: submitted,
                        ),
                      ),
                    ],
                  ],

                  const SizedBox(height: 35),

                  // Buttons
                  Row(
                    children: [
                      Expanded(
                        child: _buildButton(
                          text: "Reload Data",
                          isPrimary: false,
                          onPressed: () {
                            _loadSavedData();
                          },
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: _buildButton(
                          text: "Save",
                          isPrimary: true,
                          onPressed: () {
                            _validateAndSubmit();
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 30),
                ],
              ),
            ),

            // Progress bubble
            Positioned(
              right: 12,
              top: 8,
              child: _progressBubble(0.30, "70%"),
            ),

            // Loading indicator
            if (isLoading)
              Container(
                color: Colors.black.withOpacity(0.5),
                child: const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE64B37)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ... (Keep all your existing helper methods: _buildSectionTitle, _buildDivider,
  // _buildTextField, _buildDropdown, _buildRadioOption, _buildButton, _progressBubble)
  // Make sure all these methods are present

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: Colors.black87,
      ),
    );
  }

  Widget _buildDivider() {
    return const Divider(
      color: Colors.grey,
      height: 1,
      thickness: 1,
    );
  }

  Widget _buildTextField(TextEditingController controller, String hintText) {
    return Container(
      height: 55,
      padding: const EdgeInsets.symmetric(horizontal: 15),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: const Color(0xFF48A54C),
          width: 1.6,
        ),
      ),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: hintText,
          hintStyle: const TextStyle(fontSize: 16, color: Colors.black54),
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String? value,
    required String hint,
    required List<String> items,
    required Function(String?) onChanged,
  }) {
    return Container(
      height: 55,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: const Color(0xFF48A54C),
          width: 1.6,
        ),
      ),
      child: ExcludeFocus(
        excluding: true,
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            icon: const Icon(Icons.keyboard_arrow_down, color: Colors.black54),
            hint: Text(
              hint,
              style: const TextStyle(fontSize: 16, color: Colors.black54),
            ),
            items: items.map((String item) {
              return DropdownMenuItem<String>(
                value: item,
                child: Text(
                  item,
                  style: const TextStyle(fontSize: 16, color: Colors.black87),
                ),
              );
            }).toList(),
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }

  Widget _buildRadioOption({
    required dynamic value,
    required dynamic groupValue,
    required String label,
    required Function(dynamic) onChanged,
  }) {
    bool isSelected = groupValue == value;

    return Material(
      color: Colors.transparent,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0xFF48A54C),
            width: 1.2,
          ),
          color: isSelected ? const Color(0xFFE64B37).withOpacity(0.1) : Colors.transparent,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: () {
            onChanged(value);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? const Color(0xFFE64B37) : Colors.grey,
                      width: 2,
                    ),
                    color: isSelected ? const Color(0xFFE64B37) : Colors.transparent,
                  ),
                  child: isSelected
                      ? const Icon(
                    Icons.circle,
                    size: 10,
                    color: Colors.white,
                  )
                      : null,
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.black87,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildButton({
    required String text,
    required bool isPrimary,
    required VoidCallback onPressed,
  }) {
    return Container(
      height: 55,
      decoration: BoxDecoration(
        gradient: isPrimary
            ? const LinearGradient(
          colors: [
            Color(0xFFE64B37),
            Color(0xFFE62255),
          ],
        )
            : const LinearGradient(
          colors: [
            Color(0xFFEEA2A4),
            Color(0xFFF3C0C4),
          ],
        ),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: onPressed,
          child: Center(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _progressBubble(double progress, String label) {
    final size = 42.0;
    return SizedBox(
      height: size,
      width: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: size,
            width: size,
            decoration:  BoxDecoration(
              color: Colors.red.shade100,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(
            height: size,
            width: size,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 3.2,
              valueColor: const AlwaysStoppedAnimation(Color(0xFFE64B37)),
              backgroundColor: Colors.white,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFFE64B37),
            ),
          ),
        ],
      ),
    );
  }

  void _validateAndSubmit() async {
    setState(() {
      submitted = true;
    });

    // Validation logic (same as before)
    if (_selectedEducationMedium == null) {
      _showError("Please select education medium");
      return;
    }

    if (_selectedEducationType == null) {
      _showError("Please select education type");
      return;
    }

    if (_selectedFaculty == null) {
      _showError("Please select faculty");
      return;
    }

    if (_selectedEducationDegree == null) {
      _showError("Please select education degree");
      return;
    }

    if (_isWorking == null) {
      _showError("Please select if you are working");
      return;
    }

    String occupationType = '';
    String companyName = '';
    String designation = '';
    String workingWith = '';
    String annualIncome = '';
    String businessName = '';

    if (_isWorking == true) {
      if (_occupationType == null) {
        _showError("Please select occupation type");
        return;
      }

      occupationType = _occupationType!;

      if (_occupationType == "Job") {
        if (_companyNameController.text.isEmpty) {
          _showError("Please enter company name");
          return;
        }
        if (_selectedDesignation == null) {
          _showError("Please enter designation");
          return;
        }
        if (_selectedWorkingWith == null) {
          _showError("Please select working with");
          return;
        }
        if (_selectedAnnualIncome == null) {
          _showError("Please select annual income");
          return;
        }

        companyName = _companyNameController.text;
        designation = _selectedDesignation!;
        workingWith = _selectedWorkingWith!;
        annualIncome = _selectedAnnualIncome!;
      } else if (_occupationType == "Business") {
        if (_businessNameController.text.isEmpty) {
          _showError("Please enter business name");
          return;
        }
        if (_selectedDesignation == null) {
          _showError("Please enter designation");
          return;
        }
        if (_selectedBusinessWorkingWith == null) {
          _showError("Please select working with");
          return;
        }
        if (_selectedBusinessAnnualIncome == null) {
          _showError("Please select annual income");
          return;
        }

        businessName = _businessNameController.text;
        designation = _selectedDesignation!;
        workingWith = _selectedBusinessWorkingWith!;
        annualIncome = _selectedBusinessAnnualIncome!;
      }
    }

    // API CALL
    try {
      setState(() {
        isLoading = true;
      });

      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');
      final userData = jsonDecode(userDataString!);
      final userId = int.tryParse(userData["id"].toString());

      var url = Uri.parse("${kApiBaseUrl}/Api2/educationcareer.php");
      var response = await http.post(url, body: {
        "userid": userId.toString(),
        "educationmedium": _selectedEducationMedium ?? '',
        "educationtype": _selectedEducationType ?? '',
        "faculty": _selectedFaculty ?? '',
        "degree": _selectedEducationDegree ?? '',
        "areyouworking": _isWorking == true ? "Yes" : "No",
        "occupationtype": occupationType,
        "companyname": companyName,
        "designation": designation,
        "workingwith": workingWith,
        "annualincome": annualIncome,
        "businessname": businessName,
      });

      var data = json.decode(response.body);

      if (data['status'] == 'success') {
        _showSuccess(data['message']);
Navigator.pop(context);
      } else {
        _showError(data['message'] ?? "Failed to save data");
      }
    } catch (e) {
      _showError("Something went wrong: $e");
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showInfo(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  void dispose() {
    _companyNameController.dispose();
    _designationController.dispose();
    _businessNameController.dispose();
    _businessDesignationController.dispose();
    super.dispose();
  }
}
