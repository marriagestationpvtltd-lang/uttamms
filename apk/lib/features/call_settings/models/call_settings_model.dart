/// Data models for the Call Settings feature.
///
/// These map 1-to-1 with the JSON shapes returned by:
///   - `call_settings.php` (GET)
///   - `get_call_ringtone.php` (GET)
///
/// [RingtoneModel]     – a single system ringtone (admin managed).
/// [CallSettingsModel] – the current user's call-settings row plus
///                       the full list of available system ringtones.
/// [CallRingtoneModel] – the resolved ringtone for an incoming call.

// =============================================================================
// RingtoneModel
// =============================================================================

class RingtoneModel {
  final String id;
  final String name;
  final String fileUrl;
  final bool isDefault;

  const RingtoneModel({
    required this.id,
    required this.name,
    required this.fileUrl,
    required this.isDefault,
  });

  factory RingtoneModel.fromJson(Map<String, dynamic> json) {
    return RingtoneModel(
      id:        json['id']?.toString() ?? '',
      name:      json['name']?.toString() ?? '',
      fileUrl:   json['file_url']?.toString() ?? '',
      isDefault: json['is_default'] == true || json['is_default'] == 1,
    );
  }

  Map<String, dynamic> toJson() => {
    'id':         id,
    'name':       name,
    'file_url':   fileUrl,
    'is_default': isDefault,
  };

  @override
  String toString() => 'RingtoneModel(id: $id, name: $name)';
}

// =============================================================================
// CallSettingsModel
// =============================================================================

class CallSettingsModel {
  /// Currently selected system ringtone (null → use system default).
  final String? ringtoneId;
  final String? ringtoneName;
  final String? ringtoneUrl;

  /// User-uploaded custom tone.
  final String? customToneUrl;
  final String? customToneName;

  /// If true the custom tone is played; otherwise the system ringtone is used.
  final bool isCustom;

  /// The system-wide default ringtone.
  final RingtoneModel? defaultTone;

  /// All active system ringtones available in the picker.
  final List<RingtoneModel> ringtones;

  const CallSettingsModel({
    this.ringtoneId,
    this.ringtoneName,
    this.ringtoneUrl,
    this.customToneUrl,
    this.customToneName,
    required this.isCustom,
    this.defaultTone,
    required this.ringtones,
  });

  factory CallSettingsModel.fromJson(Map<String, dynamic> json) {
    final settingsMap = (json['settings'] as Map<String, dynamic>?) ?? {};
    final defaultMap  = json['default_tone'] as Map<String, dynamic>?;
    final ringtoneList = (json['ringtones'] as List?) ?? [];

    return CallSettingsModel(
      ringtoneId:    settingsMap['ringtone_id']?.toString(),
      ringtoneName:  settingsMap['ringtone_name']?.toString(),
      ringtoneUrl:   settingsMap['ringtone_url']?.toString(),
      customToneUrl: settingsMap['custom_tone_url']?.toString(),
      customToneName:settingsMap['custom_tone_name']?.toString(),
      isCustom:      settingsMap['is_custom'] == true || settingsMap['is_custom'] == 1,
      defaultTone:   defaultMap != null ? RingtoneModel.fromJson(defaultMap) : null,
      ringtones:     ringtoneList
          .map((e) => RingtoneModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Returns the URL that should be played as the ringtone.
  /// Priority: custom → selected system → default system → null.
  String? get effectiveRingtoneUrl {
    if (isCustom && customToneUrl != null && customToneUrl!.isNotEmpty) {
      return customToneUrl;
    }
    if (ringtoneUrl != null && ringtoneUrl!.isNotEmpty) return ringtoneUrl;
    return defaultTone?.fileUrl;
  }

  @override
  String toString() =>
      'CallSettingsModel(isCustom: $isCustom, customToneName: $customToneName, '
      'ringtoneName: $ringtoneName)';
}

// =============================================================================
// CallRingtoneModel
// =============================================================================

/// Resolved ringtone returned by `get_call_ringtone.php`.
class CallRingtoneModel {
  /// `"custom"` | `"system"` | `"default"` | `"builtin"`
  final String type;
  final String? ringtoneId;
  final String? ringtoneName;

  /// URL to stream/play.  Null when [type] is `"builtin"`.
  final String? ringtoneUrl;

  const CallRingtoneModel({
    required this.type,
    this.ringtoneId,
    this.ringtoneName,
    this.ringtoneUrl,
  });

  factory CallRingtoneModel.fromJson(Map<String, dynamic> json) {
    return CallRingtoneModel(
      type:         json['type']?.toString() ?? 'builtin',
      ringtoneId:   json['ringtone_id']?.toString(),
      ringtoneName: json['ringtone_name']?.toString(),
      ringtoneUrl:  json['ringtone_url']?.toString(),
    );
  }

  bool get isBuiltin => type == 'builtin';

  @override
  String toString() =>
      'CallRingtoneModel(type: $type, ringtoneName: $ringtoneName, url: $ringtoneUrl)';
}
