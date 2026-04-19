import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ms2026/Auth/Screen/signupscreen4.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../ReUsable/dropdownwidget.dart';
import 'package:ms2026/config/app_endpoints.dart';


class CommunityDetailsPageEdit extends StatefulWidget {
  const CommunityDetailsPageEdit({super.key, this.initialData});

  final Map<String, dynamic>? initialData;

  @override
  State<CommunityDetailsPageEdit> createState() => _CommunityDetailsPageEditState();
}

class _CommunityDetailsPageEditState extends State<CommunityDetailsPageEdit> {
  // Form variables
  bool submitted = false;

  String? _selectedReligion;
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

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null && widget.initialData!.isNotEmpty) {
      _populateFromInitialData(widget.initialData!);
    }
  }

  void _populateFromInitialData(Map<String, dynamic> data) {
    final religionName = data['religionName']?.toString();
    final communityName = data['communityName']?.toString();
    final subCommunityName = data['subCommunityName']?.toString();
    final motherTongue = data['motherTongue']?.toString();

    if (religionName != null && religionName.isNotEmpty) {
      _selectedReligion = _matchOption(_religionOptions, religionName);
    }
    if (communityName != null && communityName.isNotEmpty) {
      _selectedCommunity = _matchOption(_communityOptions, communityName);
    }
    if (subCommunityName != null && subCommunityName.isNotEmpty) {
      _selectedSubcommunity = _matchOption(_subcommunityOptions, subCommunityName);
    }
    if (motherTongue != null && motherTongue.isNotEmpty) {
      _selectedCastLanguage = _matchOption(_castLanguageOptions, motherTongue);
    }
  }

  String? _matchOption(List<String> options, String value) {
    try {
      return options.firstWhere(
        (o) => o.toLowerCase() == value.toLowerCase(),
      );
    } catch (_) {
      return null;
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
        title: const Text('Community Details', style: TextStyle(color: Colors.white)),
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
                      "Community Details",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFE64B37),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),

                  // Religion
                  _buildSectionTitle("Religious*"),
                  const SizedBox(height: 8),
                  TypingDropdown<String>(
                    items: _religionOptions,
                    selectedItem: _selectedReligion,
                    itemLabel: (item) => item,
                    hint: "Select Religion",
                    onChanged: (value) {
                      setState(() {
                        _selectedReligion = value!;
                      });
                    }, title: 'Religion', showError: submitted,
                  ),
                  const SizedBox(height: 20),

                  // Community
                  _buildSectionTitle("Community*"),
                  const SizedBox(height: 8),
                  TypingDropdown<String>(
                    items: _communityOptions,
                    selectedItem: _selectedCommunity,
                    itemLabel: (item) => item,
                    hint: "Select Community",
                    onChanged: (value) {
                      setState(() {
                        _selectedCommunity = value;
                        if (_selectedSubcommunity != null &&
                            !_subcommunityOptions.contains(_selectedSubcommunity)) {
                          _selectedSubcommunity = null;
                        }
                      });
                    }, title: 'Community', showError: submitted,
                  ),
                  const SizedBox(height: 20),

                  // Subcommunity
                  _buildSectionTitle("Subcommunity*"),
                  const SizedBox(height: 8),
                  TypingDropdown<String>(
                    items: _subcommunityOptions,
                    selectedItem: _selectedSubcommunity,
                    itemLabel: (item) => item,
                    hint: "Select Subcommunity",
                    onChanged: (value) {
                      setState(() {
                        _selectedSubcommunity = value;
                      });
                    }, title: ' Subcommunity', showError: submitted,
                  ),
                  const SizedBox(height: 20),

                  // Cast Language
                  _buildSectionTitle("Cast Language*"),
                  const SizedBox(height: 8),
                  TypingDropdown<String>(
                    items: _castLanguageOptions,
                    selectedItem: _selectedCastLanguage,
                    itemLabel: (item) => item,
                    hint: "Select Cast Language",
                    onChanged: (value) {
                      setState(() {
                        _selectedCastLanguage = value;
                      });
                    }, title: 'Cast Language', showError: submitted,
                  ),
                  const SizedBox(height: 25),

                  // Buttons
                  Row(
                    children: [

                      const SizedBox(width: 15),
                      Expanded(
                        child: _buildButton(
                          text: _isLoading ? "Saving..." : "Save",
                          isPrimary: true,
                          onPressed: _isLoading ? null : _validateAndSubmit,
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
              child: _progressBubble(0.15, "25%"),
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

  Widget _buildButton({
    required String text,
    required bool isPrimary,
    required VoidCallback? onPressed,
  }) {
    return Container(
      height: 55,
      decoration: BoxDecoration(
        gradient: isPrimary
            ? const LinearGradient(
          colors: [Color(0xFFE64B37), Color(0xFFE62255)],
        )
            : const LinearGradient(
          colors: [Color(0xFFEEA2A4), Color(0xFFF3C0C4)],
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

  // ------------------ Validation & Submit ------------------
  void _validateAndSubmit() async {
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
      _showError("Please select cast language");
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

  Navigator.pop(context);
    } else {
      _showError(result['message'] ?? "Failed to save details");
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
