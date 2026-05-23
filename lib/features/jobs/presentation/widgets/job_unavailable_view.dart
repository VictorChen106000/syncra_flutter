import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/brand_theme.dart';
import '../../../../shared/widgets/empty_state_card.dart';

/// Shown when a job-scoped page (detail / tailor / review / submitted) is
/// opened without a [Job] in the route's `extra` — e.g. a stale deep link or
/// a back-stack restore. Replaces the old "fall back to a mock job" behavior.
class JobUnavailableView extends StatelessWidget {
  const JobUnavailableView({super.key});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Scaffold(
      backgroundColor: brand.bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: EmptyStateCard(
              icon: Icons.work_off_rounded,
              title: 'Job unavailable',
              body: 'This role is no longer available. Head back to your '
                  'jobs to pick another.',
              actionLabel: 'Back to chat',
              onAction: () => context.go(RouteNames.agentChat),
            ),
          ),
        ),
      ),
    );
  }
}
