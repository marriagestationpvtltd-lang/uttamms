import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:ms2026/constant/app_colors.dart';
import 'package:ms2026/constant/app_dimensions.dart';
import 'package:ms2026/constant/app_text_styles.dart';
import 'package:ms2026/config/app_endpoints.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({Key? key}) : super(key: key);

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

enum ForgotStep { email, otp, reset }

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  ForgotStep step = ForgotStep.email;

  final emailController = TextEditingController();
  final otpController = TextEditingController();
  final passwordController = TextEditingController();

  bool loading = false;

  // Validation error states
  Map<String, bool> _fieldErrors = {
    'email': false,
    'otp': false,
    'password': false,
  };

  // Track which fields have been touched
  Map<String, bool> _fieldTouched = {
    'email': false,
    'otp': false,
    'password': false,
  };

  // Focus nodes
  final Map<String, FocusNode> _focusNodes = {
    'email': FocusNode(),
    'otp': FocusNode(),
    'password': FocusNode(),
  };

  @override
  void initState() {
    super.initState();
    // Initialize focus nodes
    _focusNodes.forEach((key, node) {
      node.addListener(() {
        if (!node.hasFocus) {
          setState(() {
            _fieldTouched[key] = true;
          });
        }
      });
    });
  }

  @override
  void dispose() {
    _focusNodes.forEach((key, node) => node.dispose());
    emailController.dispose();
    otpController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  bool _hasError(String fieldName) {
    return _fieldErrors[fieldName] ?? false;
  }

  bool _shouldShowError(String fieldName) {
    return _fieldTouched[fieldName] == true;
  }

  String _getErrorMessage(String fieldName) {
    switch (fieldName) {
      case 'email':
        return 'Email is required';
      case 'otp':
        return 'OTP is required';
      case 'password':
        if (passwordController.text.isEmpty) {
          return 'Password is required';
        } else if (passwordController.text.length < 6) {
          return 'Password must be at least 6 characters';
        }
        return 'Invalid password';
      default:
        return 'This field is required';
    }
  }

  // Get border color based on field state
  Color _getBorderColor(String fieldName) {
    String value = '';
    switch (fieldName) {
      case 'email':
        value = emailController.text;
        break;
      case 'otp':
        value = otpController.text;
        break;
      case 'password':
        value = passwordController.text;
        break;
    }

    if (_hasError(fieldName) && _shouldShowError(fieldName)) {
      return AppColors.error;
    }

    return value.isNotEmpty ? AppColors.success : AppColors.borderDark;
  }

  void showMessage(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppColors.error : AppColors.primary,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> sendOtp() async {
    // Validate email
    if (emailController.text.isEmpty) {
      setState(() {
        _fieldErrors['email'] = true;
        _fieldTouched['email'] = true;
      });
      return;
    }

    setState(() => loading = true);

    final url = Uri.parse('${kApiBaseUrl}/Api2/forgot_password_send_otp.php');
    final resp = await http.post(url, body: {'email': emailController.text.trim()});
    final data = json.decode(resp.body);

    setState(() => loading = false);

    if (data['success'] == true) {
      showMessage('OTP sent to email');
      setState(() {
        step = ForgotStep.otp;
        _fieldErrors['email'] = false;
      });
    } else {
      showMessage(data['message'] ?? 'Error sending OTP', isError: true);
      setState(() {
        _fieldErrors['email'] = true;
      });
    }
  }

  Future<void> verifyOtp() async {
    // Validate OTP
    if (otpController.text.isEmpty) {
      setState(() {
        _fieldErrors['otp'] = true;
        _fieldTouched['otp'] = true;
      });
      return;
    }

    setState(() => loading = true);

    final url = Uri.parse('${kApiBaseUrl}/Api2/forgot_password_verify_otp.php');
    final resp = await http.post(url, body: {
      'email': emailController.text.trim(),
      'otp': otpController.text.trim(),
    });
    final data = json.decode(resp.body);

    setState(() => loading = false);

    if (data['success'] == true) {
      showMessage('OTP verified');
      setState(() {
        step = ForgotStep.reset;
        _fieldErrors['otp'] = false;
      });
    } else {
      showMessage(data['message'] ?? 'OTP verification failed', isError: true);
      setState(() {
        _fieldErrors['otp'] = true;
      });
    }
  }

  Future<void> resetPassword() async {
    // Validate password
    if (passwordController.text.isEmpty || passwordController.text.length < 6) {
      setState(() {
        _fieldErrors['password'] = true;
        _fieldTouched['password'] = true;
      });
      return;
    }

    setState(() => loading = true);

    final url = Uri.parse('${kApiBaseUrl}/Api2/forgot_password_reset.php');
    final resp = await http.post(url, body: {
      'email': emailController.text.trim(),
      'password': passwordController.text.trim(),
    });
    final data = json.decode(resp.body);

    setState(() => loading = false);

    if (data['success'] == true) {
      showMessage('Password reset successful');
      Navigator.pop(context); // back to login
    } else {
      showMessage(data['message'] ?? 'Password reset failed', isError: true);
    }
  }

  Widget _buildTextField({
    required String fieldName,
    required TextEditingController controller,
    required String labelText,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    final bool hasError = _hasError(fieldName) && _shouldShowError(fieldName);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: AppDimensions.buttonHeightMD,
          padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingMD),
          decoration: BoxDecoration(
            borderRadius: AppDimensions.borderRadiusMD,
            border: Border.all(
              color: _getBorderColor(fieldName),
              width: 1.6,
            ),
          ),
          child: Row(
            children: [
              if (fieldName == 'email')
                Icon(
                  Icons.email,
                  color: hasError ? AppColors.error : AppColors.textPrimary,
                  size: AppDimensions.iconSizeSM,
                )
              else if (fieldName == 'otp')
                Icon(
                  Icons.lock_clock,
                  color: hasError ? AppColors.error : AppColors.textPrimary,
                  size: AppDimensions.iconSizeSM,
                )
              else if (fieldName == 'password')
                  Icon(
                    Icons.lock,
                    color: hasError ? AppColors.error : AppColors.textPrimary,
                    size: AppDimensions.iconSizeSM,
                  ),
              if (fieldName == 'email' || fieldName == 'otp' || fieldName == 'password')
                const SizedBox(width: AppDimensions.spacingSM),
              Expanded(
                child: TextField(
                  focusNode: _focusNodes[fieldName],
                  controller: controller,
                  keyboardType: keyboardType,
                  obscureText: obscureText,
                  style: AppTextStyles.bodyLarge,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: labelText,
                    hintStyle: AppTextStyles.bodyMedium.copyWith(
                      color: hasError
                          ? AppColors.error.withOpacity(0.7)
                          : AppColors.textHint,
                    ),
                    suffixIcon: suffixIcon,
                  ),
                  onChanged: (value) {
                    if (value.isNotEmpty && _hasError(fieldName)) {
                      setState(() {
                        _fieldErrors[fieldName] = false;
                      });
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(left: AppDimensions.spacingMD, top: AppDimensions.spacingXS),
            child: Text(
              _getErrorMessage(fieldName),
              style: AppTextStyles.caption.copyWith(color: AppColors.error),
            ),
          ),
      ],
    );
  }

  Widget _buildEmailStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: AppDimensions.spacingXXL),
        Text(
          "Forgot Password",
          style: AppTextStyles.heading1.copyWith(color: AppColors.primary),
        ),
        const SizedBox(height: AppDimensions.spacingSM),
        Text(
          "Enter your email address to receive OTP",
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppDimensions.spacingXXL),

        _buildTextField(
          fieldName: 'email',
          controller: emailController,
          labelText: 'Email Address*',
          keyboardType: TextInputType.emailAddress,
        ),

        const SizedBox(height: AppDimensions.spacingXL),

        // Send OTP button
        SizedBox(
          width: double.infinity,
          height: AppDimensions.buttonHeightMD,
          child: Container(
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: AppDimensions.borderRadiusMD,
            ),
            child: ElevatedButton(
              onPressed: loading ? null : sendOtp,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: AppDimensions.borderRadiusMD,
                ),
              ),
              child: loading
                  ? const SizedBox(
                height: AppDimensions.iconSizeMD,
                width: AppDimensions.iconSizeMD,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.white,
                ),
              )
                  : Text("Send OTP", style: AppTextStyles.whiteLabel),
            ),
          ),
        ),

        const SizedBox(height: AppDimensions.spacingMD),

        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: AppColors.primary),
          child: Text("Back to Login", style: AppTextStyles.primaryLabel),
        ),
      ],
    );
  }

  Widget _buildOtpStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: AppDimensions.spacingXXL),
        Text(
          "Verify OTP",
          style: AppTextStyles.heading1.copyWith(color: AppColors.primary),
        ),
        const SizedBox(height: AppDimensions.spacingSM),
        Text(
          "OTP sent to ${emailController.text}",
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppDimensions.spacingXXL),

        _buildTextField(
          fieldName: 'otp',
          controller: otpController,
          labelText: 'Enter OTP*',
          keyboardType: TextInputType.number,
        ),

        const SizedBox(height: AppDimensions.spacingXL),

        // Verify OTP button
        SizedBox(
          width: double.infinity,
          height: AppDimensions.buttonHeightMD,
          child: Container(
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: AppDimensions.borderRadiusMD,
            ),
            child: ElevatedButton(
              onPressed: loading ? null : verifyOtp,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: AppDimensions.borderRadiusMD,
                ),
              ),
              child: loading
                  ? const SizedBox(
                height: AppDimensions.iconSizeMD,
                width: AppDimensions.iconSizeMD,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.white,
                ),
              )
                  : Text("Verify OTP", style: AppTextStyles.whiteLabel),
            ),
          ),
        ),

        const SizedBox(height: AppDimensions.spacingMD),

        TextButton(
          onPressed: loading ? null : sendOtp,
          style: TextButton.styleFrom(foregroundColor: AppColors.primary),
          child: Text(
            loading ? "Resending..." : "Resend OTP",
            style: AppTextStyles.primaryLabel,
          ),
        ),

        TextButton(
          onPressed: () {
            setState(() {
              step = ForgotStep.email;
              otpController.clear();
              _fieldErrors['otp'] = false;
              _fieldTouched['otp'] = false;
            });
          },
          style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
          child: Text("Change Email", style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
        ),
      ],
    );
  }

  Widget _buildResetStep() {
    bool _passwordVisible = false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: AppDimensions.spacingXXL),
        Text(
          "Reset Password",
          style: AppTextStyles.heading1.copyWith(color: AppColors.primary),
        ),
        const SizedBox(height: AppDimensions.spacingSM),
        Text(
          "Create a new password for your account",
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppDimensions.spacingXXL),

        _buildTextField(
          fieldName: 'password',
          controller: passwordController,
          labelText: 'New Password*',
          obscureText: !_passwordVisible,
          suffixIcon: IconButton(
            icon: Icon(
              _passwordVisible ? Icons.visibility : Icons.visibility_off,
              color: (_hasError('password') && _shouldShowError('password'))
                  ? AppColors.error
                  : AppColors.textSecondary,
              size: AppDimensions.iconSizeSM,
            ),
            onPressed: () {
              setState(() {
                _passwordVisible = !_passwordVisible;
              });
            },
          ),
        ),

        const SizedBox(height: AppDimensions.spacingSM),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingMD),
          child: Text(
            "Password must be at least 6 characters",
            style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
          ),
        ),

        const SizedBox(height: AppDimensions.spacingXL),

        // Reset Password button
        SizedBox(
          width: double.infinity,
          height: AppDimensions.buttonHeightMD,
          child: Container(
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: AppDimensions.borderRadiusMD,
            ),
            child: ElevatedButton(
              onPressed: loading ? null : resetPassword,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: AppDimensions.borderRadiusMD,
                ),
              ),
              child: loading
                  ? const SizedBox(
                height: AppDimensions.iconSizeMD,
                width: AppDimensions.iconSizeMD,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.white,
                ),
              )
                  : Text("Reset Password", style: AppTextStyles.whiteLabel),
            ),
          ),
        ),

        const SizedBox(height: AppDimensions.spacingMD),

        TextButton(
          onPressed: () {
            setState(() {
              step = ForgotStep.otp;
              passwordController.clear();
              _fieldErrors['password'] = false;
              _fieldTouched['password'] = false;
            });
          },
          style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
          child: Text("Back to OTP", style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.primary),
          onPressed: () {
            if (step == ForgotStep.email) {
              Navigator.pop(context);
            } else if (step == ForgotStep.otp) {
              setState(() => step = ForgotStep.email);
            } else {
              setState(() => step = ForgotStep.otp);
            }
          },
        ),
        title: Text(
          step == ForgotStep.email
              ? "Forgot Password"
              : step == ForgotStep.otp
              ? "Verify OTP"
              : "Reset Password",
          style: AppTextStyles.heading4.copyWith(color: AppColors.primary),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.spacingMD,
            vertical: AppDimensions.spacingSM,
          ),
          child: step == ForgotStep.email
              ? _buildEmailStep()
              : step == ForgotStep.otp
              ? _buildOtpStep()
              : _buildResetStep(),
        ),
      ),
    );
  }
}