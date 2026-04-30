class UserDetailsResponse {
  final String status;
  final UserDetailsData data;

  UserDetailsResponse({required this.status, required this.data});

  factory UserDetailsResponse.fromJson(Map<String, dynamic> json) {
    return UserDetailsResponse(
      status: json['status']?.toString() ?? '',
      data: UserDetailsData.fromJson(json['data'] ?? {}),
    );
  }
}

class UserDetailsData {
  final PersonalDetail personalDetail;
  final FamilyDetail familyDetail;
  final Lifestyle lifestyle;
  final PartnerPreference partner;
  final ContactDetail contactDetail;

  UserDetailsData({
    required this.personalDetail,
    required this.familyDetail,
    required this.lifestyle,
    required this.partner,
    required this.contactDetail,
  });

  factory UserDetailsData.fromJson(Map<String, dynamic> json) {
    return UserDetailsData(
      personalDetail: PersonalDetail.fromJson(json['personalDetail'] ?? {}),
      familyDetail: FamilyDetail.fromJson(json['familyDetail'] ?? {}),
      lifestyle: Lifestyle.fromJson(json['lifestyle'] ?? {}),
      partner: PartnerPreference.fromJson(json['partner'] ?? {}),
      contactDetail: ContactDetail.fromJson(
        json['contactDetail'] ??
            json['contact'] ??
            json['personalDetail'] ??
            {},
      ),
    );
  }
}

class PersonalDetail {
  final String photoRequest;
  final String firstName;
  final String lastName;
  final String profilePicture;
  final String userType;
  final int isVerified;
  final String privacy;
  final String city;
  final String country;
  final String educationMedium;
  final String educationType;
  final String faculty;
  final String degree;
  final String areYouWorking;
  final String occupationType;
  final String companyName;
  final String designation;
  final String workingWith;
  final String annualIncome;
  final String businessName;
  final String memberId;
  final String heightName;
  final int maritalStatusId;
  final String maritalStatusName;
  final String motherTongue;
  final String aboutMe;
  final String birthDate;
  final String disability;
  final String bloodGroup;
  final String religionName;
  final String communityName;
  final String subCommunityName;
  final String manglik;
  final String birthtime;
  final String birthcity;

  static String _sanitizeProfilePicture(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty || value == 'null') return '';
    final lower = value.toLowerCase();
    if (lower.endsWith('/default.png') || lower.endsWith('default.png')) {
      return '';
    }
    return value;
  }

  PersonalDetail({
    required this.photoRequest,
    required this.firstName,
    required this.lastName,
    required this.profilePicture,
    required this.userType,
    required this.isVerified,
    required this.privacy,
    required this.city,
    required this.country,
    required this.educationMedium,
    required this.educationType,
    required this.faculty,
    required this.degree,
    required this.areYouWorking,
    required this.occupationType,
    required this.companyName,
    required this.designation,
    required this.workingWith,
    required this.annualIncome,
    required this.businessName,
    required this.memberId,
    required this.heightName,
    required this.maritalStatusId,
    required this.maritalStatusName,
    required this.motherTongue,
    required this.aboutMe,
    required this.birthDate,
    required this.disability,
    required this.bloodGroup,
    required this.religionName,
    required this.communityName,
    required this.subCommunityName,
    required this.manglik,
    required this.birthtime,
    required this.birthcity,
  });

  factory PersonalDetail.fromJson(Map<String, dynamic> json) {
    return PersonalDetail(
      photoRequest: json['photo_request']?.toString() ?? '',
      firstName: json['firstName']?.toString() ?? 'Not available',
      lastName: json['lastName']?.toString() ?? 'Not available',
      profilePicture: _sanitizeProfilePicture(
        json['profile_picture']?.toString(),
      ),
      userType: json['usertype']?.toString() ?? '',
      isVerified: json['isVerified'] is int ? json['isVerified'] : 0,
      privacy: json['privacy']?.toString() ?? '',
      city: json['city']?.toString() ?? 'Not available',
      country: json['country']?.toString() ?? 'Not available',
      educationMedium: json['educationmedium']?.toString() ?? 'Not available',
      educationType: json['educationtype']?.toString() ?? 'Not available',
      faculty: json['faculty']?.toString() ?? 'Not available',
      degree: json['degree']?.toString() ?? 'Not available',
      areYouWorking: json['areyouworking']?.toString() ?? 'Not available',
      occupationType: json['occupationtype']?.toString() ?? 'Not available',
      companyName: json['companyname']?.toString() ?? 'Not available',
      designation: json['designation']?.toString() ?? 'Not available',
      workingWith: json['workingwith']?.toString() ?? 'Not available',
      annualIncome: json['annualincome']?.toString() ?? 'Not available',
      businessName: json['businessname']?.toString() ?? '',
      memberId: json['memberid']?.toString() ?? 'Not available',
      heightName: json['height_name']?.toString() ?? 'Not available',
      maritalStatusId: json['maritalStatusId'] is int
          ? json['maritalStatusId']
          : 0,
      maritalStatusName:
          json['maritalStatusName']?.toString() ?? 'Not available',
      motherTongue: json['motherTongue']?.toString() ?? 'Not available',
      aboutMe: json['aboutMe']?.toString() ?? 'Not available',
      birthDate: json['birthDate']?.toString() ?? '',
      disability: json['Disability']?.toString() ?? 'Not available',
      bloodGroup: json['bloodGroup']?.toString() ?? 'Not available',
      religionName: json['religionName']?.toString() ?? 'Not available',
      communityName: json['communityName']?.toString() ?? 'Not available',
      subCommunityName: json['subCommunityName']?.toString() ?? 'Not available',
      manglik: json['manglik']?.toString() ?? 'Not available',
      birthtime: json['birthtime']?.toString() ?? 'Not available',
      birthcity: json['birthcity']?.toString() ?? 'Not available',
    );
  }

  String get fullName => '$firstName $lastName';

  int? get age {
    if (birthDate.isEmpty) return null;
    try {
      final birthDateTime = DateTime.parse(birthDate);
      final now = DateTime.now();
      int age = now.year - birthDateTime.year;
      if (now.month < birthDateTime.month ||
          (now.month == birthDateTime.month && now.day < birthDateTime.day)) {
        age--;
      }
      return age;
    } catch (e) {
      return null;
    }
  }

  bool get hasProfilePicture {
    if (profilePicture.isEmpty || profilePicture == 'null') return false;
    final lower = profilePicture.toLowerCase();
    if (lower.endsWith('/default.png') || lower.endsWith('default.png')) {
      return false;
    }
    return true;
  }
}

class ContactDetail {
  final String email;
  final String phone;
  final String whatsapp;
  final String countryCode;

  ContactDetail({
    required this.email,
    required this.phone,
    required this.whatsapp,
    required this.countryCode,
  });

  factory ContactDetail.fromJson(Map<String, dynamic> json) {
    return ContactDetail(
      email: json['email']?.toString() ?? '',
      phone:
          json['phone']?.toString() ??
          json['mobile']?.toString() ??
          json['phone_number']?.toString() ??
          '',
      whatsapp: json['whatsapp']?.toString() ?? '',
      countryCode: json['country_code']?.toString() ?? '',
    );
  }

  ContactDetail withFallback({
    String? email,
    String? phone,
    String? whatsapp,
    String? countryCode,
  }) {
    return ContactDetail(
      email: (email ?? this.email).isNotEmpty
          ? (email ?? this.email)
          : this.email,
      phone: (phone ?? this.phone).isNotEmpty
          ? (phone ?? this.phone)
          : this.phone,
      whatsapp: (whatsapp ?? this.whatsapp).isNotEmpty
          ? (whatsapp ?? this.whatsapp)
          : this.whatsapp,
      countryCode: (countryCode ?? this.countryCode).isNotEmpty
          ? (countryCode ?? this.countryCode)
          : this.countryCode,
    );
  }

  bool get hasEmail => email.isNotEmpty && email != 'null';
  bool get hasPhone => preferredPhone.isNotEmpty;

  String get preferredPhone {
    if (phone.isNotEmpty && phone != 'null') return phone;
    if (whatsapp.isNotEmpty && whatsapp != 'null') return whatsapp;
    return '';
  }
}

class FamilyDetail {
  final int familyId;
  final String familyType;
  final String familyBackground;
  final String fatherStatus;
  final String fatherName;
  final String fatherEducation;
  final String fatherOccupation;
  final String motherStatus;
  final String motherCaste;
  final String motherEducation;
  final String motherOccupation;
  final String familyOrigin;

  FamilyDetail({
    required this.familyId,
    required this.familyType,
    required this.familyBackground,
    required this.fatherStatus,
    required this.fatherName,
    required this.fatherEducation,
    required this.fatherOccupation,
    required this.motherStatus,
    required this.motherCaste,
    required this.motherEducation,
    required this.motherOccupation,
    required this.familyOrigin,
  });

  factory FamilyDetail.fromJson(Map<String, dynamic> json) {
    return FamilyDetail(
      familyId: json['familyId'] is int ? json['familyId'] : 0,
      familyType: json['familytype']?.toString() ?? 'Not available',
      familyBackground: json['familybackground']?.toString() ?? 'Not available',
      fatherStatus: json['fatherstatus']?.toString() ?? 'Not available',
      fatherName: json['fathername']?.toString() ?? 'Not available',
      fatherEducation: json['fathereducation']?.toString() ?? 'Not available',
      fatherOccupation: json['fatheroccupation']?.toString() ?? 'Not available',
      motherStatus: json['motherstatus']?.toString() ?? 'Not available',
      motherCaste: json['mothercaste']?.toString() ?? 'Not available',
      motherEducation: json['mothereducation']?.toString() ?? 'Not available',
      motherOccupation: json['motheroccupation']?.toString() ?? 'Not available',
      familyOrigin: json['familyorigin']?.toString() ?? 'Not available',
    );
  }
}

class Lifestyle {
  final int lifestyleId;
  final String smokeType;
  final String diet;
  final String drinks;
  final String drinkType;
  final String smoke;

  Lifestyle({
    required this.lifestyleId,
    required this.smokeType,
    required this.diet,
    required this.drinks,
    required this.drinkType,
    required this.smoke,
  });

  factory Lifestyle.fromJson(Map<String, dynamic> json) {
    return Lifestyle(
      lifestyleId: json['lifestyleId'] is int ? json['lifestyleId'] : 0,
      smokeType: json['smoketype']?.toString() ?? 'Not available',
      diet: json['diet']?.toString() ?? 'Not available',
      drinks: json['drinks']?.toString() ?? 'Not available',
      drinkType: json['drinktype']?.toString() ?? 'Not available',
      smoke: json['smoke']?.toString() ?? 'Not available',
    );
  }
}

class PartnerPreference {
  final int minAge;
  final int maxAge;
  final int minHeight;
  final int maxHeight;
  final String maritalStatus;
  final String profileWithChild;
  final String familyType;
  final String religion;
  final String caste;
  final String motherTongue;
  final String hersCopeBelief;
  final String manglik;
  final String country;
  final String state;
  final String city;
  final String qualification;
  final String educationMedium;
  final String profession;
  final String workingWith;
  final String annualIncome;
  final String diet;
  final String smokeAccept;
  final String drinkAccept;
  final String disabilityAccept;
  final String complexion;
  final String bodyType;
  final String otherExpectation;

  PartnerPreference({
    required this.minAge,
    required this.maxAge,
    required this.minHeight,
    required this.maxHeight,
    required this.maritalStatus,
    required this.profileWithChild,
    required this.familyType,
    required this.religion,
    required this.caste,
    required this.motherTongue,
    required this.hersCopeBelief,
    required this.manglik,
    required this.country,
    required this.state,
    required this.city,
    required this.qualification,
    required this.educationMedium,
    required this.profession,
    required this.workingWith,
    required this.annualIncome,
    required this.diet,
    required this.smokeAccept,
    required this.drinkAccept,
    required this.disabilityAccept,
    required this.complexion,
    required this.bodyType,
    required this.otherExpectation,
  });

  factory PartnerPreference.fromJson(Map<String, dynamic> json) {
    return PartnerPreference(
      minAge: json['minage'] is int ? json['minage'] : 0,
      maxAge: json['maxage'] is int ? json['maxage'] : 0,
      minHeight: json['minheight'] is int ? json['minheight'] : 0,
      maxHeight: json['maxheight'] is int ? json['maxheight'] : 0,
      maritalStatus: json['maritalstatus']?.toString() ?? 'Not available',
      profileWithChild: json['profilewithchild']?.toString() ?? 'Not available',
      familyType: json['familytype']?.toString() ?? 'Not available',
      religion: json['religion']?.toString() ?? 'Not available',
      caste: json['caste']?.toString() ?? 'Not available',
      motherTongue: json['mothertoungue']?.toString() ?? 'Not available',
      hersCopeBelief: json['herscopeblief']?.toString() ?? 'Not available',
      manglik: json['manglik']?.toString() ?? 'Not available',
      country: json['country']?.toString() ?? 'Not available',
      state: json['state']?.toString() ?? 'Not available',
      city: json['city']?.toString() ?? 'Not available',
      qualification: json['qualification']?.toString() ?? 'Not available',
      educationMedium: json['educationmedium']?.toString() ?? 'Not available',
      profession: json['proffession']?.toString() ?? 'Not available',
      workingWith: json['workingwith']?.toString() ?? 'Not available',
      annualIncome: json['annualincome']?.toString() ?? 'Not available',
      diet: json['diet']?.toString() ?? 'Not available',
      smokeAccept: json['smokeaccept']?.toString() ?? 'Not available',
      drinkAccept: json['drinkaccept']?.toString() ?? 'Not available',
      disabilityAccept: json['disabilityaccept']?.toString() ?? 'Not available',
      complexion: json['complexion']?.toString() ?? 'Not available',
      bodyType: json['bodytype']?.toString() ?? 'Not available',
      otherExpectation: json['otherexpectation']?.toString() ?? 'Not available',
    );
  }

  String get ageRange => '$minAge - $maxAge years';
  String get heightRange => '$minHeight - $maxHeight cm';
}

// ─────────────────────── Activity Stats ───────────────────────────────────────

class ActivityStats {
  final int requestsSent;
  final int requestsReceived;
  final int chatRequestsSent;
  final int chatRequestsAccepted;
  final int profileViews;
  final int matchesCount;

  ActivityStats({
    required this.requestsSent,
    required this.requestsReceived,
    required this.chatRequestsSent,
    required this.chatRequestsAccepted,
    required this.profileViews,
    required this.matchesCount,
  });

  factory ActivityStats.fromJson(Map<String, dynamic> json) {
    int _parse(dynamic v) =>
        v is int ? v : int.tryParse(v?.toString() ?? '0') ?? 0;
    return ActivityStats(
      requestsSent: _parse(json['requests_sent']),
      requestsReceived: _parse(json['requests_received']),
      chatRequestsSent: _parse(json['chat_requests_sent']),
      chatRequestsAccepted: _parse(json['chat_requests_accepted']),
      profileViews: _parse(json['profile_views']),
      matchesCount: _parse(json['matches_count']),
    );
  }

  factory ActivityStats.empty() => ActivityStats(
    requestsSent: 0,
    requestsReceived: 0,
    chatRequestsSent: 0,
    chatRequestsAccepted: 0,
    profileViews: 0,
    matchesCount: 0,
  );
}
