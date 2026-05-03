/// profile_constants.dart
///
/// Centralized dropdown constants for profile fields.
/// Contains only SHORT, STABLE lists that are unlikely to change
/// (medical standards, binary choices, small fixed taxonomies).
///
/// Used by BOTH the admin app (adminmrz) and the user app (ms2026).
/// Mirror any changes here to apk/lib/config/profile_constants.dart.
///
/// Long / admin-configurable lists (annual income, religion,
/// community, etc.) live in the backend master data and are fetched
/// via get_profile_field_options.php — do NOT add those here.

/// Height options — stable list, shared across admin and user apps.
const List<String> kHeightOptions = [
  '121 cm (4\' 0").ft',
  '122 cm (4\' 0").ft',
  '123 cm (4\' 0").ft',
  '124 cm (4\' 1").ft',
  '125 cm (4\' 1").ft',
  '130 cm (4\' 3").ft',
  '135 cm (4\' 5").ft',
  '140 cm (4\' 7").ft',
  '145 cm (4\' 9").ft',
  '150 cm (4\' 11").ft',
  '155 cm (5\' 1").ft',
  '160 cm (5\' 3").ft',
  '165 cm (5\' 5").ft',
  '170 cm (5\' 7").ft',
  '175 cm (5\' 9").ft',
  '180 cm (5\' 11").ft',
  '185 cm (6\' 1").ft',
  '190 cm (6\' 3").ft',
  '195 cm (6\' 5").ft',
  '200 cm (6\' 7").ft',
];

/// Blood group — medically standardised, will never change.
const List<String> kBloodGroupOptions = [
  'A+',
  'A-',
  'B+',
  'B-',
  'AB+',
  'AB-',
  'O+',
  'O-',
];

/// Manglik status — three fixed options.
const List<String> kManglikOptions = ['Yes', 'No', 'Partial'];

/// Simple Yes / No — used for "Are you working?", "Smoke accept?",
/// "Drink accept?", "Disability accept?".
const List<String> kYesNoOptions = ['Yes', 'No'];

/// Profile visibility / privacy — system-defined, tied to app logic.
const List<String> kPrivacyOptions = ['free', 'paid', 'verified', 'private'];

/// Family type — stable sociological categories.
const List<String> kFamilyTypeOptions = ['Nuclear', 'Joint', 'Extended'];

/// Body type — standard physical classification.
const List<String> kBodyTypeOptions = [
  'Slim',
  'Athletic',
  'Average',
  'Heavy',
  'Muscular',
];

/// Complexion — fairly universal colour scale.
const List<String> kComplexionOptions = [
  'Very Fair',
  'Fair',
  'Wheatish',
  'Dark',
  'Very Dark',
];

/// Profile with child — fixed count options.
const List<String> kProfileWithChildOptions = [
  'No child',
  'One',
  'Two',
  'Three',
  'More than three',
];

/// Diet preference — standard food-habit categories.
/// Kept here (not master data) because the list is short and global.
const List<String> kDietOptions = [
  'Vegetarian',
  'Non-Vegetarian',
  'Vegan',
  'Eggetarian',
];

/// Horoscope / scope belief (herscopeblief).
const List<String> kHerscopeBliefOptions = ['Yes', 'No', "Doesn't matter"];

// ── ID-keyed options ─────────────────────────────────────────────────────────
//
// These are used for fields that store a foreign-key integer in the DB
// (e.g. maritalStatusId → maritalstatus table).  We keep them here as
// plain Maps so we don't import any Flutter/app model into this config file.
// detailscreen.dart converts them to ProfileFieldOption at the callsite.
//
// Schema: {value: '<row_id_as_string>', label: '<display_name>'}

/// Marital status — mirrors the `maritalstatus` table in the database.
/// Values are row IDs; labels are the canonical display names.
const List<Map<String, String>> kMaritalStatusIdEntries = [
  {'value': '1', 'label': 'Still Unmarried'},
  {'value': '2', 'label': 'Widowed'},
  {'value': '3', 'label': 'Divorced'},
  {'value': '4', 'label': 'Waiting Divorce'},
  {'value': '5', 'label': 'Annulled'},
];

// ── Text-value options (same display and stored value) ───────────────────────

/// Marital status as plain text — used in partner preference (user_partner
/// table `maritalstatus` column which stores text, not an ID).
const List<String> kMaritalStatusOptions = [
  'Any',
  'Still Unmarried',
  'Widowed',
  'Divorced',
  'Waiting Divorce',
  'Annulled',
];

/// Gender — system-level, app-defined values.
const List<String> kGenderOptions = ['Male', 'Female', 'Other'];
