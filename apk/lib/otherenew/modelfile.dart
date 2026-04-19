// modelfile.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:ms2026/config/app_endpoints.dart';
import 'package:ms2026/utils/privacy_utils.dart';

enum ContactInfoType { freeInquiry, onlineChat }

/// Data model for a single contact information entry.
class ContactInfoItem {
  final ContactInfoType type;
  final String title;
  final IconData displayIcon;

  ContactInfoItem({
    required this.type,
    required this.title,
    required this.displayIcon,
  });
}

/// Data model for a single personal detail entry.
class PersonalDetailItem {
  final IconData icon;
  final String title;
  final String value;

  PersonalDetailItem({
    required this.icon,
    required this.title,
    required this.value,
  });
}

/// Data model for a single community detail entry.
class CommunityDetailItem {
  final IconData icon;
  final String title;
  final String value;

  CommunityDetailItem({
    required this.icon,
    required this.title,
    required this.value,
  });
}

/// Data model for a single education or career detail entry.
class EducationCareerDetailItem {
  final IconData icon;
  final String title;
  final String value;

  EducationCareerDetailItem({
    required this.icon,
    required this.title,
    required this.value,
  });
}

/// Data model for a single life style detail entry.
class LifeStyleDetailItem {
  final IconData icon;
  final String title;
  final String value;

  LifeStyleDetailItem({
    required this.icon,
    required this.title,
    required this.value,
  });
}

/// Data model for a single partner preference entry.
class PartnerPreferenceItem {
  final IconData icon;
  final String title;
  final String value;
  final bool matched;

  PartnerPreferenceItem({
    required this.icon,
    required this.title,
    required this.value,
    required this.matched,
  });
}

/// Data model for another matched profile displayed at the bottom.
/// Data model for matched profile from API
class MatchedProfile {
  final int userid;
  final String? memberid;
  final String firstName;
  final String lastName;
  final int isVerified;
  final String? profilePicture;
  final String privacy;
  final int age;
  final String heightName;
  final String country;
  final String city;
  final String designation;
  final int matchPercent;
  final String photoRequest;
  final bool like;
  final List<String> gallery;
  final bool canViewPhoto; // backend-computed visibility flag

  MatchedProfile({
    required this.userid,
    this.memberid,
    required this.firstName,
    required this.lastName,
    required this.isVerified,
    this.profilePicture,
    required this.privacy,
    required this.age,
    required this.heightName,
    required this.country,
    required this.city,
    required this.designation,
    required this.matchPercent,
    required this.photoRequest,
    required this.like,
    required this.gallery,
    required this.canViewPhoto,
  });

  // Computed getters for UI
  String get name => "$firstName $lastName";
  String get ageAndHeight => "Age $age yrs, $heightName";
  String get profession => designation.isNotEmpty ? designation : "Not specified";
  String get maritalStatus => "Not specified"; // Not in API
  String get qualification => "Not specified"; // Not in API
  String get imageUrl => profilePicture != null && profilePicture!.isNotEmpty
      ? "${kApiBaseUrl}/Api2/$profilePicture"
      : '';

  bool get isVerifiedBool => isVerified == 1;

  factory MatchedProfile.fromJson(Map<String, dynamic> json) {
    final privacyVal = (json['privacy'] ?? 'private').toString().toLowerCase();
    final photoReqVal = (json['photo_request'] ?? 'not sent').toString().toLowerCase();
    return MatchedProfile(
      userid: int.tryParse(json['userid']?.toString() ?? '') ?? 0,
      memberid: json['memberid'],
      firstName: json['firstName'] ?? '',
      lastName: json['lastName'] ?? '',
      isVerified: int.tryParse(json['isVerified']?.toString() ?? '') ?? 0,
      profilePicture: json['profile_picture'],
      privacy: privacyVal,
      age: int.tryParse(json['age']?.toString() ?? '') ?? 0,
      heightName: json['height_name'] ?? '',
      country: json['country'] ?? '',
      city: json['city'] ?? '',
      designation: json['designation'] ?? '',
      matchPercent: int.tryParse(json['matchPercent']?.toString() ?? '') ?? 0,
      photoRequest: photoReqVal,
      like: json['like'] ?? false,
      gallery: List<String>.from(json['gallery'] ?? []),
      canViewPhoto: PrivacyUtils.canViewPhotoFromJson(json),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userid': userid,
      'memberid': memberid,
      'firstName': firstName,
      'lastName': lastName,
      'isVerified': isVerified,
      'profile_picture': profilePicture,
      'privacy': privacy,
      'age': age,
      'height_name': heightName,
      'country': country,
      'city': city,
      'designation': designation,
      'matchPercent': matchPercent,
      'photo_request': photoRequest,
      'like': like,
      'gallery': gallery,
      'can_view_photo': canViewPhoto,
    };
  }
}

/// Personal Detail Model - Exactly matching API response
class PersonalDetail {
  final String photoRequest;
  final String chatRequest;
  final String firstName;
  final String lastName;
  final String profilePicture;
  final String usertype;
  final dynamic isVerified;
  final String privacy;
  final String city;
  final String country;
  final String educationmedium;
  final String educationtype;
  final String faculty;
  final String degree;
  final String areyouworking;
  final String occupationtype;
  final String companyname;
  final String designation;
  final String workingwith;
  final String annualincome;
  final String businessname;
  final String memberid;
  final String heightName;
  final dynamic maritalStatusId;
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
  final String photoRequestType;
  final String chatRequestType;

  PersonalDetail({
    required this.photoRequest,
    required this.chatRequest,
    required this.firstName,
    required this.lastName,
    required this.profilePicture,
    required this.usertype,
    required this.isVerified,
    required this.privacy,
    required this.city,
    required this.country,
    required this.educationmedium,
    required this.educationtype,
    required this.faculty,
    required this.degree,
    required this.areyouworking,
    required this.occupationtype,
    required this.companyname,
    required this.designation,
    required this.workingwith,
    required this.annualincome,
    required this.businessname,
    required this.memberid,
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
    required this.photoRequestType,
    required this.chatRequestType,
  });

  factory PersonalDetail.fromJson(Map<String, dynamic> json) {
    return PersonalDetail(
      photoRequest: json['photo_request'] ?? 'not_sent',
      chatRequest: json['chat_request'] ?? 'not_sent',
      firstName: json['firstName'] ?? '',
      lastName: json['lastName'] ?? '',
      profilePicture: json['profile_picture'] ?? '',
      usertype: json['usertype'] ?? '',
      isVerified: json['isVerified'] ?? 0,
      privacy: json['privacy'] ?? '',
      city: json['city'] ?? '',
      country: json['country'] ?? '',
      educationmedium: json['educationmedium'] ?? '',
      educationtype: json['educationtype'] ?? '',
      faculty: json['faculty'] ?? '',
      degree: json['degree'] ?? '',
      areyouworking: json['areyouworking'] ?? '',
      occupationtype: json['occupationtype'] ?? '',
      companyname: json['companyname'] ?? '',
      designation: json['designation'] ?? '',
      workingwith: json['workingwith'] ?? '',
      annualincome: json['annualincome'] ?? '',
      businessname: json['businessname'] ?? '',
      memberid: json['memberid'] ?? '',
      heightName: json['height_name'] ?? '',
      maritalStatusId: json['maritalStatusId'] ?? '',
      maritalStatusName: json['maritalStatusName'] ?? '',
      motherTongue: json['motherTongue'] ?? '',
      aboutMe: json['aboutMe'] ?? '',
      birthDate: json['birthDate'] ?? '',
      disability: json['Disability'] ?? '',
      bloodGroup: json['bloodGroup'] ?? '',
      religionName: json['religionName'] ?? '',
      communityName: json['communityName'] ?? '',
      subCommunityName: json['subCommunityName'] ?? '',
      manglik: json['manglik'] ?? '',
      birthtime: json['birthtime'] ?? '',
      birthcity: json['birthcity'] ?? '',
      photoRequestType: json['photo_request_type'] ?? 'none',
      chatRequestType: json['chat_request_type'] ?? 'none',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'photo_request': photoRequest,
      'chat_request': chatRequest,
      'firstName': firstName,
      'lastName': lastName,
      'profile_picture': profilePicture,
      'usertype': usertype,
      'isVerified': isVerified,
      'privacy': privacy,
      'city': city,
      'country': country,
      'educationmedium': educationmedium,
      'educationtype': educationtype,
      'faculty': faculty,
      'degree': degree,
      'areyouworking': areyouworking,
      'occupationtype': occupationtype,
      'companyname': companyname,
      'designation': designation,
      'workingwith': workingwith,
      'annualincome': annualincome,
      'businessname': businessname,
      'memberid': memberid,
      'height_name': heightName,
      'maritalStatusId': maritalStatusId,
      'maritalStatusName': maritalStatusName,
      'motherTongue': motherTongue,
      'aboutMe': aboutMe,
      'birthDate': birthDate,
      'Disability': disability,
      'bloodGroup': bloodGroup,
      'religionName': religionName,
      'communityName': communityName,
      'subCommunityName': subCommunityName,
      'manglik': manglik,
      'birthtime': birthtime,
      'birthcity': birthcity,
      'photo_request_type': photoRequestType,
      'chat_request_type': chatRequestType,
    };
  }
}

/// Family Detail Model - Exactly matching API response
class FamilyDetail {
  final int familyId;
  final String familytype;
  final String familybackground;
  final String fatherstatus;
  final String fathername;
  final String fathereducation;
  final String fatheroccupation;
  final String motherstatus;
  final String mothercaste;
  final String mothereducation;
  final String motheroccupation;
  final String familyorigin;

  FamilyDetail({
    required this.familyId,
    required this.familytype,
    required this.familybackground,
    required this.fatherstatus,
    required this.fathername,
    required this.fathereducation,
    required this.fatheroccupation,
    required this.motherstatus,
    required this.mothercaste,
    required this.mothereducation,
    required this.motheroccupation,
    required this.familyorigin,
  });

  factory FamilyDetail.fromJson(Map<String, dynamic> json) {
    return FamilyDetail(
      familyId: int.tryParse(json['familyId']?.toString() ?? '') ?? 0,
      familytype: json['familytype'] ?? '',
      familybackground: json['familybackground'] ?? '',
      fatherstatus: json['fatherstatus'] ?? '',
      fathername: json['fathername'] ?? '',
      fathereducation: json['fathereducation'] ?? '',
      fatheroccupation: json['fatheroccupation'] ?? '',
      motherstatus: json['motherstatus'] ?? '',
      mothercaste: json['mothercaste'] ?? '',
      mothereducation: json['mothereducation'] ?? '',
      motheroccupation: json['motheroccupation'] ?? '',
      familyorigin: json['familyorigin'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'familyId': familyId,
      'familytype': familytype,
      'familybackground': familybackground,
      'fatherstatus': fatherstatus,
      'fathername': fathername,
      'fathereducation': fathereducation,
      'fatheroccupation': fatheroccupation,
      'motherstatus': motherstatus,
      'mothercaste': mothercaste,
      'mothereducation': mothereducation,
      'motheroccupation': motheroccupation,
      'familyorigin': familyorigin,
    };
  }
}

/// Lifestyle Model - Exactly matching API response
class Lifestyle {
  final int lifestyleId;
  final String smoketype;
  final String diet;
  final String drinks;
  final String drinktype;
  final String smoke;

  Lifestyle({
    required this.lifestyleId,
    required this.smoketype,
    required this.diet,
    required this.drinks,
    required this.drinktype,
    required this.smoke,
  });

  factory Lifestyle.fromJson(Map<String, dynamic> json) {
    return Lifestyle(
      lifestyleId: int.tryParse(json['lifestyleId']?.toString() ?? '') ?? 0,
      smoketype: json['smoketype'] ?? '',
      diet: json['diet'] ?? '',
      drinks: json['drinks'] ?? '',
      drinktype: json['drinktype'] ?? '',
      smoke: json['smoke'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'lifestyleId': lifestyleId,
      'smoketype': smoketype,
      'diet': diet,
      'drinks': drinks,
      'drinktype': drinktype,
      'smoke': smoke,
    };
  }
}

/// Partner Preference Model - Exactly matching API response
class PartnerPreference {
  final dynamic minage;
  final dynamic maxage;
  final String minweight;
  final String maxweight;
  final String maritalstatus;
  final String profilewithchild;
  final String familytype;
  final String religion;
  final String caste;
  final String mothertoungue;
  final String herscopeblief;
  final String manglik;
  final String country;
  final String state;
  final String city;
  final String qualification;
  final String educationmedium;
  final String proffession;
  final String workingwith;
  final String annualincome;
  final String diet;
  final String smokeaccept;
  final String drinkaccept;
  final String disabilityaccept;
  final String complexion;
  final String bodytype;
  final String otherexpectation;

  PartnerPreference({
    required this.minage,
    required this.maxage,
    required this.minweight,
    required this.maxweight,
    required this.maritalstatus,
    required this.profilewithchild,
    required this.familytype,
    required this.religion,
    required this.caste,
    required this.mothertoungue,
    required this.herscopeblief,
    required this.manglik,
    required this.country,
    required this.state,
    required this.city,
    required this.qualification,
    required this.educationmedium,
    required this.proffession,
    required this.workingwith,
    required this.annualincome,
    required this.diet,
    required this.smokeaccept,
    required this.drinkaccept,
    required this.disabilityaccept,
    required this.complexion,
    required this.bodytype,
    required this.otherexpectation,
  });

  factory PartnerPreference.fromJson(Map<String, dynamic> json) {
    return PartnerPreference(
      minage: json['minage'] ?? 0,
      maxage: json['maxage'] ?? 0,
      minweight: json['minweight'] ?? '',
      maxweight: json['maxweight'] ?? '',
      maritalstatus: json['maritalstatus'] ?? '',
      profilewithchild: json['profilewithchild'] ?? '',
      familytype: json['familytype'] ?? '',
      religion: json['religion'] ?? '',
      caste: json['caste'] ?? '',
      mothertoungue: json['mothertoungue'] ?? '',
      herscopeblief: json['herscopeblief'] ?? '',
      manglik: json['manglik'] ?? '',
      country: json['country'] ?? '',
      state: json['state'] ?? '',
      city: json['city'] ?? '',
      qualification: json['qualification'] ?? '',
      educationmedium: json['educationmedium'] ?? '',
      proffession: json['proffession'] ?? '',
      workingwith: json['workingwith'] ?? '',
      annualincome: json['annualincome'] ?? '',
      diet: json['diet'] ?? '',
      smokeaccept: json['smokeaccept'] ?? '',
      drinkaccept: json['drinkaccept'] ?? '',
      disabilityaccept: json['disabilityaccept'] ?? '',
      complexion: json['complexion'] ?? '',
      bodytype: json['bodytype'] ?? '',
      otherexpectation: json['otherexpectation'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'minage': minage,
      'maxage': maxage,
      'minweight': minweight,
      'maxweight': maxweight,
      'maritalstatus': maritalstatus,
      'profilewithchild': profilewithchild,
      'familytype': familytype,
      'religion': religion,
      'caste': caste,
      'mothertoungue': mothertoungue,
      'herscopeblief': herscopeblief,
      'manglik': manglik,
      'country': country,
      'state': state,
      'city': city,
      'qualification': qualification,
      'educationmedium': educationmedium,
      'proffession': proffession,
      'workingwith': workingwith,
      'annualincome': annualincome,
      'diet': diet,
      'smokeaccept': smokeaccept,
      'drinkaccept': drinkaccept,
      'disabilityaccept': disabilityaccept,
      'complexion': complexion,
      'bodytype': bodytype,
      'otherexpectation': otherexpectation,
    };
  }
}

/// Gallery Image Model - Exactly matching API response
class GalleryImage {
  final int id;
  final String imageurl;
  final String status;
  final dynamic rejectReason;

  GalleryImage({
    required this.id,
    required this.imageurl,
    required this.status,
    this.rejectReason,
  });

  factory GalleryImage.fromJson(Map<String, dynamic> json) {
    return GalleryImage(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      imageurl: json['imageurl'] ?? '',
      status: json['status'] ?? '',
      rejectReason: json['reject_reason'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'imageurl': imageurl,
      'status': status,
      'reject_reason': rejectReason,
    };
  }
}

/// Partner Match Model - Exactly matching API response
class PartnerMatch {
  final int matchedCount;
  final int totalCount;
  final Map<String, bool> details;

  PartnerMatch({
    required this.matchedCount,
    required this.totalCount,
    required this.details,
  });

  factory PartnerMatch.fromJson(Map<String, dynamic> json) {
    return PartnerMatch(
      matchedCount: int.tryParse(json['matched_count']?.toString() ?? '') ?? 0,
      totalCount: int.tryParse(json['total_count']?.toString() ?? '') ?? 0,
      details: Map<String, bool>.from(json['details'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'matched_count': matchedCount,
      'total_count': totalCount,
      'details': details,
    };
  }
}

/// Access Control Model - Exactly matching API response
class AccessControl {
  final String currentUserPlan;
  final bool canViewPhoto;
  final bool canChat;

  AccessControl({
    required this.currentUserPlan,
    required this.canViewPhoto,
    required this.canChat,
  });

  factory AccessControl.fromJson(Map<String, dynamic> json) {
    return AccessControl(
      currentUserPlan: json['current_user_plan'] ?? '',
      canViewPhoto: json['can_view_photo'] ?? false,
      canChat: json['can_chat'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'current_user_plan': currentUserPlan,
      'can_view_photo': canViewPhoto,
      'can_chat': canChat,
    };
  }
}

/// Data Model - Exactly matching the data object in API response
class ProfileData {
  final PersonalDetail personalDetail;
  final FamilyDetail familyDetail;
  final Lifestyle lifestyle;
  final PartnerPreference partner;

  ProfileData({
    required this.personalDetail,
    required this.familyDetail,
    required this.lifestyle,
    required this.partner,
  });

  factory ProfileData.fromJson(Map<String, dynamic> json) {
    return ProfileData(
      personalDetail: PersonalDetail.fromJson(json['personalDetail'] ?? {}),
      familyDetail: FamilyDetail.fromJson(json['familyDetail'] ?? {}),
      lifestyle: Lifestyle.fromJson(json['lifestyle'] ?? {}),
      partner: PartnerPreference.fromJson(json['partner'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'personalDetail': personalDetail.toJson(),
      'familyDetail': familyDetail.toJson(),
      'lifestyle': lifestyle.toJson(),
      'partner': partner.toJson(),
    };
  }
}

/// Main Response Model - Exactly matching the complete API response
class ProfileResponse {
  final String status;
  final ProfileData data;
  final PartnerMatch partnerMatch;
  final List<GalleryImage> gallery;
  final AccessControl accessControl;

  ProfileResponse({
    required this.status,
    required this.data,
    required this.partnerMatch,
    required this.gallery,
    required this.accessControl,
  });

  factory ProfileResponse.fromJson(Map<String, dynamic> json) {
    return ProfileResponse(
      status: json['status'] ?? '',
      data: ProfileData.fromJson(json['data'] ?? {}),
      partnerMatch: PartnerMatch.fromJson(json['partner_match'] ?? {}),
      gallery: (json['gallery'] as List? ?? [])
          .map((item) => GalleryImage.fromJson(item))
          .toList(),
      accessControl: AccessControl.fromJson(json['access_control'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status,
      'data': data.toJson(),
      'partner_match': partnerMatch.toJson(),
      'gallery': gallery.map((item) => item.toJson()).toList(),
      'access_control': accessControl.toJson(),
    };
  }
}

/// Main UserProfile class that extends ChangeNotifier for state management
/// Main UserProfile class that extends ChangeNotifier for state management
class UserProfile extends ChangeNotifier {
  bool get isPhotoRequestNone =>
      photoRequestStatus == 'not_sent' && photoRequestType == 'none';

  bool get isChatRequestNone =>
      chatRequestStatus == 'not_sent' && chatRequestType == 'none';

  // NEW getters
  String get photoRequestType =>
      profileResponse?.data.personalDetail.photoRequestType ?? 'none';

  String get chatRequestType =>
      profileResponse?.data.personalDetail.chatRequestType ?? 'none';

// CHECK RECEIVED
  bool get isPhotoRequestReceived =>
      photoRequestType == 'received' && isPhotoRequestPending;

  bool get isChatRequestReceived =>
      chatRequestType == 'received' && isChatRequestPending;

// CHECK SENT
  bool get isPhotoRequestSent =>
      photoRequestType == 'sent' && isPhotoRequestPending;

  bool get isChatRequestSent =>
      chatRequestType == 'sent' && isChatRequestPending;

  // Add/update these getters in your UserProfile class

// Check if photos should be blurred.
// Delegates to the backend-computed canViewPhoto from access_control.
// The backend considers: target's privacy setting, photo request status,
// viewer's plan (paid/free), and viewer's verification status.
  bool get shouldBlurPhotos {
    return !canViewPhoto;
  }

// Check if user can view photos (for UI logic)
  bool get canViewPhotos => canViewPhoto;

// For backward compatibility
  bool get shouldBlurProfilePhoto => shouldBlurPhotos;
  bool get shouldBlurGallery => shouldBlurPhotos;
  // Core data from API
  ProfileResponse? profileResponse;

  // UI specific fields (derived from API data)
  List<ContactInfoItem> contactInfo;
  List<String> photoAlbumUrls;
  List<PersonalDetailItem> personalDetails;
  List<CommunityDetailItem> communityDetails;
  List<EducationCareerDetailItem> educationCareerDetails;
  List<LifeStyleDetailItem> lifeStyleDetails;
  List<PartnerPreferenceItem> partnerPreferences;
  List<MatchedProfile> otherMatchedProfiles;

  UserProfile({
    this.profileResponse,
    required this.contactInfo,
    required this.photoAlbumUrls,
    required this.personalDetails,
    required this.communityDetails,
    required this.educationCareerDetails,
    required this.lifeStyleDetails,
    required this.partnerPreferences,
    required this.otherMatchedProfiles,
  });

  // Computed getters for UI
  String get name {
    final firstName = profileResponse?.data.personalDetail.firstName ?? '';
    final lastName = profileResponse?.data.personalDetail.lastName ?? '';
    return '$firstName $lastName'.trim();
  }

  String get studentStatus {
    final educationType = profileResponse?.data.personalDetail.educationtype ?? '';
    final faculty = profileResponse?.data.personalDetail.faculty ?? '';
    if (educationType.isNotEmpty && faculty.isNotEmpty) {
      return "$educationType - $faculty";
    } else if (educationType.isNotEmpty) {
      return educationType;
    } else if (faculty.isNotEmpty) {
      return faculty;
    }
    return "Not specified";
  }

  String get location {
    final city = profileResponse?.data.personalDetail.city ?? '';
    final country = profileResponse?.data.personalDetail.country ?? '';
    if (city.isNotEmpty && country.isNotEmpty) {
      return "$city, $country";
    } else if (city.isNotEmpty) {
      return city;
    } else if (country.isNotEmpty) {
      return country;
    }
    return "Location not specified";
  }

  String get bio => (profileResponse?.data.personalDetail.aboutMe != "Not available" &&
      (profileResponse?.data.personalDetail.aboutMe?.isNotEmpty == true))
      ? profileResponse!.data.personalDetail.aboutMe!
      : "No bio available";

  String get avatarUrl => profileResponse?.data.personalDetail.profilePicture ?? '';

  bool get isVerified => profileResponse?.data.personalDetail.isVerified == 1;

  String get usertype => profileResponse?.accessControl.currentUserPlan ?? '';

  bool get isCurrentUserPaid => usertype == 'paid';

  bool get canViewPhoto => profileResponse?.accessControl.canViewPhoto ?? false;

  int get matchedPreferencesCount => profileResponse?.partnerMatch.matchedCount ?? 0;

  int get totalPreferencesCount => profileResponse?.partnerMatch.totalCount ?? 0;

  String get maritalStatus => profileResponse?.data.personalDetail.maritalStatusName != "Not available"
      ? profileResponse?.data.personalDetail.maritalStatusName ?? "Not specified"
      : "Not specified";

  String get height => profileResponse?.data.personalDetail.heightName != "Not available"
      ? profileResponse?.data.personalDetail.heightName ?? "Not specified"
      : "Not specified";

  String get religion => profileResponse?.data.personalDetail.religionName != "Not available"
      ? profileResponse?.data.personalDetail.religionName ?? "Not specified"
      : "Not specified";

  String get community => profileResponse?.data.personalDetail.communityName != "Not available"
      ? profileResponse?.data.personalDetail.communityName ?? "Not specified"
      : "Not specified";

  String get subCommunity => profileResponse?.data.personalDetail.subCommunityName != "Not available"
      ? profileResponse?.data.personalDetail.subCommunityName ?? "Not specified"
      : "Not specified";

  String get motherTongue => profileResponse?.data.personalDetail.motherTongue != "Not available"
      ? profileResponse?.data.personalDetail.motherTongue ?? "Not specified"
      : "Not specified";

  String get birthDate => profileResponse?.data.personalDetail.birthDate != "Not available"
      ? profileResponse?.data.personalDetail.birthDate ?? "Not specified"
      : "Not specified";

  String get birthTime => profileResponse?.data.personalDetail.birthtime.isNotEmpty == true
      ? profileResponse!.data.personalDetail.birthtime
      : "Not specified";

  String get birthCity => profileResponse?.data.personalDetail.birthcity.isNotEmpty == true
      ? profileResponse!.data.personalDetail.birthcity
      : "Not specified";

  String get manglik => profileResponse?.data.personalDetail.manglik.isNotEmpty == true
      ? profileResponse!.data.personalDetail.manglik
      : "Not specified";

  String get diet => profileResponse?.data.lifestyle.diet.isNotEmpty == true
      ? profileResponse!.data.lifestyle.diet
      : "Not specified";

  String get smoke => profileResponse?.data.lifestyle.smoke.isNotEmpty == true
      ? profileResponse!.data.lifestyle.smoke
      : "Not specified";

  String get drinks => profileResponse?.data.lifestyle.drinks.isNotEmpty == true
      ? profileResponse!.data.lifestyle.drinks
      : "Not specified";

  String get occupation => profileResponse?.data.personalDetail.occupationtype.isNotEmpty == true
      ? profileResponse!.data.personalDetail.occupationtype
      : "Not specified";

  String get companyName => profileResponse?.data.personalDetail.companyname.isNotEmpty == true
      ? profileResponse!.data.personalDetail.companyname
      : "Not specified";

  String get designation => profileResponse?.data.personalDetail.designation.isNotEmpty == true
      ? profileResponse!.data.personalDetail.designation
      : "Not specified";

  String get annualIncome => profileResponse?.data.personalDetail.annualincome.isNotEmpty == true
      ? profileResponse!.data.personalDetail.annualincome
      : "Not specified";

  String get educationMedium => profileResponse?.data.personalDetail.educationmedium.isNotEmpty == true
      ? profileResponse!.data.personalDetail.educationmedium
      : "Not specified";

  String get educationType => profileResponse?.data.personalDetail.educationtype.isNotEmpty == true
      ? profileResponse!.data.personalDetail.educationtype
      : "Not specified";

  String get faculty => profileResponse?.data.personalDetail.faculty.isNotEmpty == true
      ? profileResponse!.data.personalDetail.faculty
      : "Not specified";

  String get degree => profileResponse?.data.personalDetail.degree.isNotEmpty == true
      ? profileResponse!.data.personalDetail.degree
      : "Not specified";

  // Request status getters
  String get photoRequestStatus => profileResponse?.data.personalDetail.photoRequest ?? 'not_sent';
  String get chatRequestStatus => profileResponse?.data.personalDetail.chatRequest ?? 'not_sent';

  // Helper getters for UI

  bool get canChat => isChatRequestAccepted;

  bool get isPhotoRequestPending => photoRequestStatus == 'pending';
  bool get isPhotoRequestAccepted => photoRequestStatus == 'accepted';
  bool get isPhotoRequestRejected => photoRequestStatus == 'rejected';
  bool get isPhotoRequestNotSent => photoRequestStatus == 'not_sent';

  bool get isChatRequestPending => chatRequestStatus == 'pending';
  bool get isChatRequestAccepted => chatRequestStatus == 'accepted';
  bool get isChatRequestRejected => chatRequestStatus == 'rejected';
  bool get isChatRequestNotSent => chatRequestStatus == 'not_sent';

  // Button text helpers
  String get photoRequestButtonText {
    if (isPhotoRequestPending) return 'Photo Request Pending';
    if (isPhotoRequestAccepted) return 'Photos Unlocked';
    if (isPhotoRequestRejected) return 'Photo Request Rejected';
    if (!isCurrentUserPaid) return 'Upgrade to Request Photos';
    return 'Send Photo Request';
  }

  String get chatRequestButtonText {
    if (isChatRequestPending) return 'Chat Request Pending';
    if (isChatRequestAccepted) return 'Start Chat';
    if (isChatRequestRejected) return 'Chat Request Rejected';
    if (!isCurrentUserPaid) return 'Upgrade to Chat';
    return 'Send Chat Request';
  }

  IconData get photoRequestIcon {
    if (isPhotoRequestPending) return Icons.hourglass_empty;
    if (isPhotoRequestAccepted) return Icons.photo_library;
    if (isPhotoRequestRejected) return Icons.block;
    if (!isCurrentUserPaid) return Icons.upgrade;
    return Icons.photo_camera;
  }

  IconData get chatRequestIcon {
    if (isChatRequestPending) return Icons.hourglass_empty;
    if (isChatRequestAccepted) return Icons.chat;
    if (isChatRequestRejected) return Icons.block;
    if (!isCurrentUserPaid) return Icons.upgrade;
    return Icons.chat_bubble_outline;
  }

  Color getPhotoRequestButtonColor(Color red) {
    if (isPhotoRequestPending) return Colors.orange;
    if (isPhotoRequestAccepted) return Colors.green;
    if (isPhotoRequestRejected) return Colors.grey;
    if (!isCurrentUserPaid) return Colors.blue;
    return red;
  }

  Color getChatRequestButtonColor(Color red) {
    if (isChatRequestPending) return Colors.orange;
    if (isChatRequestAccepted) return Colors.green;
    if (isChatRequestRejected) return Colors.grey;
    if (!isCurrentUserPaid) return Colors.blue;
    return red;
  }

  /// Factory constructor to create UserProfile from API response
  factory UserProfile.fromResponse(ProfileResponse response) {
    final personalDetail = response.data.personalDetail;
    final familyDetail = response.data.familyDetail;
    final lifestyle = response.data.lifestyle;
    final partner = response.data.partner;
    final partnerMatch = response.partnerMatch;
    final accessControl = response.accessControl;

    String normalize(dynamic value) {
      if (value == null) return '';
      return value
          .toString()
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), ' ');
    }

    bool isAnyValue(dynamic value) {
      final normalized = normalize(value);
      return normalized.isEmpty ||
          normalized == 'any' ||
          normalized == 'all' ||
          normalized == 'not available' ||
          normalized == 'not specified';
    }

    bool matchesPreference({
      required String key,
      required dynamic preferenceValue,
      required dynamic actualValue,
    }) {
      final apiValue = partnerMatch.details[key];
      if (apiValue is bool) return apiValue;
      if (isAnyValue(preferenceValue)) return true;

      final normalizedPreference = normalize(preferenceValue);
      final normalizedActual = normalize(actualValue);
      if (normalizedActual.isEmpty) return false;

      final options = normalizedPreference
          .split(RegExp(r'[,/|]'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();

      if (options.isEmpty) {
        return normalizedActual == normalizedPreference ||
            normalizedActual.contains(normalizedPreference) ||
            normalizedPreference.contains(normalizedActual);
      }

      return options.any((option) =>
          normalizedActual == option ||
          normalizedActual.contains(option) ||
          option.contains(normalizedActual));
    }

    bool matchesAgeRange() {
      final apiValue = partnerMatch.details['age'];
      if (apiValue is bool) return apiValue;

      final minAge = int.tryParse(partner.minage.toString());
      final maxAge = int.tryParse(partner.maxage.toString());
      if (minAge == null || maxAge == null) return true;

      DateTime? birthDate = DateTime.tryParse(personalDetail.birthDate);
      if (birthDate == null) {
        final match = RegExp(r'^(\d{2})-(\d{2})-(\d{4})$')
            .firstMatch(personalDetail.birthDate);
        if (match != null) {
          final day = int.tryParse(match.group(1)!);
          final month = int.tryParse(match.group(2)!);
          final year = int.tryParse(match.group(3)!);
          if (day != null && month != null && year != null) {
            birthDate = DateTime.tryParse(
              '${year.toString().padLeft(4, '0')}-'
              '${month.toString().padLeft(2, '0')}-'
              '${day.toString().padLeft(2, '0')}',
            );
          }
        }
      }

      if (birthDate == null) return false;

      final now = DateTime.now();
      var computedAge = now.year - birthDate.year;
      final hadBirthday = now.month > birthDate.month ||
          (now.month == birthDate.month && now.day >= birthDate.day);
      if (!hadBirthday) computedAge--;

      return computedAge >= minAge && computedAge <= maxAge;
    }

    // Build contact info based on access control
    final contactInfo = <ContactInfoItem>[];
    if (accessControl.canChat) {
      contactInfo.add(ContactInfoItem(
        type: ContactInfoType.onlineChat,
        title: "Direct chat to user",
        displayIcon: Icons.chat,
      ));
    } else {
      contactInfo.add(ContactInfoItem(
        type: ContactInfoType.onlineChat,
        title: "Upgrade to chat",
        displayIcon: Icons.upgrade,
      ));
    }

    contactInfo.add(ContactInfoItem(
      type: ContactInfoType.freeInquiry,
      title: "Free inquiry from admin",
      displayIcon: Icons.power_settings_new,
    ));

    // Build photo album URLs
    final photoAlbumUrls = response.gallery.map((item) => item.imageurl).toList();

    // Build personal details
    final personalDetails = <PersonalDetailItem>[
      PersonalDetailItem(
        icon: Icons.favorite,
        title: "Marital status",
        value: personalDetail.maritalStatusName.isNotEmpty
            ? personalDetail.maritalStatusName
            : "Not available",
      ),
      PersonalDetailItem(
        icon: Icons.height,
        title: "Height",
        value: personalDetail.heightName.isNotEmpty
            ? personalDetail.heightName
            : "Not available",
      ),
      PersonalDetailItem(
        icon: Icons.female,
        title: "Gender",
        value: "Female",
      ),
      PersonalDetailItem(
        icon: Icons.cake,
        title: "Birth Date",
        value: personalDetail.birthDate.isNotEmpty
            ? personalDetail.birthDate
            : "Not available",
      ),
      PersonalDetailItem(
        icon: Icons.restaurant,
        title: "Diet",
        value: lifestyle.diet.isNotEmpty ? lifestyle.diet : "Not specified",
      ),
      PersonalDetailItem(
        icon: Icons.abc,
        title: "Mother Tongue",
        value: personalDetail.motherTongue.isNotEmpty
            ? personalDetail.motherTongue
            : "Not available",
      ),
      PersonalDetailItem(
        icon: Icons.access_time,
        title: "Birth Time",
        value: personalDetail.birthtime.isNotEmpty
            ? personalDetail.birthtime
            : "Not available",
      ),
      PersonalDetailItem(
        icon: Icons.location_city,
        title: "Birth City",
        value: personalDetail.birthcity.isNotEmpty
            ? personalDetail.birthcity
            : "Not available",
      ),
    ];

    // Build community details
    final communityDetails = <CommunityDetailItem>[
      CommunityDetailItem(
        icon: Icons.menu_book,
        title: "Religion",
        value: personalDetail.religionName.isNotEmpty
            ? personalDetail.religionName
            : "Not available",
      ),
      CommunityDetailItem(
        icon: Icons.groups,
        title: "Community",
        value: personalDetail.communityName.isNotEmpty
            ? personalDetail.communityName
            : "Not available",
      ),
      CommunityDetailItem(
        icon: Icons.group,
        title: "Sub-community",
        value: personalDetail.subCommunityName.isNotEmpty
            ? personalDetail.subCommunityName
            : "Not available",
      ),
      CommunityDetailItem(
        icon: Icons.person_pin,
        title: "Mother tongue",
        value: personalDetail.motherTongue.isNotEmpty
            ? personalDetail.motherTongue
            : "Not available",
      ),
      CommunityDetailItem(
        icon: Icons.star,
        title: "Manglik",
        value: personalDetail.manglik.isNotEmpty
            ? personalDetail.manglik
            : "Not available",
      ),
    ];

    // Build education and career details
    final educationCareerDetails = <EducationCareerDetailItem>[
      EducationCareerDetailItem(
        icon: Icons.text_fields,
        title: "Medium",
        value: personalDetail.educationmedium.isNotEmpty
            ? personalDetail.educationmedium
            : "Not available",
      ),
      EducationCareerDetailItem(
        icon: Icons.assignment,
        title: "Type",
        value: personalDetail.educationtype.isNotEmpty
            ? personalDetail.educationtype
            : "Not available",
      ),
      EducationCareerDetailItem(
        icon: Icons.school,
        title: "Faculty",
        value: personalDetail.faculty.isNotEmpty
            ? personalDetail.faculty
            : "Not available",
      ),
      EducationCareerDetailItem(
        icon: Icons.school,
        title: "Degree",
        value: personalDetail.degree.isNotEmpty
            ? personalDetail.degree
            : "Not available",
      ),
      EducationCareerDetailItem(
        icon: Icons.work,
        title: "Working",
        value: personalDetail.areyouworking.isNotEmpty
            ? personalDetail.areyouworking
            : "Not available",
      ),
      EducationCareerDetailItem(
        icon: Icons.star,
        title: "Occupation",
        value: personalDetail.occupationtype.isNotEmpty
            ? personalDetail.occupationtype
            : "Not available",
      ),
      EducationCareerDetailItem(
        icon: Icons.attach_money,
        title: "Annual income",
        value: personalDetail.annualincome.isNotEmpty
            ? personalDetail.annualincome
            : "Not available",
      ),
      EducationCareerDetailItem(
        icon: Icons.apartment,
        title: "Company",
        value: personalDetail.companyname.isNotEmpty
            ? personalDetail.companyname
            : "Not available",
      ),
      EducationCareerDetailItem(
        icon: Icons.business,
        title: "Designation",
        value: personalDetail.designation.isNotEmpty
            ? personalDetail.designation
            : "Not available",
      ),
    ];

    // Build lifestyle details
    final lifeStyleDetails = <LifeStyleDetailItem>[
      LifeStyleDetailItem(
        icon: Icons.restaurant,
        title: "Diet",
        value: lifestyle.diet.isNotEmpty ? lifestyle.diet : "Not specified",
      ),
      LifeStyleDetailItem(
        icon: Icons.smoking_rooms,
        title: "Smoke",
        value: lifestyle.smoke.isNotEmpty ? lifestyle.smoke : "Not specified",
      ),
      LifeStyleDetailItem(
        icon: Icons.local_bar,
        title: "Drink",
        value: lifestyle.drinks.isNotEmpty ? lifestyle.drinks : "Not specified",
      ),
      if (lifestyle.drinktype.isNotEmpty)
        LifeStyleDetailItem(
          icon: Icons.local_bar,
          title: "Drink Type",
          value: lifestyle.drinktype,
        ),
      if (lifestyle.smoketype.isNotEmpty)
        LifeStyleDetailItem(
          icon: Icons.smoking_rooms,
          title: "Smoke Type",
          value: lifestyle.smoketype,
        ),
    ];

    // Build partner preferences with match indicators
    final partnerPreferences = <PartnerPreferenceItem>[
      PartnerPreferenceItem(
        icon: Icons.cake,
        title: "Age Range",
        value: "${partner.minage} to ${partner.maxage}",
        matched: matchesAgeRange(),
      ),
      PartnerPreferenceItem(
        icon: Icons.menu_book,
        title: "Religion",
        value: partner.religion.isNotEmpty ? partner.religion : "Any",
        matched: matchesPreference(
          key: 'religion',
          preferenceValue: partner.religion,
          actualValue: personalDetail.religionName,
        ),
      ),
      PartnerPreferenceItem(
        icon: Icons.flag,
        title: "Country",
        value: partner.country.isNotEmpty ? partner.country : "Any",
        matched: matchesPreference(
          key: 'country',
          preferenceValue: partner.country,
          actualValue: personalDetail.country,
        ),
      ),
      PartnerPreferenceItem(
        icon: Icons.location_city,
        title: "City",
        value: partner.city.isNotEmpty ? partner.city : "Any",
        matched: matchesPreference(
          key: 'city',
          preferenceValue: partner.city,
          actualValue: personalDetail.city,
        ),
      ),
      PartnerPreferenceItem(
        icon: Icons.restaurant,
        title: "Diet",
        value: partner.diet.isNotEmpty ? partner.diet : "Any",
        matched: matchesPreference(
          key: 'diet',
          preferenceValue: partner.diet,
          actualValue: lifestyle.diet,
        ),
      ),
      PartnerPreferenceItem(
        icon: Icons.favorite,
        title: "Marital Status",
        value: partner.maritalstatus.isNotEmpty ? partner.maritalstatus : "Any",
        matched: matchesPreference(
          key: 'marital_status',
          preferenceValue: partner.maritalstatus,
          actualValue: personalDetail.maritalStatusName,
        ),
      ),
      PartnerPreferenceItem(
        icon: Icons.family_restroom,
        title: "Family Type",
        value: partner.familytype.isNotEmpty ? partner.familytype : "Any",
        matched: matchesPreference(
          key: 'family_type',
          preferenceValue: partner.familytype,
          actualValue: familyDetail.familytype,
        ),
      ),
      PartnerPreferenceItem(
        icon: Icons.groups,
        title: "Caste",
        value: partner.caste.isNotEmpty ? partner.caste : "Any",
        matched: matchesPreference(
          key: 'caste',
          preferenceValue: partner.caste,
          actualValue: personalDetail.communityName,
        ),
      ),
      PartnerPreferenceItem(
        icon: Icons.person_pin,
        title: "Mother Tongue",
        value: partner.mothertoungue.isNotEmpty ? partner.mothertoungue : "Any",
        matched: matchesPreference(
          key: 'mother_tongue',
          preferenceValue: partner.mothertoungue,
          actualValue: personalDetail.motherTongue,
        ),
      ),
      PartnerPreferenceItem(
        icon: Icons.star,
        title: "Manglik",
        value: partner.manglik.isNotEmpty ? partner.manglik : "Any",
        matched: matchesPreference(
          key: 'manglik',
          preferenceValue: partner.manglik,
          actualValue: personalDetail.manglik,
        ),
      ),
      PartnerPreferenceItem(
        icon: Icons.school,
        title: "Qualification",
        value: partner.qualification.isNotEmpty ? partner.qualification : "Any",
        matched: matchesPreference(
          key: 'qualification',
          preferenceValue: partner.qualification,
          actualValue: personalDetail.degree,
        ),
      ),
      PartnerPreferenceItem(
        icon: Icons.work,
        title: "Profession",
        value: partner.proffession.isNotEmpty ? partner.proffession : "Any",
        matched: matchesPreference(
          key: 'profession',
          preferenceValue: partner.proffession,
          actualValue: personalDetail.occupationtype,
        ),
      ),
      PartnerPreferenceItem(
        icon: Icons.attach_money,
        title: "Annual Income",
        value: partner.annualincome.isNotEmpty ? partner.annualincome : "Any",
        matched: matchesPreference(
          key: 'annual_income',
          preferenceValue: partner.annualincome,
          actualValue: personalDetail.annualincome,
        ),
      ),
      PartnerPreferenceItem(
        icon: Icons.local_bar,
        title: "Drink",
        value: partner.drinkaccept.isNotEmpty ? partner.drinkaccept : "Any",
        matched: matchesPreference(
          key: 'drink',
          preferenceValue: partner.drinkaccept,
          actualValue: lifestyle.drinks,
        ),
      ),
      PartnerPreferenceItem(
        icon: Icons.smoking_rooms,
        title: "Smoke",
        value: partner.smokeaccept.isNotEmpty ? partner.smokeaccept : "Any",
        matched: matchesPreference(
          key: 'smoke',
          preferenceValue: partner.smokeaccept,
          actualValue: lifestyle.smoke,
        ),
      ),
    ];

    return UserProfile(
      profileResponse: response,
      contactInfo: contactInfo,
      photoAlbumUrls: photoAlbumUrls,
      personalDetails: personalDetails,
      communityDetails: communityDetails,
      educationCareerDetails: educationCareerDetails,
      lifeStyleDetails: lifeStyleDetails,
      partnerPreferences: partnerPreferences,
      otherMatchedProfiles: [],
    );
  }

  /// Method to update profile with new response data
  void updateFromResponse(ProfileResponse newResponse) {
    final newProfile = UserProfile.fromResponse(newResponse);
    profileResponse = newResponse;
    contactInfo = newProfile.contactInfo;
    photoAlbumUrls = newProfile.photoAlbumUrls;
    personalDetails = newProfile.personalDetails;
    communityDetails = newProfile.communityDetails;
    educationCareerDetails = newProfile.educationCareerDetails;
    lifeStyleDetails = newProfile.lifeStyleDetails;
    partnerPreferences = newProfile.partnerPreferences;
    otherMatchedProfiles = newProfile.otherMatchedProfiles;

    notifyListeners();
  }

  void updateProfileData(
    ProfileResponse newResponse,
    List<MatchedProfile> matchedProfiles,
  ) {
    final newProfile = UserProfile.fromResponse(newResponse);
    profileResponse = newResponse;
    contactInfo = newProfile.contactInfo;
    photoAlbumUrls = newProfile.photoAlbumUrls;
    personalDetails = newProfile.personalDetails;
    communityDetails = newProfile.communityDetails;
    educationCareerDetails = newProfile.educationCareerDetails;
    lifeStyleDetails = newProfile.lifeStyleDetails;
    partnerPreferences = newProfile.partnerPreferences;
    otherMatchedProfiles = matchedProfiles;

    notifyListeners();
  }

  /// Factory constructor for empty profile
  factory UserProfile.empty() {
    return UserProfile(
      profileResponse: null,
      contactInfo: [],
      photoAlbumUrls: [],
      personalDetails: [],
      communityDetails: [],
      educationCareerDetails: [],
      lifeStyleDetails: [],
      partnerPreferences: [],
      otherMatchedProfiles: [],
    );
  }
}
