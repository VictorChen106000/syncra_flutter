import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_assets.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/brand_theme.dart';
import '../state/auth_notifier.dart';

class LoginPage extends ConsumerWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Login is intentionally dark in both themes (matches the marketing
    // background asset). Use BrandTheme.dark directly so colors don't shift
    // when system flips to light.
    const brand = BrandTheme.dark;
    final auth = ref.watch(authProvider);
    final notifier = ref.read(authProvider.notifier);
    final disabled = auth.isLoading;
    return Scaffold(
      backgroundColor: brand.bg,
      body: Stack(
        children: [
          const _LoginBackground(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      // Scale headline down on narrow phones so the three-line
                      // "Let AI Agent / Apply / For You." block never wraps or
                      // clips. 48 is the design target; floor is ~37.
                      final scale = (constraints.maxWidth / 360).clamp(
                        0.78,
                        1.0,
                      );
                      // Pull GoogleFonts.inter directly to guarantee the Black
                      // (w900) weight is actually loaded — relying on the
                      // theme's interTextTheme sometimes falls back to a
                      // lighter weight for very large display type.
                      final headline = GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 48 * scale,
                        height: 1.02,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.1,
                      );
                      return RichText(
                        text: TextSpan(
                          style: headline,
                          children: [
                            const TextSpan(text: 'Let '),
                            TextSpan(
                              text: 'AI Agent',
                              style: TextStyle(color: brand.accent),
                            ),
                            const TextSpan(text: '\nApply\nFor You.'),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 40),
                  _LoginButton(
                    label: AppStrings.continueWithGoogle,
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF0A0B0A),
                    leading: SvgPicture.asset(
                      AppAssets.googleGSvg,
                      width: 20,
                      height: 20,
                    ),
                    loading: disabled,
                    onTap: disabled ? null : () => notifier.signInWithGoogle(),
                  ),
                  const SizedBox(height: 12),
                  _LoginButton(
                    label: 'Continue with Email',
                    backgroundColor: Colors.white.withValues(alpha: 0.16),
                    foregroundColor: Colors.white,
                    leading: const Icon(
                      Icons.mail_outline_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                    borderColor: Colors.white.withValues(alpha: 0.32),
                    loading: false,
                    onTap: disabled ? null : () => _showEmailSheet(context),
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: TextButton(
                      onPressed:
                          disabled ? null : () => notifier.continueAsGuest(),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        minimumSize: const Size(0, 44),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        AppStrings.continueAsGuest,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    AppStrings.loginTerms,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 11,
                      height: 1.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showEmailSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (_) => const _EmailSignInSheet(),
    );
  }
}

class _LoginBackground extends StatelessWidget {
  const _LoginBackground();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            AppAssets.loginBackground,
            fit: BoxFit.cover,
          ),
          // Bottom-anchored dark gradient guarantees headline + buttons stay
          // legible regardless of which part of the photo sits behind them.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.45, 1.0],
                colors: [
                  Color(0x00000000),
                  Color(0x66000000),
                  Color(0xE6000000),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginButton extends StatelessWidget {
  const _LoginButton({
    required this.label,
    required this.leading,
    required this.onTap,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.loading,
    this.borderColor,
  });

  final String label;
  final Widget leading;
  final VoidCallback? onTap;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color? borderColor;
  final bool loading;

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
            children: loading
                ? [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(foregroundColor),
                      ),
                    ),
                  ]
                : [
                    leading,
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

// ---------------------------------------------------------------------------
// Email sign-in bottom sheet — popup over the marketing background.
// ---------------------------------------------------------------------------

class _EmailSignInSheet extends ConsumerStatefulWidget {
  const _EmailSignInSheet();

  @override
  ConsumerState<_EmailSignInSheet> createState() => _EmailSignInSheetState();
}

class _EmailSignInSheetState extends ConsumerState<_EmailSignInSheet> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  bool _obscure = true;
  bool _isCreate = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final notifier = ref.read(authProvider.notifier);
    await notifier.signInWithEmail(
      email: _email.text,
      password: _password.text,
    );
    final auth = ref.read(authProvider);
    if (!mounted) return;
    if (auth.appUser != null && auth.error == null) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    const brand = BrandTheme.dark;
    final auth = ref.watch(authProvider);
    final disabled = auth.isLoading;
    final inset = MediaQuery.viewInsetsOf(context).bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.only(bottom: inset),
      child: Container(
        decoration: BoxDecoration(
          color: brand.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(
            top: BorderSide(color: brand.border),
            left: BorderSide(color: brand.border),
            right: BorderSide(color: brand.border),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: brand.border,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              _isCreate ? 'Create account' : 'Continue with email',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _isCreate
                  ? "We'll set you up so the agent can start working."
                  : "Sign in and the agent picks up where it left off.",
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.60),
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 22),
            _SheetField(
              controller: _email,
              focusNode: _emailFocus,
              label: 'Email',
              hint: 'you@domain.com',
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              icon: Icons.mail_outline_rounded,
              onSubmitted: (_) => _passwordFocus.requestFocus(),
            ),
            const SizedBox(height: 12),
            _SheetField(
              controller: _password,
              focusNode: _passwordFocus,
              label: 'Password',
              hint: 'At least 8 characters',
              obscureText: _obscure,
              textInputAction: TextInputAction.done,
              icon: Icons.lock_outline_rounded,
              onSubmitted: (_) => _submit(),
              trailing: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 18,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
            ),
            if (auth.error != null) ...[
              const SizedBox(height: 14),
              _SheetError(message: auth.error!),
            ],
            const SizedBox(height: 22),
            _SheetSubmitButton(
              label: disabled
                  ? 'Signing in…'
                  : (_isCreate ? 'Create account' : 'Sign in'),
              onTap: disabled ? null : _submit,
            ),
            const SizedBox(height: 14),
            Center(
              child: TextButton(
                onPressed: disabled
                    ? null
                    : () => setState(() => _isCreate = !_isCreate),
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    children: [
                      TextSpan(
                        text: _isCreate
                            ? 'Already have an account? '
                            : 'New here? ',
                      ),
                      TextSpan(
                        text: _isCreate ? 'Sign in' : 'Create account',
                        style: TextStyle(
                          color: brand.accent,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetSubmitButton extends StatelessWidget {
  const _SheetSubmitButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const brand = BrandTheme.dark;
    final isLoading = onTap == null;
    return Material(
      color: brand.accent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          height: 56,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: isLoading
                ? [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(brand.onAccent),
                      ),
                    ),
                  ]
                : [
                    Text(
                      label,
                      style: TextStyle(
                        color: brand.onAccent,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.arrow_forward_rounded,
                      color: brand.onAccent,
                      size: 20,
                    ),
                  ],
          ),
        ),
      ),
    );
  }
}

class _SheetError extends StatelessWidget {
  const _SheetError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    const brand = BrandTheme.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: brand.danger.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: brand.danger.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: brand.danger, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.92),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetField extends StatelessWidget {
  const _SheetField({
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.trailing,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    const brand = BrandTheme.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 10.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: brand.surfaceMuted,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: brand.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Icon(icon, size: 18, color: Colors.white.withValues(alpha: 0.55)),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  obscureText: obscureText,
                  keyboardType: keyboardType,
                  textInputAction: textInputAction,
                  onSubmitted: onSubmitted,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  cursorColor: brand.accent,
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.30),
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                    isCollapsed: true,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 16),
                    border: InputBorder.none,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ],
    );
  }
}
