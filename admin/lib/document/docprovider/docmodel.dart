import 'package:adminmrz/config/app_endpoints.dart';

class Document {
  final int userId;
  final String email;
  final String firstName;
  final String lastName;
  final String gender;
  final int isVerified;
  final int documentId;
  final String documentType;
  final String documentIdNumber;
  final String photo;
  final String status;
  final String rejectReason;

  Document({
    required this.userId,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.gender,
    required this.isVerified,
    required this.documentId,
    required this.documentType,
    required this.documentIdNumber,
    required this.photo,
    required this.status,
    required this.rejectReason,
  });

  factory Document.fromJson(Map<String, dynamic> json) {
    return Document(
      userId: json['user_id'] ?? 0,
      email: json['email'] ?? '',
      firstName: json['firstName'] ?? '',
      lastName: json['lastName'] ?? '',
      gender: json['gender'] ?? '',
      isVerified: json['isVerified'] ?? 0,
      documentId: json['document_id'] ?? 0,
      documentType: json['documenttype'] ?? '',
      documentIdNumber: json['documentidnumber'] ?? '',
      photo: json['photo'] ?? '',
      status: json['status'] ?? 'not_uploaded',
      rejectReason: json['reject_reason'] ?? '',
    );
  }

  String get fullName => '$firstName $lastName';

  String get fullPhotoUrl {
    final raw = photo.trim();
    if (raw.isEmpty) return raw;

    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      final uri = Uri.tryParse(raw);
      if (uri != null && uri.path.contains('/Api2/')) {
        final api2 = Uri.parse(kAdminApi2BaseUrl);
        final suffix = uri.path.split('/Api2/').last;
        final normalizedBase = api2.toString().replaceFirst(RegExp(r'/$'), '');
        final normalizedPath = suffix.startsWith('/')
            ? suffix.substring(1)
            : suffix;
        if (uri.host != api2.host || !uri.path.startsWith(api2.path)) {
          return '$normalizedBase/$normalizedPath';
        }
      }
      return raw;
    }

    final normalizedBase = kAdminApi2BaseUrl.replaceFirst(RegExp(r'/$'), '');
    final normalizedPath = raw.startsWith('Api2/')
        ? raw.substring('Api2/'.length)
        : raw.startsWith('/')
        ? raw.substring(1)
        : raw;
    return '$normalizedBase/$normalizedPath';
  }

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
}
