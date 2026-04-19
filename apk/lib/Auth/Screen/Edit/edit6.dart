import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:ms2026/Auth/Screen/signupscreen6.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../ReUsable/dropdownwidget.dart';
import '../../../service/updatepage.dart';
import 'package:ms2026/config/app_endpoints.dart';

class FamilyDetailsPagee extends StatefulWidget {
  const FamilyDetailsPagee({
    super.key,
    this.initialFamilyData,
  });

  final Map<String, dynamic>? initialFamilyData;

  @override
  State<FamilyDetailsPagee> createState() => _FamilyDetailsPageeState();
}

class _FamilyDetailsPageeState extends State<FamilyDetailsPagee> {
  bool submitted = false;
  bool isLoading = false;
  bool isDataLoaded = false;

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
  String? _motherEducation;
  String? _motherOccupation;

  // Other family members
  final List<FamilyMember> _familyMembers = [];
  String? _selectedMemberType;
  String? _selectedMemberMaritalStatus;
  String? _memberLivesWithUs = '';

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialFamilyData != null && widget.initialFamilyData!.isNotEmpty) {
        _applyFamilyData(widget.initialFamilyData!);
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

      print("Loading family data for user ID: $userId");

      // Call GET API
      var url = Uri.parse("${kApiBaseUrl}/Api2/get_family_details.php?userid=$userId");
      var response = await http.get(url);

      print("API Response Status: ${response.statusCode}");
      print("API Response Body: ${response.body}");

      if (response.statusCode == 200) {
        var data = json.decode(response.body);

        if (data['status'] == 'success') {
          final familyData = data['data']['family'];
          final membersData = data['data']['members'];

          print("Loaded Family Data: $familyData");
          print("Loaded Members Data: $membersData");

          // Update all state variables at once
          setState(() {
            // Load family data if exists
            if (familyData != null) {
              _applyFamilyData(familyData, updateState: false);
            }

            // Load family members
            _familyMembers.clear();
            if (membersData != null && membersData is List && membersData.isNotEmpty) {
              _hasOtherFamilyMembers = 'Yes';
              for (var member in membersData) {
                _familyMembers.add(FamilyMember(
                  type: member['membertype']?.toString() ?? '',
                  maritalStatus: member['maritalstatus']?.toString() ?? '',
                  livesWithUs: member['livestatus']?.toString() ?? '',
                ));
              }
            } else {
              _hasOtherFamilyMembers = 'NO';
            }

            isDataLoaded = true;
          });

          print("Family data loaded successfully!");
          print("Family Type: $_selectedFamilyType");
          print("Father Status: $_fatherStatus");
          print("Mother Status: $_motherStatus");
          print("Family Members Count: ${_familyMembers.length}");

          _showSuccess("Family data loaded successfully");
        } else {
          print("No saved family data found");
          setState(() {
            isDataLoaded = true;
          });
          _showInfo("No saved family data found. Please fill the form.");
        }
      } else {
        print("Failed to load family data: ${response.statusCode}");
        _showError("Failed to load family data: ${response.statusCode}");
      }
    } catch (e) {
      print("Error loading family data: $e");
      _showError("Error loading family data: $e");
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  // Helper method to get valid value
  String? _getValidValue(dynamic value) {
    if (value == null || value.toString().trim().isEmpty || value.toString().toLowerCase() == 'null') {
      return null;
    }
    return value.toString();
  }

  void _applyFamilyData(
    Map<String, dynamic> familyData, {
    bool updateState = true,
  }) {
    final apply = () {
      _selectedFamilyType = _getValidValue(familyData['familytype']);
      _selectedFamilyBackground = _getValidValue(familyData['familybackground']);
      _fatherStatus = _getValidValue(familyData['fatherstatus']);
      _motherStatus = _getValidValue(familyData['motherstatus']);
      _selectedFamilyOrigin = _getValidValue(familyData['familyorigin']);
      _fatherNameController.text = familyData['fathername']?.toString() ?? '';
      _fatherEducation = _getValidValue(familyData['fathereducation']);
      _fatherOccupation = _getValidValue(familyData['fatheroccupation']);
      _motherCastController.text = familyData['mothercaste']?.toString() ?? '';
      _motherEducation = _getValidValue(familyData['mothereducation']);
      _motherOccupation = _getValidValue(familyData['motheroccupation']);
    };

    if (updateState) {
      setState(apply);
    } else {
      apply();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Family Details', style: TextStyle(color: Colors.white)),
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
                      "Family Details",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFE64B37),
                      ),
                    ),
                  ),

                  const SizedBox(height: 25),

                  // Family Type
                  _buildSectionTitle("Family Type*"),
                  const SizedBox(height: 8),
                  Container(
                    child: TypingDropdown<String>(
                      key: ValueKey('familytype_$_selectedFamilyType'),
                      items: _familyTypeOptions,
                      selectedItem: _selectedFamilyType,
                      itemLabel: (item) => item,
                      hint: "Select Family Type",
                      onChanged: (value) {
                        setState(() {
                          _selectedFamilyType = value;
                        });
                      },
                      title: 'Family type',
                      showError: submitted,
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Family Background
                  _buildSectionTitle("Family Background*"),
                  const SizedBox(height: 8),
                  Container(
                    child: TypingDropdown<String>(
                      key: ValueKey('familybackground_$_selectedFamilyBackground'),
                      items: _familyBackgroundOptions,
                      selectedItem: _selectedFamilyBackground,
                      itemLabel: (item) => item,
                      hint: "Select Family Background",
                      onChanged: (value) {
                        setState(() {
                          _selectedFamilyBackground = value;
                        });
                      },
                      title: 'Family background',
                      showError: submitted,
                    ),
                  ),

                  const SizedBox(height: 25),
                  _buildDivider(),
                  const SizedBox(height: 25),

                  // Father Section
                  _buildSectionTitle("Father Status*"),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildRadioOption(
                          value: "Lives with us",
                          groupValue: _fatherStatus,
                          label: "Lives with us",
                          onChanged: (value) {
                            setState(() {
                              _fatherStatus = value;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: _buildRadioOption(
                          value: "Passed Away",
                          groupValue: _fatherStatus,
                          label: "Passed Away",
                          onChanged: (value) {
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
                    _buildSectionTitle("Father Name*"),
                    const SizedBox(height: 8),
                    _buildTextField(
                      _fatherNameController,
                      "Enter father's name",
                    ),

                    const SizedBox(height: 15),

                    _buildSectionTitle("Education*"),
                    const SizedBox(height: 8),
                    Container(
                      child: TypingDropdown<String>(
                        key: ValueKey('fathereducation_$_fatherEducation'),
                        items: _educationOptions,
                        selectedItem: _fatherEducation,
                        itemLabel: (item) => item,
                        hint: "Select Education",
                        onChanged: (value) {
                          setState(() {
                            _fatherEducation = value;
                          });
                        },
                        title: 'Education',
                        showError: submitted,
                      ),
                    ),

                    const SizedBox(height: 15),

                    _buildSectionTitle("Occupation*"),
                    const SizedBox(height: 8),
                    Container(
                      child: TypingDropdown<String>(
                        key: ValueKey('fatheroccupation_$_fatherOccupation'),
                        items: _occupationOptions,
                        selectedItem: _fatherOccupation,
                        itemLabel: (item) => item,
                        hint: "Select Occupation",
                        onChanged: (value) {
                          setState(() {
                            _fatherOccupation = value;
                          });
                        },
                        title: 'Occupation',
                        showError: submitted,
                      ),
                    ),
                  ],

                  const SizedBox(height: 25),
                  _buildDivider(),
                  const SizedBox(height: 25),

                  // Mother Section
                  _buildSectionTitle("Mother Status*"),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildRadioOption(
                          value: "Lives with us",
                          groupValue: _motherStatus,
                          label: "Lives with us",
                          onChanged: (value) {
                            setState(() {
                              _motherStatus = value;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: _buildRadioOption(
                          value: "Passed Away",
                          groupValue: _motherStatus,
                          label: "Passed Away",
                          onChanged: (value) {
                            setState(() {
                              _motherStatus = value;
                            });
                          },
                        ),
                      ),
                    ],
                  ),

                  if (_motherStatus == "Lives with us") ...[
                    const SizedBox(height: 20),
                    _buildSectionTitle("Mother Cast*"),
                    const SizedBox(height: 8),
                    Container(
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
                        controller: _motherCastController,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: "Enter mother's cast",
                          hintStyle: TextStyle(fontSize: 16, color: Colors.black54),
                        ),
                      ),
                    ),

                    const SizedBox(height: 15),

                    _buildSectionTitle("Education*"),
                    const SizedBox(height: 8),
                    Container(
                      child: TypingDropdown<String>(
                        key: ValueKey('mothereducation_$_motherEducation'),
                        items: _educationOptions,
                        selectedItem: _motherEducation,
                        itemLabel: (item) => item,
                        hint: "Select Education",
                        onChanged: (value) {
                          setState(() {
                            _motherEducation = value;
                          });
                        },
                        title: 'Education',
                        showError: submitted,
                      ),
                    ),

                    const SizedBox(height: 15),

                    _buildSectionTitle("Occupation*"),
                    const SizedBox(height: 8),
                    Container(
                      child: TypingDropdown<String>(
                        key: ValueKey('motheroccupation_$_motherOccupation'),
                        items: _occupationOptions,
                        selectedItem: _motherOccupation,
                        itemLabel: (item) => item,
                        hint: "Select Occupation",
                        onChanged: (value) {
                          setState(() {
                            _motherOccupation = value;
                          });
                        },
                        title: 'Occupation',
                        showError: submitted,
                      ),
                    ),
                  ],

                  const SizedBox(height: 25),
                  _buildDivider(),
                  const SizedBox(height: 25),

                  // Other Family Members Section
                  _buildSectionTitle("Do You've Any Other Family Member?"),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildRadioOption(
                          value: "Yes",
                          groupValue: _hasOtherFamilyMembers,
                          label: "Yes",
                          onChanged: (value) {
                            setState(() {
                              _hasOtherFamilyMembers = value;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: _buildRadioOption(
                          value: "NO",
                          groupValue: _hasOtherFamilyMembers,
                          label: "No",
                          onChanged: (value) {
                            setState(() {
                              _hasOtherFamilyMembers = value;
                              if (value == "NO") {
                                _familyMembers.clear();
                              }
                            });
                          },
                        ),
                      ),
                    ],
                  ),

                  if (_hasOtherFamilyMembers == 'Yes') ...[
                    const SizedBox(height: 25),

                    // Add Family Member Form
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: const Color(0xFF48A54C),
                          width: 1.2,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionTitle("Member Type"),
                          const SizedBox(height: 8),
                          _buildDropdown(
                            value: _selectedMemberType,
                            hint: "Select Your Family Member",
                            items: _memberTypeOptions,
                            onChanged: (value) {
                              setState(() {
                                _selectedMemberType = value;
                              });
                            },
                          ),

                          const SizedBox(height: 15),

                          _buildSectionTitle("Marital Status"),
                          const SizedBox(height: 8),
                          _buildDropdown(
                            value: _selectedMemberMaritalStatus,
                            hint: "Marital Status",
                            items: _maritalStatusOptions,
                            onChanged: (value) {
                              setState(() {
                                _selectedMemberMaritalStatus = value;
                              });
                            },
                          ),

                          const SizedBox(height: 15),

                          _buildSectionTitle("Lives With Us?"),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _buildRadioOption(
                                  value: "Yes",
                                  groupValue: _memberLivesWithUs,
                                  label: "Yes",
                                  onChanged: (value) {
                                    setState(() {
                                      _memberLivesWithUs = value;
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 15),
                              Expanded(
                                child: _buildRadioOption(
                                  value: "NO",
                                  groupValue: _memberLivesWithUs,
                                  label: "No",
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

                          // Add Member Button
                          Container(
                            height: 45,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFFE64B37),
                                  Color(0xFFE62255),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(25),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(25),
                                onTap: _addFamilyMember,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(Icons.add, color: Colors.white, size: 20),
                                    SizedBox(width: 8),
                                    Text(
                                      "Add more family member",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // List of Added Family Members
                    if (_familyMembers.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _buildSectionTitle("Added Family Members"),
                      const SizedBox(height: 8),
                      ..._familyMembers.asMap().entries.map((entry) {
                        int index = entry.key;
                        FamilyMember member = entry.value;
                        return _buildFamilyMemberCard(member, index);
                      }).toList(),
                    ],
                  ],

                  const SizedBox(height: 25),
                  _buildDivider(),
                  const SizedBox(height: 25),

                  // Family Origin
                  _buildSectionTitle("Family Origin*"),
                  const SizedBox(height: 8),
                  Container(
                    child: TypingDropdown<String>(
                      key: ValueKey('familyorigin_$_selectedFamilyOrigin'),
                      items: _familyOriginOptions,
                      selectedItem: _selectedFamilyOrigin,
                      itemLabel: (item) => item,
                      hint: "Your Family Origin",
                      onChanged: (value) {
                        setState(() {
                          _selectedFamilyOrigin = value;
                        });
                      },
                      title: 'Family origin',
                      showError: submitted,
                    ),
                  ),

                  const SizedBox(height: 35),

                  // Buttons
                  Row(
                    children: [

                      const SizedBox(width: 15),

                      const SizedBox(width: 15),
                      Expanded(
                        child: _buildButton(
                          text: "Continue",
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
              child: _progressBubble(0.25, "60%"),
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

  void _addFamilyMember() {
    if (_selectedMemberType == null) {
      _showError("Please select member type");
      return;
    }

    if (_selectedMemberMaritalStatus == null) {
      _showError("Please select marital status");
      return;
    }

    if (_memberLivesWithUs == null || _memberLivesWithUs!.isEmpty) {
      _showError("Please select if member lives with you");
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
    });

    _showSuccess("Family member added successfully!");
  }

  void _removeFamilyMember(int index) {
    setState(() {
      _familyMembers.removeAt(index);
      if (_familyMembers.isEmpty) {
        _hasOtherFamilyMembers = 'NO';
      }
    });
    _showSuccess("Family member removed!");
  }

  Widget _buildFamilyMemberCard(FamilyMember member, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFF48A54C),
          width: 1,
        ),
        color: const Color(0xFFE64B37).withOpacity(0.05),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.type,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Marital Status: ${member.maritalStatus}",
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black54,
                  ),
                ),
                Text(
                  "Lives with us: ${member.livesWithUs}",
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Color(0xFFE64B37)),
            onPressed: () => _removeFamilyMember(index),
          ),
        ],
      ),
    );
  }

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
    required String value,
    required String? groupValue,
    required String label,
    required Function(String) onChanged,
  }) {
    bool isSelected = groupValue == value;

    return Container(
      height: 50,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFF48A54C),
          width: 1.2,
        ),
        color: isSelected ? const Color(0xFFE64B37).withOpacity(0.1) : Colors.transparent,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
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

    // Basic validation
    if (_selectedFamilyType == null) {
      _showError("Please select family type");
      return;
    }
    if (_selectedFamilyBackground == null) {
      _showError("Please select family background");
      return;
    }
    if (_fatherStatus == null) {
      _showError("Please select father status");
      return;
    }
    if (_motherStatus == null) {
      _showError("Please select mother status");
      return;
    }
    if (_selectedFamilyOrigin == null) {
      _showError("Please select family origin");
      return;
    }

    // Validate father details if living
    if (_fatherStatus == "Lives with us") {
      if (_fatherNameController.text.trim().isEmpty) {
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

    // Validate mother details if living
    if (_motherStatus == "Lives with us") {
      if (_motherCastController.text.trim().isEmpty) {
        _showError("Please enter mother's cast");
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

    _submitFamilyData();
  }

  void _submitFamilyData() async {
    _showLoading("Submitting data...");

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
        "fathername": _fatherStatus == "Lives with us" ? (_fatherNameController.text.trim()) : "",
        "fathereducation": _fatherStatus == "Lives with us" ? (_fatherEducation ?? "") : "",
        "fatheroccupation": _fatherStatus == "Lives with us" ? (_fatherOccupation ?? "") : "",
        "motherstatus": _motherStatus ?? "",
        "mothercaste": _motherStatus == "Lives with us" ? (_motherCastController.text.trim()) : "",
        "mothereducation": _motherStatus == "Lives with us" ? (_motherEducation ?? "") : "",
        "motheroccupation": _motherStatus == "Lives with us" ? (_motherOccupation ?? "") : "",
        "familyorigin": _selectedFamilyOrigin ?? "",
        "members": jsonEncode(members),
      };

      // Print request for debugging (remove in production)
      print("Sending request: $requestBody");

      var response = await http.post(
        Uri.parse("${kApiBaseUrl}/Api2/updatefamily.php"),
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
          // Update page number


          if (data['status'] == 'success') {
            _showSuccess("Family details saved successfully!");
            // Navigate after a short delay
            Future.delayed(const Duration(seconds: 1), () {
Navigator.pop(context) ;
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
    } finally {
      // Hide loading
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }
  }

  void _showLoading(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 15),
            Text(message),
          ],
        ),
        duration: const Duration(minutes: 1),
        backgroundColor: Colors.blue,
      ),
    );
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
        duration: const Duration(seconds: 2),
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
    _fatherNameController.dispose();
    _motherCastController.dispose();
    super.dispose();
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
