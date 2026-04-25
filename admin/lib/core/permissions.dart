import 'package:adminmrz/auth/service.dart';

// Role constants matching the backend admins table
class AdminRole {
  static const String superAdmin = 'super_admin';
  static const String moderator  = 'moderator';
  static const String support    = 'support';
}

// Permissions by feature
class AdminPermissions {
  final String role;

  AdminPermissions(this.role);

  bool get canVerifyDocuments => role == AdminRole.superAdmin || role == AdminRole.moderator;
  bool get canManagePayments  => role == AdminRole.superAdmin;
  bool get canManagePackages  => role == AdminRole.superAdmin;
  bool get canAccessChats     => role == AdminRole.superAdmin || role == AdminRole.moderator || role == AdminRole.support;
  bool get canManageUsers     => role == AdminRole.superAdmin || role == AdminRole.moderator;
  bool get canManageRequests  => role == AdminRole.superAdmin || role == AdminRole.moderator;
  bool get canViewDashboard   => true; // all roles
  bool get canManageSettings  => role == AdminRole.superAdmin;
  bool get canViewActivities  => role == AdminRole.superAdmin || role == AdminRole.moderator;
  bool get canMonitorMessages => role == AdminRole.superAdmin || role == AdminRole.moderator;

  static AdminPermissions fromRole(String? role) {
    return AdminPermissions(role ?? AdminRole.support);
  }
}

extension AuthProviderPermissions on AuthProvider {
  String get adminRole => (adminData?['role'] as String?) ?? AdminRole.support;
  AdminPermissions get permissions => AdminPermissions.fromRole(adminRole);
}
