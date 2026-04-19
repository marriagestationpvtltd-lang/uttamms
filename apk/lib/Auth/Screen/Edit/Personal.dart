import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:ms2026/Auth/Screen/signupscreen3.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../ReUsable/dropdownwidget.dart';
import '../../../service/personal_details_api.dart';
import '../../../service/updatepage.dart';
import 'package:ms2026/config/app_endpoints.dart';


class PersonalDetailsPageEdit extends StatefulWidget {
  const PersonalDetailsPageEdit({super.key});

  @override
  State<PersonalDetailsPageEdit> createState() => _PersonalDetailsPageEditState();
}

class _PersonalDetailsPageEditState extends State<PersonalDetailsPageEdit> {
  bool submitted = false;

  // Form variables
  String? _selectedMaritalStatus;
  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  bool _hasSpecs = false;
  bool _hasDisability = false;
  String _ChildStatus = '';
  String _Childlivewith= '';
  final TextEditingController _disabilityController = TextEditingController();
  String? _selectedBloodGroup;
  String? _selectedComplexion;
  String? _selectedBodyType;
  final TextEditingController _aboutYourselfController = TextEditingController();

  // Dropdown options
  final List<String> _maritalStatusOptions = [
    'Still Unmarried',
    'Widowed',
    'Divorced',
    'Waiting Divorce',
  ];

  final List<String> _bloodGroupOptions = [
    'A+',
    'A-',
    'B+',
    'B-',
    'AB+',
    'AB-',
    'O+',
    'O-'
  ];

  final List<String> _complexionOptions = [
    'Very Fair',
    'Fair',
    'Wheatish',
    'Olive',
    'Brown',
    'Dark'
  ];

  final List<String> _bodyTypeOptions = [
    'Slim',
    'Athletic',
    'Average',
    'Heavy',
    'Muscular'
  ];

  String _SelectedHeight = '';

  final List<String> _heightOptions = List.generate(121, (index) {
    int cm = 100 + index;
    double totalInches = cm / 2.54;
    int feet = totalInches ~/ 12;
    int inches = (totalInches % 12).round();
    return "$cm cm ($feet' $inches\").ft";
  });


  String _selectedWeight = '';

  final List<String> _weightOptions = List.generate(121, (index) {
    int kg = 30 + index; // 30 kg to 150 kg
    return "$kg kg";
  });


  // String _selectedBloodGroup = '';

  final List<String> _bloodGroups = [
    "A+",
    "A-",
    "B+",
    "B-",
    "AB+",
    "AB-",
    "O+",
    "O-",
  ];





  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Personal Details', style: TextStyle(color: Colors.white)),
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
                      "Personal Details",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFE64B37),
                      ),
                    ),
                  ),

                  const SizedBox(height: 25),

                  // Marital Status
                  _buildSectionTitle("Marital Status*"),

                  Container(

                    child: TypingDropdown<String>(
                      items:  _maritalStatusOptions,
                      selectedItem:  _selectedMaritalStatus,
                      itemLabel: (item) => item,
                      hint: "Select Marital",
                      onChanged: (value) {
                        setState(() {
                          _selectedMaritalStatus = value!;
                        });
                      }, title: 'Marital Status', showError: submitted,
                    ),
                  ),





                  const SizedBox(height: 10),
                  if (_selectedMaritalStatus == 'Divorced' || _selectedMaritalStatus == 'Widowed' || _selectedMaritalStatus == 'Waiting Divorce') ...[
                    //   _buildSectionTitle("Children Status?"),
                    const SizedBox(height: 8),
                    _buildSectionTitle("Children Status"),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildRadioOptionn(
                            value: "No Child",
                            groupValue:_ChildStatus,
                            label: "No Child",
                            onChanged: (value) {
                              setState(() {
                                _ChildStatus = value! ;
                              });
                            },
                          ),
                        ),
                        SizedBox(width: 15,),
                        Expanded(
                          child: _buildRadioOptionn(
                            value: 'One',
                            groupValue: _ChildStatus,
                            label: "One",
                            onChanged: (value) {
                              setState(() {
                                _ChildStatus = value!;
                              });
                            },
                          ),
                        ),
                        SizedBox(width: 15,),
                        Expanded(
                          child: _buildRadioOptionn(
                            value: 'Two +',
                            groupValue: _ChildStatus,
                            label: "Two +",
                            onChanged: (value) {
                              setState(() {
                                _ChildStatus = value!;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 25),
                  ],

                  if (_ChildStatus == 'One' || _ChildStatus == 'Two +') ...[
                    //   _buildSectionTitle("Children Status?"),

                    _buildSectionTitle("Child live with?"),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildRadioOptionn(
                            value: "With Me",
                            groupValue:_Childlivewith,
                            label: "With Me",
                            onChanged: (value) {
                              setState(() {
                                _Childlivewith = value! ;
                              });
                            },
                          ),
                        ),
                        SizedBox(width: 15,),
                        Expanded(
                          child: _buildRadioOptionn(
                            value: 'With Ex Husband',
                            groupValue: _Childlivewith,
                            label: "With Ex Husband",
                            onChanged: (value) {
                              setState(() {
                                _Childlivewith = value!;
                              });
                            },
                          ),
                        ),

                      ],
                    ),
                    const SizedBox(height: 10),
                  ],

                  if (_ChildStatus == 'One' || _ChildStatus == 'Two +') ...[
                    Row(

                      children: [
                        Expanded(
                          child: _buildRadioOptionn(
                            value: 'Others',
                            groupValue: _Childlivewith,
                            label: "Others",
                            onChanged: (value) {
                              setState(() {
                                _Childlivewith = value!;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Height and Weight Row
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionTitle("Height (In Cm)*"),

                            Container(

                              child: TypingDropdown<String>(
                                items:  _heightOptions,
                                selectedItem:  _SelectedHeight,
                                itemLabel: (item) => item,
                                hint: "Select height",
                                onChanged: (value) {
                                  setState(() {
                                    _SelectedHeight = value!;
                                  });
                                }, title: 'height', showError: submitted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionTitle("Weight (In Kg)*"),
                            Container(

                              child: TypingDropdown<String>(
                                items:  _weightOptions,
                                selectedItem:  _selectedWeight,
                                itemLabel: (item) => item,
                                hint: "Select weight",
                                onChanged: (value) {
                                  setState(() {
                                    _selectedWeight = value!;
                                  });
                                }, title: 'weight', showError: submitted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 25),

                  // Specs/Lenses Section
                  _buildSectionTitle("Specs/Lenses"),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildRadioOption(
                          value: true,
                          groupValue: _hasSpecs,
                          label: "Yes",
                          onChanged: (value) {
                            setState(() {
                              _hasSpecs = value ?? false;
                            });
                          },
                        ),
                      ),
                      SizedBox(width: 15,),
                      Expanded(
                        child: _buildRadioOption(
                          value: false,
                          groupValue: _hasSpecs,
                          label: "No",
                          onChanged: (value) {
                            setState(() {
                              _hasSpecs = value ?? false;
                            });
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 25),
                  _buildDivider(),

                  // Any Disability Section
                  _buildSectionTitle("Any Disability"),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildRadioOption(
                          value: true,
                          groupValue: _hasDisability,
                          label: "Yes",
                          onChanged: (value) {
                            setState(() {
                              _hasDisability = value ?? false;
                            });
                          },
                        ),
                      ),
                      SizedBox(width: 15,),
                      Expanded(
                        child: _buildRadioOption(
                          value: false,
                          groupValue: _hasDisability,
                          label: "No",
                          onChanged: (value) {
                            setState(() {
                              _hasDisability = value ?? false;
                            });
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 25),

                  // Disability Description (only show if disability is yes)
                  if (_hasDisability) ...[
                    _buildSectionTitle("What Disability You've?"),
                    const SizedBox(height: 8),
                    _buildTextField(
                      _disabilityController,
                      "Describe your disability",
                      maxLines: 3,
                    ),
                    const SizedBox(height: 25),
                  ],

                  _buildDivider(),

                  const SizedBox(height: 25),

                  // Blood Group
                  _buildSectionTitle("Blood Group*"),


                  Container(

                    child: TypingDropdown<String>(
                      items:  _bloodGroupOptions,
                      selectedItem:   _selectedBloodGroup,
                      itemLabel: (item) => item,
                      hint: "Select blood group",
                      onChanged: (value) {
                        setState(() {
                          _selectedBloodGroup = value!;
                        });
                      }, title: 'Blood group', showError: submitted,
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Complexion
                  _buildSectionTitle("Complexion*"),


                  Container(

                    child: TypingDropdown<String>(
                      items:  _complexionOptions,
                      selectedItem:   _selectedComplexion,
                      itemLabel: (item) => item,
                      hint: "Select Complexion",
                      onChanged: (value) {
                        setState(() {
                          _selectedComplexion = value!;
                        });
                      }, title: 'Complexion', showError: submitted,
                    ),
                  ),



                  const SizedBox(height: 20),

                  // Body Type
                  _buildSectionTitle("Body Type*"),


                  Container(

                    child: TypingDropdown<String>(
                      items: _bodyTypeOptions,
                      selectedItem:  _selectedBodyType,
                      itemLabel: (item) => item,
                      hint: "Select Complexion",
                      onChanged: (value) {
                        setState(() {
                          _selectedBodyType = value!;
                        });
                      }, title: 'Complexion', showError: submitted,
                    ),
                  ),


                  const SizedBox(height: 20),

                  // About Yourself
                  _buildSectionTitle("About Yourself"),
                  const SizedBox(height: 8),
                  Container(
                    height: 120,
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                        color: const Color(0xFF48A54C),
                        width: 1.6,
                      ),
                    ),
                    child: TextField(
                      controller: _aboutYourselfController,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: "Tell us about yourself...",
                        hintStyle: TextStyle(fontSize: 16),
                      ),
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                    ),
                  ),

                  const SizedBox(height: 35),

                  // Buttons
                  Row(
                    children: [

                      Expanded(
                        child: _buildButton(
                          text: "Save",
                          isPrimary: true,
                          onPressed: () {
                            // Handle continue button press
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
              child: _progressBubble(0.10, "10%"),
            ),
          ],
        ),
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

  Widget _buildTextField(TextEditingController controller, String hintText, {int maxLines = 1}) {
    return Container(
      height: maxLines == 1 ? 55 : null,
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
        maxLines: maxLines,
        // keyboardType: TextInputType.number,
      ),
    );
  }



  Widget _buildRadioOption({
    required bool value,
    required bool? groupValue,
    required String label,
    required Function(bool?) onChanged,
  }) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFF48A54C),
          width: 1.2,
        ),
      ),
      child: RadioListTile<bool>(
        value: value,
        groupValue: groupValue,
        onChanged: onChanged,
        title: Text(
          label,
          style: const TextStyle(fontSize: 16),
        ),
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        activeColor: const Color(0xFFE64B37),
      ),
    );
  }


  Widget _buildRadioOptionn({
    required String value,
    required String groupValue,
    required String label,
    required Function(String?) onChanged,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => onChanged(value),   // FULL CONTAINER CLICK
      child: Container(
        height: 50,
        width: 200,
        padding: EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0xFF48A54C),
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            Radio<String>(
              value: value,
              groupValue: groupValue,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: onChanged,     // radio click
              activeColor: const Color(0xFFE64B37),
            ),

            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
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
            decoration: BoxDecoration(
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
    // Basic validation
    if (_selectedMaritalStatus == null) {
      _showError("Please select marital status");
      return;
    }

    if (_SelectedHeight.isEmpty) {
      _showError("Please enter height");
      return;
    }

    if (_selectedWeight.isEmpty) {
      _showError("Please enter weight");
      return;
    }

    if (_selectedBloodGroup == null) {
      _showError("Please select blood group");
      return;
    }

    if (_selectedComplexion == null) {
      _showError("Please select complexion");
      return;
    }

    if (_selectedBodyType == null) {
      _showError("Please select body type");
      return;
    }

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      final prefs = await SharedPreferences.getInstance();

      final userDataString = prefs.getString('user_data');
      final userData = jsonDecode(userDataString!);
      final userId = int.tryParse(userData["id"].toString());
      // Call the reusable service
      final service = UserPersonalDetailService(
        baseUrl: '${kApiBaseUrl}/Api2/save_personal_detail.php',
      );

      final result = await service.saveUserPersonalDetail(
        userId: userId!, // replace with actual logged-in user id
        maritalStatusId: _maritalStatusOptions.indexOf(_selectedMaritalStatus!) + 1,
        heightName: _SelectedHeight,
        weightName: _selectedWeight,
        haveSpecs: _hasSpecs ? 1 : 0,
        anyDisability: _hasDisability ? 1 : 0,
        disability: _disabilityController.text.isNotEmpty ? _disabilityController.text : null,
        bloodGroup: _selectedBloodGroup,
        complexion: _selectedComplexion,
        bodyType: _selectedBodyType,
        aboutMe: _aboutYourselfController.text.isNotEmpty ? _aboutYourselfController.text : null,
        childStatus: _ChildStatus.isNotEmpty ? _ChildStatus : null,
        childLiveWith: _Childlivewith.isNotEmpty ? _Childlivewith : null,
      );

      Navigator.of(context).pop(); // close loading dialog

      if (result['status'] == 'success') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
        // Navigate to next page
     Navigator.pop(context);
      } else {
        _showError(result['message'] ?? "Something went wrong");
      }
    } catch (e) {
      Navigator.of(context).pop(); // close loading dialog
      _showError(e.toString());
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

  @override
  void dispose() {
    _heightController.dispose();
    _weightController.dispose();
    _disabilityController.dispose();
    _aboutYourselfController.dispose();
    super.dispose();
  }
}