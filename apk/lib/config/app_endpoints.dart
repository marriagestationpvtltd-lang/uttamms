const String kDefaultServerHost = '192.168.18.208';

const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://$kDefaultServerHost/uttamms/Backend',
);

const String kSocketServerBaseUrl = String.fromEnvironment(
  'SOCKET_SERVER_URL',
  defaultValue: 'http://$kDefaultServerHost:3001',
);

const String kApi2BaseUrl = '$kApiBaseUrl/Api2';
const String kApi3BaseUrl = '$kApiBaseUrl/Api3';
const String kApi9BaseUrl = '$kApiBaseUrl/api9';
const String kRequestBaseUrl = '$kApiBaseUrl/request';
const String kAdminBaseUrl = '$kApiBaseUrl/admin';

// ---------------------------------------------------------------------------
// App-side API endpoints
// ---------------------------------------------------------------------------

/// Proposals
const String kEndpointProposals = '$kApi2BaseUrl/proposals_api.php';
const String kEndpointSendRequest = '$kApi2BaseUrl/send_request.php';
const String kEndpointAcceptProposal = '$kApi2BaseUrl/accept_proposal.php';
const String kEndpointRejectProposal = '$kApi2BaseUrl/reject_proposal.php';
const String kEndpointDeleteProposal = '$kApi2BaseUrl/delete_proposal.php';

/// Activity logging (fire-and-forget)
const String kEndpointLogActivity = '$kApi2BaseUrl/log_activity.php';

/// Call settings
const String kEndpointCallSettings = '$kApi2BaseUrl/call_settings.php';
const String kEndpointUploadCustomTone = '$kApi2BaseUrl/upload_custom_tone.php';
const String kEndpointUploadCallTone = '$kApi9BaseUrl/upload_call_tone.php';
const String kEndpointGetCallRingtone = '$kApi2BaseUrl/get_call_ringtone.php';

/// Profile dropdown master — returns option lists for dynamic fields.
const String kEndpointProfileFieldOptions =
    '$kApi2BaseUrl/get_profile_field_options.php';

/// Story / Reel (short-video ecosystem)
const String kEndpointReelFeed = '$kApi2BaseUrl/reel_feed.php';
const String kEndpointUploadReel = '$kApi2BaseUrl/upload_reel.php';
const String kEndpointUploadStory = '$kApi2BaseUrl/upload_story.php';
const String kEndpointUserStories = '$kApi2BaseUrl/get_user_stories.php';
const String kEndpointUpdateReelPrivacy =
    '$kApi2BaseUrl/reel_update_privacy.php';
const String kEndpointDeleteReel = '$kApi2BaseUrl/reel_delete.php';
const String kEndpointUpdateStoryPrivacy =
    '$kApi2BaseUrl/story_update_privacy.php';
const String kEndpointDeleteStory = '$kApi2BaseUrl/story_delete.php';
const String kEndpointReactReel = '$kApi2BaseUrl/reel_react.php';
const String kEndpointCommentReel = '$kApi2BaseUrl/reel_comment.php';
const String kEndpointShareReel = '$kApi2BaseUrl/reel_share.php';
const String kEndpointReportReel = '$kApi2BaseUrl/reel_report.php';
const String kEndpointViewReel = '$kApi2BaseUrl/reel_view.php';

// ---------------------------------------------------------------------------
// Admin API endpoints
// ---------------------------------------------------------------------------

const String kAdminEndpointUserActivity = '$kAdminBaseUrl/user_activity.php';
const String kAdminEndpointRingtones = '$kAdminBaseUrl/ringtones.php';
const String kAdminEndpointUploadRingtone =
    '$kAdminBaseUrl/upload_ringtone.php';
