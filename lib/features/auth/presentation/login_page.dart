import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_assets.dart';
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
                builder: (context, auth, _) {
                  final disabled = auth.isLoading;
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
                      _LoginButton(
                        label: AppStrings.continueWithGoogle,
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.ink,
                        icon: Icons.g_mobiledata_rounded,
                        onTap: disabled ? null : () => auth.signInWithGoogle(),
                      ),
                      const SizedBox(height: 12),
                      _LoginButton(
                        label: AppStrings.continueWithApple,
                        backgroundColor: Colors.white.withValues(alpha: 0.10),
                        foregroundColor: Colors.white,
                        icon: Icons.apple_rounded,
                        borderColor: Colors.white.withValues(alpha: 0.20),
                        onTap: disabled ? null : () {},
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: TextButton(
                          onPressed:
                              disabled ? null : () => auth.continueAsGuest(),
                          child: Text(
                            AppStrings.continueAsGuest,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.70),
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
                          color: Colors.white.withValues(alpha: 0.42),
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
      child: Image.asset(
        AppAssets.loginBackground,
        fit: BoxFit.cover,
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
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color? borderColor;

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
            border:
                borderColor == null ? null : Border.all(color: borderColor!),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: foregroundColor, size: 24),
              const SizedBox(width: 10),
              Text(
                label,
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
