import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../state/auth_controller.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: Stack(
        children: [
          const _LoginBackground(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
              child: Consumer<AuthController>(
                builder: (context, authController, _) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Spacer(),
                      RichText(
                        text: TextSpan(
                          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                                color: Colors.white,
                                fontSize: 44,
                              ),
                          children: const [
                            TextSpan(text: 'Let '),
                            TextSpan(
                              text: 'AI Agent',
                              style: TextStyle(color: AppColors.accent),
                            ),
                            TextSpan(text: '\nApply\nFor You.'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Show error message if sign-in failed
                      if (authController.error != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.danger.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.danger.withOpacity(0.30)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  authController.error!,
                                  style: const TextStyle(color: AppColors.danger, fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // Google Sign-In button
                      _LoginButton(
                        label: AppStrings.continueWithGoogle,
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.ink,
                        icon: Icons.g_mobiledata_rounded,
                        isLoading: authController.isLoading,
                        onTap: authController.isLoading
                            ? null
                            : () => authController.signInWithGoogle(),
                      ),
                      const SizedBox(height: 12),

                      // Apple Sign-In button (still placeholder)
                      _LoginButton(
                        label: AppStrings.continueWithApple,
                        backgroundColor: Colors.white.withOpacity(0.10),
                        foregroundColor: Colors.white,
                        icon: Icons.apple_rounded,
                        borderColor: Colors.white.withOpacity(0.20),
                        isLoading: false,
                        onTap: authController.isLoading ? null : () {},
                      ),
                      const SizedBox(height: 12),

                      // Guest button
                      Center(
                        child: TextButton(
                          onPressed: authController.isLoading
                              ? null
                              : () => authController.continueAsGuest(),
                          child: Text(
                            AppStrings.continueAsGuest,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.70),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        AppStrings.loginTerms,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.42),
                          fontSize: 11,
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginBackground extends StatelessWidget {
  const _LoginBackground();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF312E81),
              const Color(0xFF581C87),
              AppColors.ink.withOpacity(0.98),
            ],
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                AppColors.ink.withOpacity(0.72),
                AppColors.ink,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginButton extends StatelessWidget {
  const _LoginButton({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.backgroundColor,
    required this.foregroundColor,
    this.borderColor,
    this.isLoading = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color? borderColor;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 58,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: borderColor == null ? null : Border.all(color: borderColor!),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isLoading)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: foregroundColor,
                  ),
                )
              else
                Icon(icon, color: foregroundColor, size: 24),
              const SizedBox(width: 10),
              Text(
                isLoading ? 'Signing in...' : label,
                style: TextStyle(
                  color: foregroundColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
