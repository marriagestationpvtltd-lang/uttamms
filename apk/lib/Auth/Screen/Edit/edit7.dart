import 'package:flutter/material.dart';
import 'package:ms2026/Auth/Screen/signupscreen9.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../ReUsable/dropdownwidget.dart';
import 'package:ms2026/config/app_endpoints.dart';

class LifestylePagee extends StatefulWidget {
  const LifestylePagee({
    super.key,
    this.initialData,
  });

  final Map<String, dynamic>? initialData;

  @override
  State<LifestylePagee> createState() => _LifestylePageeState();
}

class _LifestylePageeState extends State<LifestylePagee> {
  bool submitted = false;
  bool isLoading = false;
  bool isDataLoaded = false;

  // Form variables
  String? _selectedDiet;
  String? _selectedDrink;
  String? _selectedDrinkType;
  String? _selectedSmoke;
  String? _selectedSmokeType;

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
    'Occasionally',
    'Socially'
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

  // Keys to force dropdown rebuild
  final GlobalKey _dietKey = GlobalKey();
  final GlobalKey _drinkKey = GlobalKey();
  final GlobalKey _drinkTypeKey = GlobalKey();
  final GlobalKey _smokeKey = GlobalKey();
  final GlobalKey _smokeTypeKey = GlobalKey();

  // Counter to force rebuild
  int _rebuildCounter = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialData != null && widget.initialData!.isNotEmpty) {
        _applyLifestyleData(widget.initialData!);
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

      print("Loading lifestyle data for user ID: $userId");

      // Call GET API
      var url = Uri.parse("${kApiBaseUrl}/Api2/get_lifestyle.php?userid=$userId");
      var response = await http.get(url);

      print("API Response Status: ${response.statusCode}");
      print("API Response Body: ${response.body}");

      if (response.statusCode == 200) {
        var data = json.decode(response.body);

        if (data['status'] == 'success' && data['data'] != null) {
          final savedData = data['data'];
          print("Loaded Lifestyle Data: $savedData");

          // Create new instances to force change detection
          String? newDiet = _getValidValue(savedData['diet']);
          String? newDrink = _getValidValue(savedData['drinks']);
          String? newDrinkType = _getValidValue(savedData['drinktype']);
          String? newSmoke = _getValidValue(savedData['smoke']);
          String? newSmokeType = _getValidValue(savedData['smoketype']);

          // Check if values actually changed
          bool valuesChanged =
              newDiet != _selectedDiet ||
                  newDrink != _selectedDrink ||
                  newDrinkType != _selectedDrinkType ||
                  newSmoke != _selectedSmoke ||
                  newSmokeType != _selectedSmokeType;

          if (valuesChanged) {
            _applyLifestyleData(savedData);

            print("Values updated and widgets will rebuild");
          } else {
            setState(() {
              isDataLoaded = true;
            });
          }

          print("Lifestyle data loaded successfully!");
          print("Diet: $_selectedDiet");
          print("Drink: $_selectedDrink");
          print("Drink Type: $_selectedDrinkType");
          print("Smoke: $_selectedSmoke");
          print("Smoke Type: $_selectedSmokeType");

          _showSuccess("Lifestyle data loaded successfully");
        } else {
          // No data found for this user
          print("No saved lifestyle data found");
          setState(() {
            _selectedDiet = null;
            _selectedDrink = null;
            _selectedDrinkType = null;
            _selectedSmoke = null;
            _selectedSmokeType = null;
            _rebuildCounter++;
            isDataLoaded = true;
          });
          _showInfo("No saved lifestyle data found. Please fill the form.");
        }
      } else {
        print("Failed to load lifestyle data: ${response.statusCode}");
        _showError("Failed to load lifestyle data: ${response.statusCode}");
      }
    } catch (e) {
      print("Error loading lifestyle data: $e");
      _showError("Error loading lifestyle data: $e");
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  // Helper method to get valid value
  String? _getValidValue(dynamic value) {
    if (value == null ||
        value.toString().trim().isEmpty ||
        value.toString().toLowerCase() == 'null' ||
        value.toString().toLowerCase() == 'na') {
      return null;
    }
    return value.toString();
  }

  void _applyLifestyleData(Map<String, dynamic> savedData) {
    setState(() {
      _selectedDiet = _getValidValue(savedData['diet']);
      _selectedDrink = _getValidValue(savedData['drinks']);
      _selectedDrinkType = _getValidValue(savedData['drinktype']);
      _selectedSmoke = _getValidValue(savedData['smoke']);
      _selectedSmokeType = _getValidValue(savedData['smoketype']);
      _rebuildCounter++;
      isDataLoaded = true;
      isLoading = false;
    });
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
        title: const Text('Lifestyle', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFFE64B37),
        elevation: 0,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              key: ValueKey('scroll_$_rebuildCounter'), // Force rebuild
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with Skip button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Skip Button
SizedBox(width: 80,),

                      // Title
                      const Text(
                        "Life Style",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFE64B37),
                        ),
                      ),

                      // Empty container for balance
                      const SizedBox(width: 80),
                    ],
                  ),

                  const SizedBox(height: 25),

                  // Your Diet
                  _buildSectionTitle("Your Diet*"),
                  const SizedBox(height: 8),
                  Container(
                    key: ValueKey('diet_${_selectedDiet}_$_rebuildCounter'),
                    child: TypingDropdown<String>(
                      items: _dietOptions,
                      selectedItem: _selectedDiet,
                      itemLabel: (item) => item,
                      hint: "Select your diet*",
                      onChanged: (value) {
                        setState(() {
                          _selectedDiet = value;
                        });
                      },
                      title: 'Diets',
                      showError: submitted,
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Drink
                  _buildSectionTitle("Drink*"),
                  const SizedBox(height: 8),
                  Container(
                    key: ValueKey('drink_${_selectedDrink}_$_rebuildCounter'),
                    child: TypingDropdown<String>(
                      items: _drinkOptions,
                      selectedItem: _selectedDrink,
                      itemLabel: (item) => item,
                      hint: "Select drink habit*",
                      onChanged: (value) {
                        setState(() {
                          _selectedDrink = value;
                          // Reset drink type if "No" is selected
                          if (value == "No") {
                            _selectedDrinkType = null;
                          }
                        });
                      },
                      title: 'Drink habit',
                      showError: submitted,
                    ),
                  ),

                  // Drink Type (only show if not "No")
                  if (_selectedDrink != null && _selectedDrink != "No") ...[
                    const SizedBox(height: 15),
                    _buildSectionTitle("Select Drink Type*"),
                    const SizedBox(height: 8),
                    Container(
                      key: ValueKey('drinktype_${_selectedDrinkType}_$_rebuildCounter'),
                      child: TypingDropdown<String>(
                        items: _drinkTypeOptions,
                        selectedItem: _selectedDrinkType,
                        itemLabel: (item) => item,
                        hint: "Select drink type*",
                        onChanged: (value) {
                          setState(() {
                            _selectedDrinkType = value;
                          });
                        },
                        title: 'Drink Type',
                        showError: submitted,
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // Smoke
                  _buildSectionTitle("Smoke*"),
                  const SizedBox(height: 8),
                  Container(
                    key: ValueKey('smoke_${_selectedSmoke}_$_rebuildCounter'),
                    child: TypingDropdown<String>(
                      items: _smokeOptions,
                      selectedItem: _selectedSmoke,
                      itemLabel: (item) => item,
                      hint: "Select smoke habit*",
                      onChanged: (value) {
                        setState(() {
                          _selectedSmoke = value;
                          // Reset smoke type if "No" is selected
                          if (value == "No") {
                            _selectedSmokeType = null;
                          }
                        });
                      },
                      title: 'Smoke habit',
                      showError: submitted,
                    ),
                  ),

                  // Smoke Type (only show if not "No")
                  if (_selectedSmoke != null && _selectedSmoke != "No") ...[
                    const SizedBox(height: 15),
                    _buildSectionTitle("Select Smoke Type*"),
                    const SizedBox(height: 8),
                    Container(
                      key: ValueKey('smoketype_${_selectedSmokeType}_$_rebuildCounter'),
                      child: TypingDropdown<String>(
                        items: _smokeTypeOptions,
                        selectedItem: _selectedSmokeType,
                        itemLabel: (item) => item,
                        hint: "Select smoke type*",
                        onChanged: (value) {
                          setState(() {
                            _selectedSmokeType = value;
                          });
                        },
                        title: 'Smoke Type',
                        showError: submitted,
                      ),
                    ),
                  ],

                  const SizedBox(height: 35),

                  // Buttons
                  Row(
                    children: [




                      Expanded(
                        child: _buildButton(
                          text: isLoading ? "Submitting..." : "Save",
                          isPrimary: true,
                          onPressed: isLoading ? null : _validateAndSubmit,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 30),
                ],
              ),
            ),

            // Progress bubble


            // Loading overlay
            if (isLoading)
              Container(
                color: Colors.black54,
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

  void _skipPage() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(
            "Skip Lifestyle Details?",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFFE64B37),
            ),
          ),
          content: const Text(
            "Are you sure you want to skip this section? You can fill it later.",
            style: TextStyle(
              fontSize: 16,
              color: Colors.black87,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text(
                "Cancel",
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        );
      },
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
    return Opacity(
      opacity: onPressed == null ? 0.6 : 1.0,
      child: Container(
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
      ),
    );
  }


  void _validateAndSubmit() async {
    submitted = true;

    // Basic validation
    if (_selectedDiet == null) {
      _showError("Please select your diet");
      return;
    }

    if (_selectedDrink == null) {
      _showError("Please select your drink habit");
      return;
    }

    // Drink type validation (only if not "No")
    if (_selectedDrink != "No" && _selectedDrinkType == null) {
      _showError("Please select drink type");
      return;
    }

    if (_selectedSmoke == null) {
      _showError("Please select your smoke habit");
      return;
    }

    // Smoke type validation (only if not "No")
    if (_selectedSmoke != "No" && _selectedSmokeType == null) {
      _showError("Please select smoke type");
      return;
    }

    setState(() {
      isLoading = true;
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
        "drinktype": _selectedDrink != "No" ? (_selectedDrinkType ?? "") : "",
        "smoke": _selectedSmoke!,
        "smoketype": _selectedSmoke != "No" ? (_selectedSmokeType ?? "") : "",
      };

      // Remove empty values to avoid sending null to API
      body.removeWhere((key, value) => value.isEmpty);

      // API URL
      String url = "${kApiBaseUrl}/Api2/user_lifestyle.php";

      print("Submitting lifestyle data: $body");

      final response = await http.post(
        Uri.parse(url),
        body: body,
      ).timeout(const Duration(seconds: 2));

      final data = json.decode(response.body);
      print("API Response: $data");

      if (data['status'] == 'success') {
        _showSuccess(data['message'] ?? "Lifestyle details saved successfully!");

        // Navigate to next page
        Future.delayed(const Duration(seconds: 1), () {
     Navigator.pop(context);
        });
      } else {
        _showError(data['message'] ?? "Submission failed. Please try again.");
      }
    } catch (e) {
      _showError("Network error: $e");
      print("Error details: $e");
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
}
