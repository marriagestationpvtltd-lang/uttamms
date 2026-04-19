/// Data model for a marriage proposal / connection request.
///
/// Fields map 1-to-1 with the JSON returned by the backend
/// `proposals_api.php` endpoint, including the two fields that
/// were added to align the back-end with this front-end model:
///
/// - [privacy]      – privacy setting of the OTHER user (the profile being shown).
///                    Comes from `users.privacy` via a JOIN in the backend query.
/// - [photoRequest] – status of the Photo-type request between the two users
///                    (may differ from [requestType] when the current proposal
///                    is a Chat or Profile request).
///                    Populated via a LEFT JOIN on the `proposals` table in the backend.
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

  /// Privacy setting of the OTHER user shown in the card.
  /// Populated from `users.privacy` in the backend JOIN.
  final String? privacy;

  /// Status of the Photo-type request between the two users.
  /// Populated from a LEFT JOIN on the `proposals` table in the backend.
  final String? photoRequest;

  const ProposalModel({
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

  /// Deserialise from a JSON map returned by `proposals_api.php`.
  factory ProposalModel.fromJson(Map<String, dynamic> json) {
    return ProposalModel(
      proposalId:     json['proposalId']?.toString(),
      senderId:       json['senderId']?.toString(),
      receiverId:     json['receiverId']?.toString(),
      requestType:    json['requestType']?.toString(),
      status:         json['status']?.toString(),
      firstName:      json['firstName']?.toString(),
      lastName:       json['lastName']?.toString(),
      profilePicture: json['profilePicture']?.toString(),
      verified:       json['verified'] == true,
      occupation:     json['occupation']?.toString(),
      city:           json['city']?.toString(),
      maritalstatus:  json['maritalstatus']?.toString(),
      memberid:       json['memberid']?.toString() ?? '',
      type:           json['type']?.toString(),
      privacy:        json['privacy']?.toString(),
      photoRequest:   json['photo_request']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'proposalId':     proposalId,
    'senderId':       senderId,
    'receiverId':     receiverId,
    'requestType':    requestType,
    'status':         status,
    'firstName':      firstName,
    'lastName':       lastName,
    'profilePicture': profilePicture,
    'verified':       verified,
    'occupation':     occupation,
    'city':           city,
    'maritalstatus':  maritalstatus,
    'memberid':       memberid,
    'type':           type,
    'privacy':        privacy,
    'photo_request':  photoRequest,
  };

  @override
  String toString() =>
      'ProposalModel(proposalId: $proposalId, requestType: $requestType, '
      'status: $status, privacy: $privacy, photoRequest: $photoRequest)';
}
