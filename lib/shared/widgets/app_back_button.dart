import 'package:flutter/material.dart';

import '../../core/theme/brand_theme.dart';

class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key, this.onPressed, this.color});

  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Back',
      button: true,
      child: InkResponse(
        onTap: onPressed ?? () => Navigator.of(context).maybePop(),
        radius: 22,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(
            Icons.chevron_left_rounded,
            color: color ?? context.brand.ink,
            size: 30,
          ),
        ),
      ),
    );
  }
}
