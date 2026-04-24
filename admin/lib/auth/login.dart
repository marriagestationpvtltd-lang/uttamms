import 'package:adminmrz/auth/service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// ─── Design tokens (match dashboard.dart) ────────────────────────────────────
const _kAccent        = Color(0xFF6366F1);
const _kAccentDark    = Color(0xFF4F46E5);
const _kAccentViolet  = Color(0xFF8B5CF6);
const _kDarkBg        = Color(0xFF0F172A);
const _kDarkSurface   = Color(0xFF1E293B);
const _kTextPrimary   = Color(0xFF0F172A);
const _kTextSecondary = Color(0xFF475569);
const _kBorder        = Color(0xFFE2E8F0);
const _kError         = Color(0xFFEF4444);

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey           = GlobalKey<FormState>();
  final _emailController   = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword    = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ─── Input decoration ────────────────────────────────────────────────────────
  InputDecoration _inputDeco({required String label, required IconData icon}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 13, color: _kTextSecondary),
      prefixIcon: Icon(icon, size: 18, color: _kTextSecondary),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _kBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _kBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _kAccent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _kError),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _kError, width: 1.5),
      ),
    );
  }

  // ─── Form ────────────────────────────────────────────────────────────────────
  Widget _buildForm(AuthProvider authProvider) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Welcome back',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: _kTextPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Sign in to your admin account',
            style: TextStyle(fontSize: 14, color: _kTextSecondary),
          ),
          const SizedBox(height: 28),
          // Email
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: _inputDeco(
              label: 'Email address',
              icon: Icons.email_outlined,
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Please enter your email';
              if (!v.contains('@')) return 'Please enter a valid email';
              return null;
            },
          ),
          const SizedBox(height: 14),
          // Password
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: _inputDeco(
              label: 'Password',
              icon: Icons.lock_outline_rounded,
            ).copyWith(
              suffixIcon: IconButton(
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 18,
                  color: _kTextSecondary,
                ),
                padding: EdgeInsets.zero,
                tooltip: _obscurePassword ? 'Show password' : 'Hide password',
              ),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Please enter your password';
              return null;
            },
          ),
          // Error banner
          if (authProvider.error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFCA5A5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      size: 16, color: _kError),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      authProvider.error!,
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFFDC2626)),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 22),
          // Sign-in button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: authProvider.isLoading
                  ? null
                  : () async {
                      if (_formKey.currentState!.validate()) {
                        final success = await authProvider.login(
                          _emailController.text.trim(),
                          _passwordController.text.trim(),
                        );
                        if (!success && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  authProvider.error ?? 'Login failed'),
                              backgroundColor: _kError,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: _kAccent,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _kAccent.withOpacity(0.55),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: authProvider.isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Text(
                      'Sign In',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Text(
              '© ${DateTime.now().year} Marriage Station',
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFFB0BAC4)),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Compact layout (narrow screens) ─────────────────────────────────────────
  Widget _buildCompactLayout(AuthProvider authProvider) {
    return Container(
      width: 420,
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.fromLTRB(40, 40, 40, 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.28),
            blurRadius: 48,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Logo mark
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_kAccent, _kAccentViolet],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: _kAccent.withOpacity(0.38),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(Icons.favorite_rounded,
                color: Colors.white, size: 24),
          ),
          const SizedBox(height: 18),
          const Text(
            'Marriage Station',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: _kTextPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Admin Panel',
            style: TextStyle(fontSize: 13, color: _kTextSecondary),
          ),
          const SizedBox(height: 30),
          _buildForm(authProvider),
        ],
      ),
    );
  }

  // ─── Wide layout (desktop) ────────────────────────────────────────────────────
  Widget _buildWideLayout(AuthProvider authProvider) {
    return Container(
      width: 900,
      height: 560,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.38),
            blurRadius: 64,
            offset: const Offset(0, 24),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Row(
          children: [
            // ── Left branding panel ──────────────────────────────────────────
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(48),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_kAccentDark, _kAccentViolet],
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.20)),
                      ),
                      child: const Icon(Icons.favorite_rounded,
                          color: Colors.white, size: 28),
                    ),
                    const SizedBox(height: 30),
                    const Text(
                      'Marriage\nStation',
                      style: TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.1,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Admin Dashboard',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withOpacity(0.72),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 36),
                    ...[
                      'Manage members & profiles',
                      'Document verification',
                      'Payment tracking',
                      'Chat & call management',
                    ].map(
                      (f) => Padding(
                        padding: const EdgeInsets.only(bottom: 11),
                        child: Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.55),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              f,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white.withOpacity(0.68),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // ── Right form panel ─────────────────────────────────────────────
            Expanded(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 48, vertical: 44),
                child: _buildForm(authProvider),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 960;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_kDarkBg, Color(0xFF1E1B4B)],
          ),
        ),
        child: Stack(
          children: [
            // Decorative blobs
            Positioned(
              top: -90,
              left: -90,
              child: Container(
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _kAccent.withOpacity(0.08),
                ),
              ),
            ),
            Positioned(
              bottom: -70,
              right: -70,
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _kAccentViolet.withOpacity(0.08),
                ),
              ),
            ),
            // Main card
            Center(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: isWide
                      ? _buildWideLayout(authProvider)
                      : _buildCompactLayout(authProvider),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}