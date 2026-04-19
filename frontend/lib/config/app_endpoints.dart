const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://digitallami.com',
);

const String kApi2BaseUrl  = '$kApiBaseUrl/Api2';
const String kAdminBaseUrl = '$kApiBaseUrl/admin';

// ---------------------------------------------------------------------------
// App-side API endpoints
// ---------------------------------------------------------------------------

/// Proposals
const String kEndpointProposals      = '$kApi2BaseUrl/proposals_api.php';
const String kEndpointSendRequest    = '$kApi2BaseUrl/send_request.php';
const String kEndpointAcceptProposal = '$kApi2BaseUrl/accept_proposal.php';
const String kEndpointRejectProposal = '$kApi2BaseUrl/reject_proposal.php';
const String kEndpointDeleteProposal = '$kApi2BaseUrl/delete_proposal.php';

/// Activity logging (fire-and-forget)
const String kEndpointLogActivity = '$kApi2BaseUrl/log_activity.php';

/// Call settings
const String kEndpointCallSettings     = '$kApi2BaseUrl/call_settings.php';
const String kEndpointUploadCustomTone = '$kApi2BaseUrl/upload_custom_tone.php';
const String kEndpointGetCallRingtone  = '$kApi2BaseUrl/get_call_ringtone.php';

// ---------------------------------------------------------------------------
// Admin API endpoints
// ---------------------------------------------------------------------------

const String kAdminEndpointUserActivity    = '$kAdminBaseUrl/user_activity.php';
const String kAdminEndpointRingtones       = '$kAdminBaseUrl/ringtones.php';
const String kAdminEndpointUploadRingtone  = '$kAdminBaseUrl/upload_ringtone.php';
