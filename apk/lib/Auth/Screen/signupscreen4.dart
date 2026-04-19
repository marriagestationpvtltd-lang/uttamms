import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart'
    if (dart.library.html) 'package:ms2026/utils/web_geocoding_stub.dart';
import 'package:ms2026/Auth/Screen/signupscreen5.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../ReUsable/dropdownwidget.dart';
import '../../ReUsable/registration_progress.dart';
import '../../ReUsable/enhanced_form_fields.dart';
import '../../constant/app_colors.dart';
import '../../service/location_service.dart';
import '../../service/updatepage.dart';
import 'package:ms2026/config/app_endpoints.dart';

class LivingStatusPage extends StatefulWidget {
  const LivingStatusPage({super.key});

  @override
  State<LivingStatusPage> createState() => _LivingStatusPageState();
}

class _LivingStatusPageState extends State<LivingStatusPage> {
  bool submitted = false;

  // Form variables
  String? _selectedPermanentCountry;
  String? _selectedPermanentState;
  String? _selectedPermanentCity;
  final TextEditingController _permanentToleController = TextEditingController();

  String? _selectedResidentialStatus;
  bool _sameAsPermanent = false;

  String? _selectedTemporaryCountry;
  String? _selectedTemporaryState;
  String? _selectedTemporaryCity;
  final TextEditingController _temporaryToleController = TextEditingController();

  String? _selectedResidentialStatus2;
  bool? _willingToGoAbroad;
  String? _selectedVisaStatus;

  bool _isGettingLocation = false;
  bool _isLoading = false;

  // Field errors
  Map<String, String?> _fieldErrors = {};

  // Sample data for dropdowns
  List<String> _countryOptions = [];
  Map<String, int> _countryMap = {};

  List<String> _stateOptions = [];
  Map<String, int> _stateMap = {};

  List<String> _cityOptions = [];
  Map<String, int> _cityMap = {};

  final List<String> _residentialStatusOptions = [
    'Own House',
    'Rented',
    'With Family',
    'Hostel',
    'Other'
  ];

  final List<String> _visaStatusOptions = [
    'No Visa',
    'Tourist Visa',
    'Student Visa',
    'Work Visa',
    'Permanent Residence',
    'Citizenship'
  ];

  @override
  void initState() {
    super.initState();
    loadCountries();
  }

  Future<void> loadCountries() async {
    final data = await LocationService.fetchCountries();

    _countryOptions.clear();
    _countryMap.clear();

    for (var item in data) {
      final name = item['name'];
      final id = int.parse(item['id'].toString());

      _countryOptions.add(name);
      _countryMap[name] = id;
    }

    // Set Nepal as default country
    if (_countryOptions.contains('Nepal') && _selectedTemporaryCountry == null) {
      _selectedTemporaryCountry = 'Nepal';
      _selectedPermanentCountry = 'Nepal';
      final nepalId = _countryMap['Nepal']!;
      loadStates(nepalId);
    }

    setState(() {});
  }

  Future<void> loadStates(int countryId) async {
    final data = await LocationService.fetchStates(countryId);

    _stateOptions.clear();
    _stateMap.clear();

    for (var item in data) {
      final name = item['name'];
      final id = int.parse(item['id'].toString());

      _stateOptions.add(name);
      _stateMap[name] = id;
    }

    setState(() {});
  }

  Future<void> loadCities(int stateId) async {
    print("Loading cities for stateId: $stateId");

    final data = await LocationService.fetchCities(stateId);

    final List<String> newCityOptions = [];
    final Map<String, int> newCityMap = {};

    for (var item in data) {
      final name = item['name'];
      final id = int.parse(item['id'].toString());

      newCityOptions.add(name);
      newCityMap[name] = id;
    }

    setState(() {
      _cityOptions = newCityOptions;
      _cityMap = newCityMap;
    });

    print("Cities loaded: ${_cityOptions.length}");
  }

  // Function to get current location
  Future<void> _getCurrentLocation(TextEditingController controller) async {
    setState(() {
      _isGettingLocation = true;
    });

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showError('Location permissions are denied');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showError('Location permissions are permanently denied');
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark placemark = placemarks.first;

        String address = '';
        if (placemark.street != null && placemark.street!.isNotEmpty) {
          address = placemark.street!;
        } else if (placemark.name != null && placemark.name!.isNotEmpty) {
          address = placemark.name!;
        }

        if (placemark.locality != null && placemark.locality!.isNotEmpty) {
          address += address.isNotEmpty ? ', ${placemark.locality}' : placemark.locality!;
        }

        if (placemark.subAdministrativeArea != null &&
            placemark.subAdministrativeArea!.isNotEmpty) {
          address += address.isNotEmpty
              ? ', ${placemark.subAdministrativeArea}'
              : placemark.subAdministrativeArea!;
        }

        controller.text = address;

        if (placemark.country != null) {
          if (_countryOptions.contains(placemark.country)) {
            setState(() {
              _selectedTemporaryCountry = placemark.country;
            });
          }
        }

        if (placemark.administrativeArea != null) {
          String state = placemark.administrativeArea!;
          for (String option in _stateOptions) {
            if (state.toLowerCase().contains(option.toLowerCase()) ||
                option.toLowerCase().contains(state.toLowerCase())) {
              setState(() {
                _selectedTemporaryState = option;
              });
              break;
            }
          }
        }

        if (placemark.locality != null) {
          String city = placemark.locality!;
          for (String option in _cityOptions) {
            if (city.toLowerCase().contains(option.toLowerCase()) ||
                option.toLowerCase().contains(city.toLowerCase())) {
              setState(() {
                _selectedTemporaryCity = option;
              });
              break;
            }
          }
        }

        _showSuccess('Location detected successfully!');
      }
    } catch (e) {
      print('Error getting location: $e');
      _showError('Failed to get location. Please check your GPS and try again.');
    } finally {
      setState(() {
        _isGettingLocation = false;
      });
    }
  }

  void _copyCurrentToPermanent() {
    setState(() {
      _selectedPermanentCountry = _selectedTemporaryCountry;
      _selectedPermanentState = _selectedTemporaryState;
      _selectedPermanentCity = _selectedTemporaryCity;
      _permanentToleController.text = _temporaryToleController.text;
    });
  }

  bool get _canContinue {
    return _selectedTemporaryCountry != null &&
        _selectedTemporaryState != null &&
        _selectedTemporaryCity != null &&
        _temporaryToleController.text.isNotEmpty &&
        _selectedResidentialStatus2 != null &&
        _willingToGoAbroad != null &&
        (_willingToGoAbroad == false || _selectedVisaStatus != null) &&
        _selectedPermanentCountry != null &&
        _selectedPermanentState != null &&
        _selectedPermanentCity != null &&
        _permanentToleController.text.isNotEmpty &&
        _selectedResidentialStatus != null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Stack(
          children: [
            RegistrationStepContainer(
              onBack: () => Navigator.pop(context),
              onStepBack: () => Navigator.pop(context), // Allow step-by-step back navigation
              onContinue: _validateAndSubmit,
              isLoading: _isLoading,
              canContinue: _canContinue,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  RegistrationStepHeader(
                    title: 'Living Status',
                    subtitle: 'Share your current and permanent address details',
                    currentStep: 5,
                    totalSteps: 11,
                    onBack: () => Navigator.pop(context),
                    onStepBack: () => Navigator.pop(context), // Allow step-by-step back navigation
                  ),
                  const SizedBox(height: 32),

                  // ============= CURRENT ADDRESS SECTION =============
                  SectionHeader(
                    title: 'Current Address',
                    subtitle: 'Where do you currently live?',
                    icon: Icons.location_on_rounded,
                  ),
                  const SizedBox(height: 20),

                  // Country
                  TypingDropdown<String>(
                    title: 'Country',
                    selectedItem: _selectedTemporaryCountry,
                    items: _countryOptions,
                    itemLabel: (item) => item,
                    hint: 'Select country',
                    showError: submitted,
                    onChanged: (value) async {
                      setState(() {
                        _selectedTemporaryCountry = value;
                        _selectedTemporaryState = null;
                        _selectedTemporaryCity = null;
                        _stateOptions.clear();
                        _cityOptions.clear();
                      });

                      if (value != null) {
                        final countryId = _countryMap[value]!;
                        await loadStates(countryId);
                      }
                    },
                  ),
                  const SizedBox(height: 20),

                  // State and City Row
                  Row(
                    children: [
                      Expanded(
                        child: TypingDropdown<String>(
                          title: 'State / Province',
                          selectedItem: _selectedTemporaryState,
                          items: _stateOptions,
                          itemLabel: (item) => item,
                          hint: 'Select state',
                          showError: submitted,
                          onChanged: (value) async {
                            setState(() {
                              _selectedTemporaryState = value;
                              _selectedTemporaryCity = null;
                              _cityOptions.clear();
                            });

                            if (value != null && _stateMap.containsKey(value)) {
                              final stateId = _stateMap[value]!;
                              await loadCities(stateId);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TypingDropdown<String>(
                          title: 'City',
                          selectedItem: _selectedTemporaryCity,
                          items: _cityOptions,
                          itemLabel: (item) => item,
                          hint: 'Select city',
                          showError: submitted,
                          onChanged: (value) {
                            setState(() {
                              _selectedTemporaryCity = value;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Tole/Landmark with GPS
                  EnhancedTextField(
                    label: 'Tole, Landmark',
                    controller: _temporaryToleController,
                    hint: 'Enter your tole, landmark',
                    readOnly: true,
                    hasError: submitted && _temporaryToleController.text.isEmpty,
                    errorText: submitted && _temporaryToleController.text.isEmpty
                        ? 'Please enter landmark'
                        : null,
                    prefixIcon: Icons.location_searching_rounded,
                    suffixIcon: IconButton(
                      icon: _isGettingLocation
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                              ),
                            )
                          : const Icon(Icons.gps_fixed, color: AppColors.primary),
                      onPressed: _isGettingLocation
                          ? null
                          : () => _getCurrentLocation(_temporaryToleController),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Residential Status
                  EnhancedDropdown<String>(
                    label: 'Residential Status',
                    value: _selectedResidentialStatus2,
                    items: _residentialStatusOptions,
                    itemLabel: (item) => item,
                    hint: 'Select residential status',
                    isRequired: true,
                    hasError: submitted && _selectedResidentialStatus2 == null,
                    errorText: submitted && _selectedResidentialStatus2 == null
                        ? 'Please select residential status'
                        : null,
                    onChanged: (value) {
                      setState(() {
                        _selectedResidentialStatus2 = value;
                      });
                    },
                    prefixIcon: Icons.home_work_rounded,
                  ),
                  const SizedBox(height: 24),

                  // Willing to go abroad
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12, left: 4),
                        child: Row(
                          children: [
                            Text(
                              'Willing To Go Abroad?',
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
                            child: EnhancedRadioOption<bool>(
                              label: 'Yes',
                              value: true,
                              groupValue: _willingToGoAbroad,
                              onChanged: (value) {
                                setState(() {
                                  _willingToGoAbroad = value;
                                  if (submitted) {
                                    _fieldErrors['willingToGoAbroad'] = null;
                                  }
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: EnhancedRadioOption<bool>(
                              label: 'No',
                              value: false,
                              groupValue: _willingToGoAbroad,
                              onChanged: (value) {
                                setState(() {
                                  _willingToGoAbroad = value;
                                  if (submitted) {
                                    _fieldErrors['willingToGoAbroad'] = null;
                                  }
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      if (submitted && _willingToGoAbroad == null) ...[
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
                              const Text(
                                'Please select if willing to go abroad',
                                style: TextStyle(
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
                  const SizedBox(height: 20),

                  // Visa Status (conditional)
                  if (_willingToGoAbroad == true) ...[
                    EnhancedDropdown<String>(
                      label: 'Visa Status',
                      value: _selectedVisaStatus,
                      items: _visaStatusOptions,
                      itemLabel: (item) => item,
                      hint: 'Select visa status',
                      isRequired: true,
                      hasError: submitted && _selectedVisaStatus == null,
                      errorText: submitted && _selectedVisaStatus == null
                          ? 'Please select visa status'
                          : null,
                      onChanged: (value) {
                        setState(() {
                          _selectedVisaStatus = value;
                        });
                      },
                      prefixIcon: Icons.card_travel_rounded,
                    ),
                    const SizedBox(height: 20),
                  ],

                  const SizedBox(height: 32),

                  // Divider
                  const Divider(height: 1, thickness: 1, color: AppColors.border),
                  const SizedBox(height: 32),

                  // ============= PERMANENT ADDRESS SECTION =============
                  SectionHeader(
                    title: 'Permanent Address',
                    subtitle: 'Your permanent/home address',
                    icon: Icons.home_rounded,
                  ),
                  const SizedBox(height: 16),

                  // Same as current address checkbox
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: _sameAsPermanent
                          ? AppColors.primary.withOpacity(0.05)
                          : AppColors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _sameAsPermanent ? AppColors.primary : AppColors.border,
                        width: 1.5,
                      ),
                    ),
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _sameAsPermanent = !_sameAsPermanent;
                          if (_sameAsPermanent) {
                            _copyCurrentToPermanent();
                          }
                        });
                      },
                      child: Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: _sameAsPermanent
                                  ? AppColors.primary
                                  : AppColors.white,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: _sameAsPermanent
                                    ? AppColors.primary
                                    : AppColors.border,
                                width: 2,
                              ),
                            ),
                            child: _sameAsPermanent
                                ? const Icon(
                                    Icons.check,
                                    size: 16,
                                    color: AppColors.white,
                                  )
                                : null,
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Same As Current Address',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  if (!_sameAsPermanent) ...[
                    // Country
                    TypingDropdown<String>(
                      title: 'Country',
                      selectedItem: _selectedPermanentCountry,
                      items: _countryOptions,
                      itemLabel: (item) => item,
                      hint: 'Select country',
                      showError: submitted,
                      onChanged: (value) async {
                        setState(() {
                          _selectedPermanentCountry = value;
                        });

                        if (value != null) {
                          final countryId = _countryMap[value]!;
                          await loadStates(countryId);
                        }
                      },
                    ),
                    const SizedBox(height: 20),

                    // State and City Row
                    Row(
                      children: [
                        Expanded(
                          child: TypingDropdown<String>(
                            title: 'State / Province',
                            selectedItem: _selectedPermanentState,
                            items: _stateOptions,
                            itemLabel: (item) => item,
                            hint: 'Select state',
                            showError: submitted,
                            onChanged: (value) async {
                              setState(() {
                                _selectedPermanentState = value;
                              });

                              if (value != null && _stateMap.containsKey(value)) {
                                final stateId = _stateMap[value]!;
                                await loadCities(stateId);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TypingDropdown<String>(
                            title: 'City',
                            selectedItem: _selectedPermanentCity,
                            items: _cityOptions,
                            itemLabel: (item) => item,
                            hint: 'Select city',
                            showError: submitted,
                            onChanged: (value) {
                              setState(() {
                                _selectedPermanentCity = value;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Tole/Landmark with GPS
                    EnhancedTextField(
                      label: 'Tole, Landmark',
                      controller: _permanentToleController,
                      hint: 'Enter your tole, landmark',
                      readOnly: true,
                      hasError: submitted && _permanentToleController.text.isEmpty,
                      errorText: submitted && _permanentToleController.text.isEmpty
                          ? 'Please enter landmark'
                          : null,
                      prefixIcon: Icons.location_searching_rounded,
                      suffixIcon: IconButton(
                        icon: _isGettingLocation
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(AppColors.primary),
                                ),
                              )
                            : const Icon(Icons.gps_fixed, color: AppColors.primary),
                        onPressed: _isGettingLocation
                            ? null
                            : () => _getCurrentLocation(_permanentToleController),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Permanent Residential Status
                  EnhancedDropdown<String>(
                    label: 'Residential Status',
                    value: _selectedResidentialStatus,
                    items: _residentialStatusOptions,
                    itemLabel: (item) => item,
                    hint: 'Select residential status',
                    isRequired: true,
                    hasError: submitted && _selectedResidentialStatus == null,
                    errorText: submitted && _selectedResidentialStatus == null
                        ? 'Please select residential status'
                        : null,
                    onChanged: (value) {
                      setState(() {
                        _selectedResidentialStatus = value;
                      });
                    },
                    prefixIcon: Icons.home_work_rounded,
                  ),
                ],
              ),
            ),

            // Loading overlay
            if (_isGettingLocation)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                      ),
                      SizedBox(height: 16),
                      Text(
                        "Detecting your location...",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _validateAndSubmit() {
    setState(() {
      submitted = true;
    });

    // Basic validation - Current Address First
    if (_selectedTemporaryCountry == null) {
      _showError("Please select current country");
      return;
    }

    if (_selectedTemporaryState == null) {
      _showError("Please select current state/province");
      return;
    }

    if (_selectedTemporaryCity == null) {
      _showError("Please select current city");
      return;
    }

    if (_temporaryToleController.text.isEmpty) {
      _showError("Please enter current address landmark");
      return;
    }

    if (_selectedResidentialStatus2 == null) {
      _showError("Please select current residential status");
      return;
    }

    if (_willingToGoAbroad == null) {
      _showError("Please select if willing to go abroad");
      return;
    }

    if (_willingToGoAbroad == true && _selectedVisaStatus == null) {
      _showError("Please select visa status");
      return;
    }

    // Permanent Address Validation
    if (_selectedPermanentCountry == null) {
      _showError("Please select permanent country");
      return;
    }

    if (_selectedPermanentState == null) {
      _showError("Please select permanent state/province");
      return;
    }

    if (_selectedPermanentCity == null) {
      _showError("Please select permanent city");
      return;
    }

    if (_permanentToleController.text.isEmpty) {
      _showError("Please enter permanent address landmark");
      return;
    }

    if (_selectedResidentialStatus == null) {
      _showError("Please select permanent residential status");
      return;
    }

    _submitAddress();
  }

  Future<void> _submitAddress() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');
      final userData = jsonDecode(userDataString!);
      final userId = int.tryParse(userData["id"].toString());

      Map<String, String> body = {
        'userid': userId.toString(),
        'current_country': _selectedTemporaryCountry.toString(),
        'current_state': _selectedTemporaryState ?? '',
        'current_city': _selectedTemporaryCity ?? '',
        'current_tole': _temporaryToleController.text.isNotEmpty
            ? _temporaryToleController.text
            : 'Not specified',
        'current_residentalstatus': _selectedResidentialStatus2 ?? 'Own House',
        'current_willingtogoabroad': _willingToGoAbroad == true ? '1' : '0',
        'current_visastatus': _willingToGoAbroad == true
            ? (_selectedVisaStatus ?? 'No Visa')
            : 'No Visa',
        'permanent_country': _selectedPermanentCountry ?? 'Nepal',
        'permanent_state': _selectedPermanentState ?? '',
        'permanent_city': _selectedPermanentCity ?? '',
        'permanent_tole': _permanentToleController.text.isNotEmpty
            ? _permanentToleController.text
            : 'Not specified',
        'permanent_residentalstatus': _selectedResidentialStatus ?? 'Own House',
      };

      final response = await http
          .post(
            Uri.parse('${kApiBaseUrl}/Api2/updateadress.php'),
            body: body,
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success') {
          // Persist country + state so later screens (e.g. Astro Details)
          // can pre-populate their location fields without re-hardcoding.
          await prefs.setString('reg_country', _selectedTemporaryCountry ?? '');
          await prefs.setString('reg_state',   _selectedTemporaryState   ?? '');

          bool updated = await UpdateService.updatePageNumber(
            userId: userId.toString(),
            pageNo: 3,
          );

          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => FamilyDetailsPage()),
            );
          }
        } else {
          _showError(data['message'] ?? 'Failed to save addresses');
        }
      } else {
        _showError('Server error: ${response.statusCode}');
      }
    } on http.ClientException catch (e) {
      _showError('Network error: Please check your internet connection');
    } on SocketException catch (e) {
      _showError('Network error: Cannot connect to server');
    } on TimeoutException catch (e) {
      _showError('Request timeout: Please try again');
    } catch (e) {
      _showError('Failed to submit. Please try again.');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showError(String message) {
    if (!mounted) return;
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
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
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
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    _permanentToleController.dispose();
    _temporaryToleController.dispose();
    super.dispose();
  }
}
