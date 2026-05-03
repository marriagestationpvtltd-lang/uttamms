class MatchedProfile {
  final int id;
  final String firstName;
  final String lastName;
  final String memberid;
  final double matchingPercentage;
  final bool isPaid;
  final bool isOnline;
  final String occupation;
  final String education;
  final String country;
  final String marit;
  final String gender;
  final int age;
  final String profilePicture; // Add this field

  MatchedProfile({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.memberid,
    required this.matchingPercentage,
    required this.isPaid,
    required this.isOnline,
    required this.occupation,
    required this.education,
    required this.country,
    required this.marit,
    required this.gender,
    required this.age,
    required this.profilePicture, // Add this
  });

  MatchedProfile copyWith({bool? isOnline}) {
    return MatchedProfile(
      id: id,
      firstName: firstName,
      lastName: lastName,
      memberid: memberid,
      matchingPercentage: matchingPercentage,
      isPaid: isPaid,
      isOnline: isOnline ?? this.isOnline,
      occupation: occupation,
      education: education,
      country: country,
      marit: marit,
      gender: gender,
      age: age,
      profilePicture: profilePicture,
    );
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static bool _asBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    return normalized == '1' || normalized == 'true' || normalized == 'yes';
  }

  factory MatchedProfile.fromJson(Map<String, dynamic> json) {
    return MatchedProfile(
      id: _asInt(json['id'] ?? json['userid']),
      firstName: (json['first_name'] ?? json['firstName'])?.toString() ?? '',
      lastName: (json['last_name'] ?? json['lastName'])?.toString() ?? '',
      memberid: (json['member_id'] ?? json['memberid'])?.toString() ?? '',
      matchingPercentage: _asDouble(
        json['matching_percentage'] ?? json['matchPercent'],
      ),
      isPaid: _asBool(json['is_paid'] ?? json['isPaid']),
      isOnline: _asBool(json['is_online'] ?? json['isOnline']),
      occupation:
          (json['occupation'] ?? json['occupation_name'] ?? json['designation'])
              ?.toString() ??
          '',
      education:
          (json['education'] ?? json['education_name'])?.toString() ?? '',
      country: (json['country'] ?? json['country_name'])?.toString() ?? '',
      marit:
          (json['marital_status'] ?? json['marital_status_name'])?.toString() ??
          '',
      gender: json['gender']?.toString() ?? '',
      age: _asInt(json['age']),
      profilePicture: json['profile_picture']?.toString() ?? '',
    );
  }
}
