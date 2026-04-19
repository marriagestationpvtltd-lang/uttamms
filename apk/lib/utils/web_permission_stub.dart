/// Web stub for permission_handler.
///
/// On web, permissions are managed by the browser — we provide no-op stubs
/// so that code that references `Permission.microphone.request()` compiles
/// without errors.  The actual permission prompt on web is triggered
/// automatically by getUserMedia() when the audio recorder or Agora SDK
/// requests the microphone/camera.
library web_permission_stub;

// ignore_for_file: avoid_classes_with_only_static_members

enum PermissionStatus {
  denied,
  granted,
  restricted,
  limited,
  permanentlyDenied,
  provisional,
}

extension PermissionStatusExtension on PermissionStatus {
  bool get isGranted => this == PermissionStatus.granted;
  bool get isDenied => this == PermissionStatus.denied;
  bool get isPermanentlyDenied => this == PermissionStatus.permanentlyDenied;
  bool get isRestricted => this == PermissionStatus.restricted;
}

class Permission {
  const Permission._(this._name);
  final String _name;

  static const Permission microphone = Permission._('microphone');
  static const Permission camera = Permission._('camera');
  static const Permission storage = Permission._('storage');
  static const Permission photos = Permission._('photos');
  static const Permission location = Permission._('location');

  /// On web, always returns [PermissionStatus.granted] since the browser
  /// handles its own permission prompt.
  Future<PermissionStatus> request() async => PermissionStatus.granted;

  Future<PermissionStatus> get status async => PermissionStatus.granted;

  @override
  String toString() => 'Permission($_name)';
}

/// No-op on web — opens browser settings is not possible from a web app.
Future<bool> openAppSettings() async => false;
