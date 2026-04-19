class ProposalModel {
  final String? proposalId;
  final String? senderId;
  final String? receiverId;
  final String? requestType;
  final String? status;
  final String? firstName;
  final String? lastName;
  final String? profilePicture;
  final bool? verified;
  final String? occupation;
  final String? city;
  final String? maritalstatus;
  final String? memberid;
  final String? type;
  final String? privacy;
  final String? photoRequest;

  ProposalModel({
    this.proposalId,
    this.senderId,
    this.receiverId,
    this.requestType,
    this.status,
    this.firstName,
    this.lastName,
    this.profilePicture,
    this.verified,
    this.occupation,
    this.city,
    this.maritalstatus,
    this.memberid,
    this.type,
    this.privacy,
    this.photoRequest,
  });

  factory ProposalModel.fromJson(Map<String, dynamic> json) {
    return ProposalModel(
      proposalId: json['proposalId']?.toString(),
      senderId: json['senderId']?.toString(),
      receiverId: json['receiverId']?.toString(),
      requestType: json['requestType'],
      status: json['status'],
      firstName: json['firstName'],
      lastName: json['lastName'],
      profilePicture: json['profilePicture'], // Now matches API
      verified: json['verified'] == true,
      occupation: json['occupation'],
      city: json['city'],
      maritalstatus: json['maritalstatus'],
      memberid: json['memberid'] ?? '',
      type: json['type'],
      privacy: json['privacy'],
      photoRequest: json['photo_request'],
    );
  }

  Map<String, dynamic> toJson() => {
    'proposalId': proposalId,
    'senderId': senderId,
    'receiverId': receiverId,
    'requestType': requestType,
    'status': status,
    'firstName': firstName,
    'lastName': lastName,
    'profilePicture': profilePicture,
    'verified': verified,
    'occupation': occupation,
    'city': city,
    'maritalstatus': maritalstatus,
    'memberid': memberid,
    'type': type,
    'privacy': privacy,
    'photo_request': photoRequest,
  };
}