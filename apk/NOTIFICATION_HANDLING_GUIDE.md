# Notification Handling Guide

## Overview

This guide documents the notification handling system for video calls, audio calls, and messages in the application.

## Notification Type Classification

### Type 1: Real-time Interactive Notifications
**Purpose**: Require immediate user action

**Types**:
- `call` - Incoming audio call
- `video_call` - Incoming video call

**Behavior**:
- **Foreground**: Full-screen call UI opens via CallOverlayWrapper, no notification banner shown
- **Background**: Full notification with Accept/Decline action buttons
- **iOS**: Uses CallKit for native call experience
- **Android**: Full-screen intent notification with custom actions
- **Channel**: `calls_channel` (Max importance)
- **Sound/Vibration**: Always enabled
- **Priority**: Maximum

### Type 2: Silent Data Messages
**Purpose**: Update app state without user alert

**Types**:
- `call_response` - Call accepted/rejected response
- `video_call_response` - Video call accepted/rejected response
- `call_ended` - Call ended by either party
- `video_call_ended` - Video call ended
- `call_cancelled` - Call cancelled before answer
- `video_call_cancelled` - Video call cancelled before answer
- `missed_call` - Missed call notification (backend only)
- `missed_video_call` - Missed video call notification (backend only)

**Behavior**:
- **All States**: No visual notification shown
- **Foreground**: Updates call screen UI directly via streams
- **Background**: Recorded in notification inbox only
- **Channel**: None (no notification displayed)
- **Sound/Vibration**: Disabled
- **Priority**: N/A (silent)

**Important**: Backend should send these as data-only messages (no `notification` payload key)

### Type 3: Context-Aware Notifications
**Purpose**: Show notifications based on user context

**Types**:
- `chat_message` - Chat message received
- `chat` - Legacy chat notification

**Behavior**:
- **Foreground + User viewing that chat**: No notification (suppressed)
- **Foreground + User on different screen**: Standard notification banner
- **Background/Terminated**: Full notification
- **Channel**: `messages_channel` (High importance)
- **Sound/Vibration**: Enabled
- **Priority**: High

**Context Detection**:
- Uses `ScreenStateManager` to track active chat
- Checks if user is chatting with the sender
- Considers app lifecycle state (foreground/background)

### Type 4: Standard Notifications
**Purpose**: Always show notification

**Types**:
- `request` - Profile request received
- `request_accepted` - Request accepted
- `request_rejected` - Request rejected
- `profile_view` - Profile viewed by another user

**Behavior**:
- **All States**: Show notification
- **Channel**: `general_notifications` (Default importance)
- **Sound/Vibration**: Enabled
- **Priority**: Default

## Notification Channels (Android)

### 1. Calls Channel
- **ID**: `calls_channel`
- **Name**: Calls
- **Importance**: Max
- **Features**: Full-screen intent, vibration pattern, LED lights
- **Use**: Incoming call/video call notifications

### 2. Messages Channel
- **ID**: `messages_channel`
- **Name**: Messages
- **Importance**: High
- **Features**: Sound, vibration, badge
- **Use**: Chat message notifications

### 3. General Channel
- **ID**: `general_notifications`
- **Name**: General Notifications
- **Importance**: Default
- **Features**: Sound, badge
- **Use**: Requests, profile views, etc.

## Implementation Details

### Background Handler (`firebaseBackgroundHandler`)
Located in: `lib/main.dart`

**Responsibilities**:
1. Initialize Firebase
2. Trigger call response streams
3. Trigger incoming call streams
4. Record notification in inbox
5. Filter silent notifications (Type 2)
6. Show call notifications (Type 1)
7. Show standard notifications (Type 3 & 4)

**Key Logic**:
```dart
// Silent types are filtered out
const silentTypes = {
  'call_response', 'video_call_response',
  'call_ended', 'video_call_ended',
  'call_cancelled', 'video_call_cancelled',
  'missed_call', 'missed_video_call',
};

if (silentTypes.contains(type)) {
  return; // No notification shown
}
```

### Foreground Handler (`FirebaseMessaging.onMessage`)
Located in: `lib/main.dart`

**Responsibilities**:
1. Record notification in inbox
2. Trigger call streams
3. Handle incoming calls (Type 1)
4. Filter silent notifications (Type 2)
5. Apply chat context awareness (Type 3)
6. Show standard notifications (Type 3 & 4)

**Key Logic**:
```dart
// Type 1: Incoming calls - UI handled by CallOverlayWrapper
if (type == 'call' || type == 'video_call') {
  NotificationService.triggerIncomingCall(data);
  return; // No banner notification
}

// Type 2: Silent notifications
if (silentTypes.contains(type)) {
  return; // No notification
}

// Type 3: Context-aware chat notifications
if (type == 'chat_message' || type == 'chat') {
  if (!shouldShowChatNotification(data)) {
    return; // Suppress if viewing chat
  }
}
```

### Screen State Manager
Located in: `lib/Chat/screen_state_manager.dart`

**Features**:
- Tracks active chat room and partner
- Tracks app lifecycle state
- Provides `shouldShowChatNotification()` helper

**Usage**:
```dart
// When chat screen opens
ScreenStateManager().onChatScreenOpened(
  chatRoomId,
  userId,
  partnerUserId: partnerId
);

// When chat screen closes
ScreenStateManager().onChatScreenClosed();

// Check if notification should be shown
if (!shouldShowChatNotification(data)) {
  return; // Suppress notification
}
```

### iOS Foreground Notifications
Located in: `lib/main.dart` - `setupFirebaseMessaging()`

**Configuration**:
```dart
await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
  alert: true,  // Enable alerts
  badge: true,  // Update badge count
  sound: true,  // Play sound
);
```

This allows important notifications (calls) to alert the user even when app is in foreground.

## Backend Requirements

### Data-Only Messages (Type 2 - Silent)
For silent notifications, send **data-only** payload:

```php
$message = [
  'data' => [
    'type' => 'call_response',
    'accepted' => 'true',
    'recipientUid' => '123',
    // ... other data
  ],
  // NO 'notification' key
];
```

### Regular Messages (Type 1, 3, 4)
For regular notifications, include both `notification` and `data`:

```php
$message = [
  'notification' => [
    'title' => 'Incoming Call',
    'body' => 'John is calling you',
  ],
  'data' => [
    'type' => 'call',
    'callerId' => '456',
    // ... other data
  ],
];
```

### Priority Configuration
```php
// High priority for calls and messages
'android' => [
  'priority' => 'high',
  'notification' => [
    'channel_id' => 'calls_channel', // or 'messages_channel'
  ]
],
'apns' => [
  'headers' => [
    'apns-priority' => '10' // High priority
  ]
]

// Normal priority for general notifications
'android' => ['priority' => 'normal'],
'apns' => ['headers' => ['apns-priority' => '5']]
```

## Testing Checklist

### Incoming Call Tests
- [ ] Incoming call (app foreground) - Full-screen UI opens, no banner
- [ ] Incoming call (app background) - Full notification with Accept/Decline
- [ ] Incoming video call (app foreground) - Full-screen UI opens
- [ ] Incoming video call (app background) - Full notification with buttons

### Silent Notification Tests
- [ ] Call accepted response - No notification shown, UI updates
- [ ] Call rejected response - No notification shown, UI updates
- [ ] Call ended - No notification shown
- [ ] Call cancelled - No notification shown
- [ ] Video call responses - Same as above for video

### Chat Message Tests
- [ ] Chat message (on that chat screen) - No notification
- [ ] Chat message (on different screen, foreground) - Banner shown
- [ ] Chat message (app background) - Full notification
- [ ] Chat message (app terminated) - Full notification

### Standard Notification Tests
- [ ] Profile request (foreground) - Notification shown
- [ ] Profile request (background) - Full notification
- [ ] Request accepted - Notification shown
- [ ] Profile view - Notification shown

## Troubleshooting

### Issue: Silent notifications showing banner
**Solution**: Ensure backend sends data-only payload (no `notification` key)

### Issue: Chat notifications showing when on chat screen
**Solution**:
1. Verify `ScreenStateManager().onChatScreenOpened()` is called
2. Check partner user ID is correctly passed
3. Ensure `ScreenStateManager().onChatScreenClosed()` is called on exit

### Issue: Calls not showing in foreground
**Solution**: Check iOS foreground notification settings are enabled

### Issue: Wrong notification channel used
**Solution**: Verify notification type is correctly classified in `_displayStandardNotification()`

## File References

- **Main notification logic**: `/msfinal/lib/main.dart`
- **Notification service**: `/msfinal/lib/pushnotification/pushservice.dart`
- **Screen state manager**: `/msfinal/lib/Chat/screen_state_manager.dart`
- **Call overlay**: `/msfinal/lib/Chat/call_overlay_manager.dart`
- **Notification inbox**: `/msfinal/lib/Notification/notification_inbox_service.dart`

## Memory Storage

Key facts stored in repository memory:
- Silent notification types should never show visual alerts
- Chat notifications use context-aware suppression
- iOS foreground notifications enabled for important alerts
- Three notification channels: calls (max), messages (high), general (default)
