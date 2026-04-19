import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ms2026/Auth/Screen/signupscreen8.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../ReUsable/dropdownwidget.dart';
import '../../ReUsable/registration_progress.dart';
import '../../ReUsable/enhanced_form_fields.dart';
import '../../constant/app_colors.dart';
import '../../service/location_service.dart';
import '../../service/updatepage.dart';
import 'package:ms2026/config/app_endpoints.dart';

class AstrologicDetailsPage extends StatefulWidget {
  const AstrologicDetailsPage({super.key});

  @override
  State<AstrologicDetailsPage> createState() => _AstrologicDetailsPageState();
}

class _AstrologicDetailsPageState extends State<AstrologicDetailsPage> {
  bool submitted = false;
  bool isLoading = false;

  // Form variables
  String? _horoscopeBelief;
  String? _selectedCountryOfBirth;
  String? _selectedCityOfBirth;
  String? _selectedZodiacSign;
  TimeOfDay? _selectedTimeOfBirth;
  bool _isAD = true;
  String? _selectedMonth;
  String? _selectedDay;
  String? _selectedYear;
  String? _manglikStatus;

  // Nepali date variables
  List<String> _nepaliMonths = [];
  List<String> _nepaliDays = [];
  List<String> _nepaliYears = [];
  Map<String, int> _nepaliMonthDays = {};

  // Error messages
  final Map<String, String> _errors = {
    'horoscopeBelief': '',
    'countryOfBirth': '',
    'cityOfBirth': '',
    'zodiacSign': '',
    'timeOfBirth': '',
    'month': '',
    'day': '',
    'year': '',
    'manglikStatus': '',
  };

  // Dropdown options
  final List<String> _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];
  final List<String> _dayOptions =
      List.generate(31, (i) => (i + 1).toString().padLeft(2, '0'));
  final List<String> _yearOptions =
      List.generate(100, (i) => (DateTime.now().year - 17 - i).toString());

  // Dynamic location data (loaded from API – same as LivingStatusPage)
  List<String> _countryOptions = [];
  Map<String, int> _countryMap  = {};
  List<String> _stateOptions    = [];
  Map<String, int> _stateMap    = {};
  bool _isLoadingCountries = false;
  bool _isLoadingStates    = false;

  // Zodiac data with symbols and names
  final List<Map<String, String>> _zodiacData = [
    {'name': 'Aries',       'nepali': 'Mesh',      'symbol': '♈', 'dates': 'Mar 21–Apr 19'},
    {'name': 'Taurus',      'nepali': 'Vrishabh',  'symbol': '♉', 'dates': 'Apr 20–May 20'},
    {'name': 'Gemini',      'nepali': 'Mithun',    'symbol': '♊', 'dates': 'May 21–Jun 20'},
    {'name': 'Cancer',      'nepali': 'Karka',     'symbol': '♋', 'dates': 'Jun 21–Jul 22'},
    {'name': 'Leo',         'nepali': 'Simha',     'symbol': '♌', 'dates': 'Jul 23–Aug 22'},
    {'name': 'Virgo',       'nepali': 'Kanya',     'symbol': '♍', 'dates': 'Aug 23–Sep 22'},
    {'name': 'Libra',       'nepali': 'Tula',      'symbol': '♎', 'dates': 'Sep 23–Oct 22'},
    {'name': 'Scorpio',     'nepali': 'Vrishchika','symbol': '♏', 'dates': 'Oct 23–Nov 21'},
    {'name': 'Sagittarius', 'nepali': 'Dhanu',     'symbol': '♐', 'dates': 'Nov 22–Dec 21'},
    {'name': 'Capricorn',   'nepali': 'Makar',     'symbol': '♑', 'dates': 'Dec 22–Jan 19'},
    {'name': 'Aquarius',    'nepali': 'Kumbha',    'symbol': '♒', 'dates': 'Jan 20–Feb 18'},
    {'name': 'Pisces',      'nepali': 'Meen',      'symbol': '♓', 'dates': 'Feb 19–Mar 20'},
  ];

  @override
  void initState() {
    super.initState();
    _initializeNepaliDate();
    _loadDefaultDateFromRegistration();
    _loadCountries();
  }

  @override
  void dispose() {
    super.dispose();
  }

  /// Load the date of birth entered during registration (Step 1) and pre-fill
  /// the birth date fields so the user can verify / modify if needed.
  Future<void> _loadDefaultDateFromRegistration() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');
      if (userDataString == null) return;

      final userData = jsonDecode(userDataString) as Map<String, dynamic>;
      final dob = userData['dateofbirth']?.toString() ?? '';

      if (dob.isEmpty) return;

      // Expected format: YYYY-MM-DD
      final parts = dob.split('-');
      if (parts.length != 3) return;

      final year  = parts[0];
      final month = int.tryParse(parts[1]) ?? 1;
      final day   = parts[2].padLeft(2, '0');

      if (month < 1 || month > 12) return;
      if (!_yearOptions.contains(year)) return;

      setState(() {
        _isAD         = true;
        _selectedYear  = year;
        _selectedMonth = _monthNames[month - 1];
        _selectedDay   = day;
      });
    } catch (e) {
      // Silently ignore – user can still select date manually.
      debugPrint('AstroPage: failed to pre-load registration date: $e');
    }
  }

  /// Load countries from LocationService (same API as LivingStatusPage).
  /// After loading, pre-populate country + state from the values saved
  /// during the registration location step (signupscreen4).
  Future<void> _loadCountries() async {
    setState(() => _isLoadingCountries = true);
    try {
      final data = await LocationService.fetchCountries();
      final List<String> names = [];
      final Map<String, int> map  = {};
      for (final item in data) {
        final n = item['name'].toString();
        final id = int.parse(item['id'].toString());
        names.add(n);
        map[n] = id;
      }

      // Read the country/state that was saved when the user completed
      // the LivingStatusPage (signupscreen4).
      final prefs = await SharedPreferences.getInstance();
      final savedCountry = prefs.getString('reg_country') ?? '';
      final savedState   = prefs.getString('reg_state')   ?? '';

      setState(() {
        _countryOptions = names;
        _countryMap     = map;
        _isLoadingCountries = false;

        // Pre-populate birth country with the registration country, falling
        // back to 'Nepal' if nothing was saved yet.
        if (_selectedCountryOfBirth == null || _selectedCountryOfBirth == 'Nepal') {
          if (savedCountry.isNotEmpty && names.contains(savedCountry)) {
            _selectedCountryOfBirth = savedCountry;
          } else if (names.contains('Nepal')) {
            _selectedCountryOfBirth = 'Nepal';
          } else if (names.isNotEmpty) {
            _selectedCountryOfBirth = names.first;
          }
        }
      });

      // Load states for the pre-populated country.
      if (_selectedCountryOfBirth != null &&
          _countryMap.containsKey(_selectedCountryOfBirth)) {
        await _loadStates(_countryMap[_selectedCountryOfBirth]!,
            preselectState: savedState);
      }
    } catch (e) {
      debugPrint('AstroPage: failed to load countries: $e');
      setState(() => _isLoadingCountries = false);
    }
  }

  Future<void> _loadStates(int countryId, {String preselectState = ''}) async {
    setState(() {
      _isLoadingStates  = true;
      _selectedCityOfBirth = null; // reset state when country changes
      _stateOptions = [];
      _stateMap     = {};
    });
    try {
      final data = await LocationService.fetchStates(countryId);
      final List<String> names = [];
      final Map<String, int> map  = {};
      for (final item in data) {
        final n = item['name'].toString();
        final id = int.parse(item['id'].toString());
        names.add(n);
        map[n] = id;
      }
      setState(() {
        _stateOptions        = names;
        _stateMap            = map;
        _isLoadingStates     = false;

        // Pre-populate with the state saved from registration.
        if (preselectState.isNotEmpty && names.contains(preselectState)) {
          _selectedCityOfBirth = preselectState;
        }
      });
    } catch (e) {
      debugPrint('AstroPage: failed to load states: $e');
      setState(() => _isLoadingStates = false);
    }
  }

  void _initializeNepaliDate() {
    _nepaliMonths = [
      'Baisakh', 'Jestha', 'Ashad', 'Shrawan', 'Bhadra', 'Ashwin',
      'Kartik', 'Mangsir', 'Poush', 'Magh', 'Falgun', 'Chaitra'
    ];
    _nepaliMonthDays = {
      'Baisakh': 31, 'Jestha': 31, 'Ashad': 31, 'Shrawan': 31,
      'Bhadra': 31,  'Ashwin': 30, 'Kartik': 29, 'Mangsir': 29,
      'Poush': 30,   'Magh': 29,   'Falgun': 30,  'Chaitra': 30,
    };
    _nepaliYears = List.generate(91, (i) => (2000 + i).toString());
    _updateDays();
  }

  void _updateDays() {
    if (!_isAD && _selectedMonth != null) {
      final daysInMonth = _nepaliMonthDays[_selectedMonth] ?? 30;
      _nepaliDays =
          List.generate(daysInMonth, (i) => (i + 1).toString().padLeft(2, '0'));
      if (_selectedDay != null) {
        final d = int.tryParse(_selectedDay!);
        if (d != null && d > daysInMonth) _selectedDay = '01';
      } else {
        _selectedDay = '01';
      }
    } else {
      _selectedDay ??= '01';
    }
  }

  // Simple AD to BS conversion (approximate)
  Map<String, String> _convertADtoBS(String adYear, String adMonth, String adDay) {
    // This is a simplified conversion
    int year = int.tryParse(adYear) ?? DateTime.now().year;
    int month = _monthNames.indexOf(adMonth) + 1;
    int day = int.tryParse(adDay) ?? 1;

    // Approximate conversion: AD Year - 57 = BS Year
    int bsYear = year - 57;

    // Approximate month conversion
    int bsMonth = month + 8;
    if (bsMonth > 12) {
      bsMonth -= 12;
      bsYear += 1;
    }

    // Approximate day (same day for simplicity)
    int bsDay = day;

    return {
      'year': bsYear.toString(),
      'month': _nepaliMonths[bsMonth - 1],
      'day': bsDay.toString().padLeft(2, '0'),
    };
  }

  // Simple BS to AD conversion (approximate)
  Map<String, String> _convertBStoAD(String bsYear, String bsMonth, String bsDay) {
    // This is a simplified conversion
    int year = int.tryParse(bsYear) ?? 2080;
    int month = _nepaliMonths.indexOf(bsMonth) + 1;
    int day = int.tryParse(bsDay) ?? 1;

    // Approximate conversion: BS Year + 57 = AD Year
    int adYear = year + 57;

    // Approximate month conversion
    int adMonth = month - 8;
    if (adMonth <= 0) {
      adMonth += 12;
      adYear -= 1;
    }

    // Approximate day (same day for simplicity)
    int adDay = day;

    return {
      'year': adYear.toString(),
      'month': _monthNames[adMonth - 1],
      'day': adDay.toString().padLeft(2, '0'),
    };
  }

  // Time Picker Method
  Future<void> _selectTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTimeOfBirth ?? TimeOfDay.now(),
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
            dialogBackgroundColor: Colors.white,
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _selectedTimeOfBirth) {
      setState(() {
        _selectedTimeOfBirth = picked;
        _errors['timeOfBirth'] = '';
      });
    }
  }

  // Format TimeOfDay to HH:MM:SS for API
  String _formatTimeForAPI(TimeOfDay time) {
    final hours = time.hour.toString().padLeft(2, '0');
    final minutes = time.minute.toString().padLeft(2, '0');
    return '$hours:$minutes:00';
  }

  // Format TimeOfDay for display
  String _formatTimeForDisplay(TimeOfDay time) {
    final hour = time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  // Month conversion function for AD
  String _getMonthNumber(String monthName) {
    final months = {
      'January': '01', 'February': '02', 'March': '03', 'April': '04',
      'May': '05', 'June': '06', 'July': '07', 'August': '08',
      'September': '09', 'October': '10', 'November': '11', 'December': '12'
    };
    return months[monthName] ?? '01';
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

    // Validate horoscope belief
    if (!_validateRequired(_horoscopeBelief, 'horoscopeBelief')) {
      isValid = false;
    }

    // If belief is "Yes", validate all fields
    if (_horoscopeBelief == 'Yes') {
      if (!_validateRequired(_selectedCountryOfBirth, 'countryOfBirth')) {
        isValid = false;
      }
      if (!_validateRequired(_selectedCityOfBirth, 'cityOfBirth')) {
        isValid = false;
      }
      if (!_validateRequired(_selectedZodiacSign, 'zodiacSign')) {
        isValid = false;
      }
      if (_selectedTimeOfBirth == null) {
        _errors['timeOfBirth'] = 'Please select time of birth';
        isValid = false;
      } else {
        _errors['timeOfBirth'] = '';
      }
      if (!_validateRequired(_selectedMonth, 'month')) {
        isValid = false;
      }
      if (!_validateRequired(_selectedDay, 'day')) {
        isValid = false;
      }
      if (!_validateRequired(_selectedYear, 'year')) {
        isValid = false;
      }
      if (!_validateRequired(_manglikStatus, 'manglikStatus')) {
        isValid = false;
      }
    }

    setState(() {});
    return isValid;
  }

  // Handler methods
  void _handleHoroscopeBeliefChange(String? value) {
    setState(() {
      _horoscopeBelief = value;
      _errors['horoscopeBelief'] = '';
    });
  }

  void _handleCountryOfBirthChange(String? value) {
    setState(() {
      _selectedCountryOfBirth = value;
      _errors['countryOfBirth'] = '';
    });
    // Re-load states for the newly selected country.
    if (value != null && _countryMap.containsKey(value)) {
      _loadStates(_countryMap[value]!);
    }
  }

  void _handleCityOfBirthChange(String? value) {
    setState(() {
      _selectedCityOfBirth = value;
      _errors['cityOfBirth'] = '';
    });
  }

  void _handleZodiacSignChange(String? value) {
    setState(() {
      _selectedZodiacSign = value;
      _errors['zodiacSign'] = '';
    });
  }

  void _handleMonthChange(String? value) {
    setState(() {
      _selectedMonth = value;
      _errors['month'] = '';
      if (!_isAD) {
        _updateDays();
      }
    });
  }

  void _handleDayChange(String? value) {
    setState(() {
      _selectedDay = value;
      _errors['day'] = '';
    });
  }

  void _handleYearChange(String? value) {
    setState(() {
      _selectedYear = value;
      _errors['year'] = '';
      if (!_isAD) {
        _updateDays();
      }
    });
  }

  void _handleManglikStatusChange(String? value) {
    setState(() {
      _manglikStatus = value;
      _errors['manglikStatus'] = '';
    });
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0EDF8),
      resizeToAvoidBottomInset: false,
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
                // ── Progress header ──────────────────────────────────────
                RegistrationStepHeader(
                  title: 'Astrological Details',
                  subtitle:
                      'Share your horoscope and birth details for better compatibility',
                  currentStep: 8,
                  totalSteps: 11,
                  onBack: () => Navigator.pop(context),
                  onStepBack: () => Navigator.pop(context), // Allow step-by-step back navigation
                ),
                const SizedBox(height: 20),

                // ── Celestial hero banner ────────────────────────────────
                _buildCelestialBanner(),
                const SizedBox(height: 24),

                // ── Skip button ──────────────────────────────────────────
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: isLoading ? null : _skipPage,
                    icon: const Icon(Icons.skip_next, size: 18),
                    label: const Text('Skip this step'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF5C35A8),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // ── Horoscope Belief card ────────────────────────────────
                _buildAstroCard(
                  icon: Icons.auto_awesome_rounded,
                  title: 'Horoscope Belief',
                  subtitle: 'Do you believe in horoscope matching?',
                  child: Column(
                    children: [
                      _buildThreeOptionButtons(
                        selected: _horoscopeBelief,
                        onChanged: _handleHoroscopeBeliefChange,
                        options: const [
                          _TriOption('Yes',            '✅', Color(0xFF2E7D32)),
                          _TriOption('No',             '❌', Color(0xFFC62828)),
                          _TriOption("Doesn't matter", '🤷', Color(0xFF5C35A8)),
                        ],
                      ),
                      if (submitted && _errors['horoscopeBelief']!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _buildErrorText(_errors['horoscopeBelief']!),
                      ],
                    ],
                  ),
                ),

                // ── Show detail sections only when belief is "Yes" ───────
                if (_horoscopeBelief == 'Yes') ...[
                  const SizedBox(height: 20),

                  // Birth Location card
                  _buildAstroCard(
                    icon: Icons.location_on_outlined,
                    title: 'Birth Location',
                    subtitle: 'Where were you born?',
                    child: Column(
                      children: [
                        // Country — loaded from LocationService API
                        _isLoadingCountries
                            ? _buildLocationLoading('Loading countries…')
                            : EnhancedDropdown<String>(
                                label: 'Country of Birth',
                                value: _selectedCountryOfBirth,
                                items: _countryOptions,
                                itemLabel: (item) => item,
                                hint: 'Select your birth country',
                                onChanged: _handleCountryOfBirthChange,
                                hasError: submitted &&
                                    _errors['countryOfBirth']!.isNotEmpty,
                                errorText: _errors['countryOfBirth'],
                                isRequired: true,
                              ),
                        const SizedBox(height: 16),
                        // State — loaded from LocationService API based on country
                        _isLoadingStates
                            ? _buildLocationLoading('Loading states…')
                            : EnhancedDropdown<String>(
                                label: 'State / Province of Birth',
                                value: _selectedCityOfBirth,
                                items: _stateOptions,
                                itemLabel: (item) => item,
                                hint: _stateOptions.isEmpty
                                    ? 'Select a country first'
                                    : 'Select your birth state',
                                onChanged: _handleCityOfBirthChange,
                                hasError: submitted &&
                                    _errors['cityOfBirth']!.isNotEmpty,
                                errorText: _errors['cityOfBirth'],
                                isRequired: true,
                              ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Birth Date & Time card
                  _buildAstroCard(
                    icon: Icons.calendar_today_outlined,
                    title: 'Birth Date & Time',
                    subtitle:
                        'Pre-filled from your registration. Change if needed.',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Calendar type toggle
                        Row(
                          children: [
                            Expanded(
                              child: _buildCalendarToggleBtn(
                                label: 'AD',
                                sublabel: 'Anno Domini',
                                isSelected: _isAD,
                                onTap: () => setState(() {
                                  if (!_isAD &&
                                      _selectedMonth != null &&
                                      _selectedDay != null &&
                                      _selectedYear != null) {
                                    final c = _convertBStoAD(
                                        _selectedYear!,
                                        _selectedMonth!,
                                        _selectedDay!);
                                    _selectedYear  = c['year'];
                                    _selectedMonth = c['month'];
                                    _selectedDay   = c['day'];
                                  }
                                  _isAD = true;
                                }),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildCalendarToggleBtn(
                                label: 'BS',
                                sublabel: 'Bikram Sambat',
                                isSelected: !_isAD,
                                onTap: () => setState(() {
                                  if (_isAD &&
                                      _selectedMonth != null &&
                                      _selectedDay != null &&
                                      _selectedYear != null) {
                                    final c = _convertADtoBS(
                                        _selectedYear!,
                                        _selectedMonth!,
                                        _selectedDay!);
                                    _selectedYear  = c['year'];
                                    _selectedMonth = c['month'];
                                    _selectedDay   = c['day'];
                                    _updateDays();
                                  } else {
                                    _selectedMonth ??= _nepaliMonths.first;
                                    _selectedYear  ??= '2080';
                                    _updateDays();
                                  }
                                  _isAD = false;
                                }),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Date row
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: EnhancedDropdown<String>(
                                label: 'Month',
                                value: _selectedMonth,
                                items: _isAD ? _monthNames : _nepaliMonths,
                                itemLabel: (item) => item,
                                hint: 'Month',
                                onChanged: _handleMonthChange,
                                hasError:
                                    submitted && _errors['month']!.isNotEmpty,
                                errorText: _errors['month'],
                                isRequired: true,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: EnhancedDropdown<String>(
                                label: 'Day',
                                value: _selectedDay,
                                items: _isAD ? _dayOptions : _nepaliDays,
                                itemLabel: (item) => item,
                                hint: 'DD',
                                onChanged: _handleDayChange,
                                hasError:
                                    submitted && _errors['day']!.isNotEmpty,
                                errorText: _errors['day'],
                                isRequired: true,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TypingDropdown<String>(
                                title: 'Year',
                                selectedItem: _selectedYear,
                                items: _isAD ? _yearOptions : _nepaliYears,
                                itemLabel: (item) => item,
                                hint: 'YYYY',
                                showError: submitted,
                                onChanged: _handleYearChange,
                              ),
                            ),
                          ],
                        ),

                        // Selected date preview banner
                        if (_selectedMonth != null &&
                            _selectedDay != null &&
                            _selectedYear != null) ...[
                          const SizedBox(height: 16),
                          _buildDatePreviewBanner(),
                        ],

                        const SizedBox(height: 20),

                        // Time of birth
                        _buildFieldLabel('Time of Birth', isRequired: true),
                        const SizedBox(height: 12),
                        _buildTimePicker(),
                        if (submitted && _errors['timeOfBirth']!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _buildErrorText(_errors['timeOfBirth']!),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Zodiac Sign card
                  _buildAstroCard(
                    icon: Icons.stars_rounded,
                    title: 'Zodiac Sign',
                    subtitle: 'Select your astrological sign',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildZodiacGrid(),
                        if (submitted && _errors['zodiacSign']!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _buildErrorText(_errors['zodiacSign']!),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Manglik Status card
                  _buildAstroCard(
                    icon: Icons.flare_rounded,
                    title: 'Manglik Status',
                    subtitle: 'Are you Manglik?',
                    child: Column(
                      children: [
                        _buildThreeOptionButtons(
                          selected: _manglikStatus,
                          onChanged: _handleManglikStatusChange,
                          options: const [
                            _TriOption('Yes',            '🔴', Color(0xFFC62828)),
                            _TriOption('No',             '🟢', Color(0xFF2E7D32)),
                            _TriOption("Doesn't matter", '🤷', Color(0xFF5C35A8)),
                          ],
                        ),
                        if (submitted && _errors['manglikStatus']!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _buildErrorText(_errors['manglikStatus']!),
                        ],
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

  // ─── UI Helper Widgets ───────────────────────────────────────────────────────

  /// Celestial banner at the top of the form area
  Widget _buildCelestialBanner() {
    return Container(
      height: 130,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A0533), Color(0xFF3B1D8B), Color(0xFF5C35A8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3B1D8B).withOpacity(0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Decorative star dots
          _starDot(top: 12,  left: 18,  size: 4),
          _starDot(top: 40,  left: 60,  size: 3),
          _starDot(top: 20,  left: 120, size: 5),
          _starDot(top: 60,  left: 90,  size: 3),
          _starDot(top: 80,  left: 40,  size: 4),
          _starDot(top: 30,  right: 100, size: 4),
          _starDot(top: 70,  right: 50,  size: 5),
          _starDot(top: 15,  right: 30,  size: 3),
          _starDot(top: 100, right: 120, size: 4),

          // Content
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                // Zodiac wheel
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withOpacity(0.25),
                      width: 2,
                    ),
                    gradient: RadialGradient(
                      colors: [
                        Colors.white.withOpacity(0.15),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: const Center(
                    child: Text(
                      '☯',
                      style: TextStyle(
                        fontSize: 44,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Celestial Profile',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'The stars reveal your compatibility',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.75),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Zodiac symbols row
                      Text(
                        '♈ ♉ ♊ ♋ ♌ ♍ ♎ ♏ ♐ ♑ ♒ ♓',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withOpacity(0.55),
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Positioned _starDot({
    double? top,
    double? left,
    double? right,
    double? bottom,
    required double size,
  }) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      bottom: bottom,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.6),
        ),
      ),
    );
  }

  /// Astro-themed section card
  Widget _buildAstroCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8E0F7), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5C35A8).withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF3B1D8B), Color(0xFF5C35A8)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 18, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Card body
          Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ],
      ),
    );
  }

  /// Compact 3-option button row (fixes sizing/overflow for long labels)
  Widget _buildThreeOptionButtons({
    required String? selected,
    required ValueChanged<String?> onChanged,
    required List<_TriOption> options,
  }) {
    return Column(
      children: options.map((opt) {
        final isSelected = selected == opt.value;
        return GestureDetector(
          onTap: () => onChanged(opt.value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(bottom: 10),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isSelected
                  ? opt.activeColor.withOpacity(0.08)
                  : const Color(0xFFF8F6FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? opt.activeColor : const Color(0xFFDDD6F0),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Text(opt.emoji, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    opt.value,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: isSelected
                          ? opt.activeColor
                          : const Color(0xFF3D3D5C),
                    ),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? opt.activeColor
                          : const Color(0xFFBBB3D8),
                      width: 2,
                    ),
                    color: isSelected ? opt.activeColor : Colors.transparent,
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  /// Calendar type toggle button
  Widget _buildCalendarToggleBtn({
    required String label,
    required String sublabel,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF5C35A8)
              : const Color(0xFFF4F0FF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF5C35A8)
                : const Color(0xFFDDD6F0),
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : const Color(0xFF5C35A8),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sublabel,
              style: TextStyle(
                fontSize: 10,
                color: isSelected
                    ? Colors.white.withOpacity(0.8)
                    : const Color(0xFF8878C3),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// Date preview banner
  Widget _buildDatePreviewBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEDE7FF), Color(0xFFF3EEFF)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD0C0FF), width: 1),
      ),
      child: Row(
        children: [
          const Text('📅', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _isAD
                  ? 'Birth Date: $_selectedMonth $_selectedDay, $_selectedYear AD'
                  : 'Birth Date: $_selectedMonth $_selectedDay, $_selectedYear BS',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF3B1D8B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Zodiac sign grid (4 columns)
  Widget _buildZodiacGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.2,
      ),
      itemCount: _zodiacData.length,
      itemBuilder: (_, i) {
        final z = _zodiacData[i];
        final isSelected = _selectedZodiacSign == z['name'];
        return GestureDetector(
          onTap: () => setState(() {
            _selectedZodiacSign = z['name'];
            _errors['zodiacSign'] = '';
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF5C35A8)
                  : const Color(0xFFF4F0FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF5C35A8)
                    : const Color(0xFFDDD6F0),
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: const Color(0xFF5C35A8).withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      )
                    ]
                  : [],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  z['symbol']!,
                  style: TextStyle(
                    fontSize: 20,
                    color: isSelected ? Colors.white : const Color(0xFF5C35A8),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  z['nepali']!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? Colors.white : const Color(0xFF3D3D5C),
                  ),
                  textAlign: TextAlign.center,
                ),
                Text(
                  z['name']!,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w400,
                    color: isSelected
                        ? Colors.white.withOpacity(0.85)
                        : const Color(0xFF7B6FAE),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Shown while country/state data is being fetched from the API.
  Widget _buildLocationLoading(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F0FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDDD6F0)),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFF5C35A8),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF8878C3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimePicker() {
    final hasErr = submitted && _errors['timeOfBirth']!.isNotEmpty;
    return GestureDetector(
      onTap: _selectTime,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F0FF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasErr
                ? AppColors.error
                : (_selectedTimeOfBirth != null
                    ? const Color(0xFF5C35A8)
                    : const Color(0xFFDDD6F0)),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.access_time_rounded,
              color: _selectedTimeOfBirth != null
                  ? const Color(0xFF5C35A8)
                  : const Color(0xFF8878C3),
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _selectedTimeOfBirth != null
                    ? _formatTimeForDisplay(_selectedTimeOfBirth!)
                    : 'Select time of birth',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: _selectedTimeOfBirth != null
                      ? FontWeight.w600
                      : FontWeight.w400,
                  color: _selectedTimeOfBirth != null
                      ? const Color(0xFF3B1D8B)
                      : const Color(0xFF8878C3),
                ),
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: const Color(0xFF8878C3),
              size: 24,
            ),
          ],
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
            color: Color(0xFF3D3D5C),
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
        const Icon(Icons.error_outline, size: 14, color: AppColors.error),
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
                "Skip Astrological Details?",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: const Text(
            "You can fill in your astrological details later from your profile settings.",
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
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const LifestylePage()),
                );
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

    await _submitAstrologicData();

    setState(() {
      isLoading = false;
    });
  }

  _submitAstrologicData() async {
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

      // Prepare POST data
      Map<String, String> postData = {
        "userid": userId.toString(),
        "belief": _horoscopeBelief ?? "",
      };

      // Format data properly for API
      if (_horoscopeBelief == 'Yes') {
        // Format birth date to YYYY-MM-DD (API expects this format)
        String birthDate;
        if (_isAD) {
          // AD Date
          String monthNumber = _getMonthNumber(_selectedMonth!);
          birthDate = "${_selectedYear}-${monthNumber.padLeft(2, '0')}-${_selectedDay!.padLeft(2, '0')}";
        } else {
          // BS Date - We need to convert to AD for API
          final converted = _convertBStoAD(_selectedYear!, _selectedMonth!, _selectedDay!);
          String monthNumber = _getMonthNumber(converted['month']!);
          birthDate = "${converted['year']}-${monthNumber.padLeft(2, '0')}-${converted['day']!.padLeft(2, '0')}";
        }

        // Format time to HH:MM:SS (API expects this format)
        String formattedTime = _formatTimeForAPI(_selectedTimeOfBirth!);

        postData.addAll({
          "birthcountry": _selectedCountryOfBirth ?? "",
          "birthcity": _selectedCityOfBirth ?? "",
          "zodiacsign": _selectedZodiacSign ?? "",
          "birthtime": formattedTime,
          "birthdate": birthDate,
          "manglik": _manglikStatus ?? "",
        });

        // Debug info
        print("Birth Date being sent: $birthDate");
        print("Is AD: $_isAD");
        print("Selected Month: $_selectedMonth");
        print("Selected Day: $_selectedDay");
        print("Selected Year: $_selectedYear");
      } else {
        // For "No" or "Doesn't matter", send empty strings for other fields
        postData.addAll({
          "birthcountry": "",
          "birthcity": "",
          "zodiacsign": "",
          "birthtime": "",
          "birthdate": "",
          "manglik": "",
        });
      }

      // Debug print
      print("Sending to API: $postData");

      // Send POST request with better error handling
      final response = await http.post(
        Uri.parse("${kApiBaseUrl}/Api2/user_astrologic.php"),
        body: postData,
      ).timeout(const Duration(seconds: 30));

      print("Raw response: ${response.body}");

      // Check if response is valid JSON
      final decodedResponse = json.decode(response.body);

      if (decodedResponse['status'] == 'success') {
        bool updated = await UpdateService.updatePageNumber(
          userId: userId.toString(),
          pageNo: 6,
        );

        if (updated) {
          _showSuccess("Astrological details saved successfully!");
          // Navigate after a short delay
          Future.delayed(const Duration(seconds: 1), () {
            Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const LifestylePage())
            );
          });
        } else {
          _showError("Failed to update progress");
        }
      } else {
        _showError(decodedResponse['message'] ?? "Failed to save details");
      }
    } on FormatException catch (e) {
      print("JSON Format Error: $e");
      _showError("Server response format error. Please try again.");
    } on http.ClientException catch (e) {
      print("Network Error: $e");
      _showError("Network error. Please check your connection.");
    } on TimeoutException catch (e) {
      print("Timeout Error: $e");
      _showError("Request timeout. Please try again.");
    } catch (e) {
      print("Unexpected Error: $e");
      _showError("An unexpected error occurred: $e");
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

// ─── Helper data class ───────────────────────────────────────────────────────

/// Immutable data object for a 3-option button row item.
class _TriOption {
  final String value;
  final String emoji;
  final Color activeColor;

  const _TriOption(this.value, this.emoji, this.activeColor);
}
