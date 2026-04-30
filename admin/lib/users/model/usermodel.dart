import 'package:flutter/material.dart';

class UserListResponse {
  bool success;
  int count;
  List<User> data;

  UserListResponse({
    required this.success,
    required this.count,
    required this.data,
  });

  factory UserListResponse.fromJson(Map<String, dynamic> json) {
    return UserListResponse(
      success: json['success'] ?? false,
      count: json['count'] ?? 0,
      data: List<User>.from((json['data'] ?? []).map((x) => User.fromJson(x))),
    );
  }
}

class User {
  int id;
  String firstName;
  String lastName;
  String email;
  int isVerified;
  String status;
  String privacy;
  String usertype;
  String lastLogin;
  String? profilePicture;
  int isOnline;
  int isActive;
  int? pageno;
  String gender;
  String? registrationDate;
  String? expiryDate;
  String? paymentStatus;
  String? phone;
  int phoneVerified;
  int emailVerified;

  static String? _sanitizeProfilePicture(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty || value == 'null') return null;
    final lower = value.toLowerCase();
    if (lower.endsWith('/default.png') || lower.endsWith('default.png')) {
      return null;
    }
    return value;
  }

  User({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.isVerified,
    required this.status,
    required this.privacy,
    required this.usertype,
    required this.lastLogin,
    this.profilePicture,
    required this.isOnline,
    required this.isActive,
    this.pageno,
    required this.gender,
    this.registrationDate,
    this.expiryDate,
    this.paymentStatus,
    this.phone,
    required this.phoneVerified,
    required this.emailVerified,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] is int
          ? json['id']
          : int.tryParse(json['id'].toString()) ?? 0,
      firstName: json['firstName']?.toString() ?? '',
      lastName: json['lastName']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      isVerified: json['isVerified'] is int ? json['isVerified'] : 0,
      status: json['status']?.toString() ?? 'pending',
      privacy: json['privacy']?.toString() ?? 'private',
      usertype: json['usertype']?.toString() ?? 'free',
      lastLogin: json['lastLogin']?.toString() ?? '',
      profilePicture: _sanitizeProfilePicture(
        json['profile_picture']?.toString(),
      ),
      isOnline: json['isOnline'] is int ? json['isOnline'] : 0,
      isActive: json['isActive'] is int ? json['isActive'] : 1,
      pageno: json['pageno'] is int ? json['pageno'] : null,
      gender: json['gender']?.toString() ?? 'Male',
      registrationDate:
          json['registration_date']?.toString() ??
          json['created_at']?.toString() ??
          json['registrationDate']?.toString(),
      expiryDate:
          json['expiry_date']?.toString() ??
          json['subscription_expiry']?.toString() ??
          json['expiryDate']?.toString(),
      paymentStatus:
          json['payment_status']?.toString() ??
          json['paymentStatus']?.toString(),
      phone:
          json['phone']?.toString() ??
          json['mobile']?.toString() ??
          json['phone_number']?.toString(),
      phoneVerified: json['phone_verified'] is int
          ? json['phone_verified']
          : (json['phoneVerified'] is int ? json['phoneVerified'] : 0),
      emailVerified: json['email_verified'] is int
          ? json['email_verified']
          : (json['emailVerified'] is int
                ? json['emailVerified']
                : (json['isVerified'] is int ? json['isVerified'] : 0)),
    );
  }

  String get fullName => '$firstName $lastName';

  bool get hasProfilePicture {
    final pic = profilePicture?.trim();
    if (pic == null || pic.isEmpty || pic == 'null') return false;
    final lower = pic.toLowerCase();
    // Backend may send default placeholders that are not real user photos.
    if (lower.endsWith('/default.png') || lower.endsWith('default.png')) {
      return false;
    }
    return true;
  }

  String get formattedStatus {
    return status.replaceAll('_', ' ').toUpperCase();
  }

  Color get statusColor {
    switch (status.toLowerCase()) {
      case 'approved':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'rejected':
        return Colors.red;
      case 'not_uploaded':
        return Colors.grey;
      default:
        return Colors.blue;
    }
  }
}
