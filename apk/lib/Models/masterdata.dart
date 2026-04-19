class UserMasterData {
  final int id;
  final String email;
  final String firstName;
  final String lastName;
  final String profilePicture; // full relative path returned by PHP
  final String usertype;
  final int pageno;
  final String createdDate;
  final String docStatus; // new field from PHP


  UserMasterData({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.profilePicture,
    required this.usertype,
    required this.pageno,
    required this.createdDate,
    required this.docStatus,

  });

  factory UserMasterData.fromJson(Map<String, dynamic> json) {
    return UserMasterData(
      id: json['id'],
      email: json['email'] ?? '',
      firstName: json['firstName'] ?? '',
      lastName: json['lastName'] ?? '',
      profilePicture: json['profile_picture'] ?? '',
      usertype: json['usertype'] ?? 'free',
      pageno: json['pageno'] ?? 0,
      createdDate: json['createdDate'] ?? '',
      docStatus: json['docstatus']

    );
  }
}
