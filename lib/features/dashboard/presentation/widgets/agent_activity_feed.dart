import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../data/mock/mock_agent_steps.dart';

class AgentActivityFeed extends StatelessWidget {
  const AgentActivityFeed({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: MockAgentSteps.activityFeed.map((activity) {
        final status = activity['status'];
        final isActive = status == 'active';

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border.withOpacity( 0.65)),
          ),
          child: Row(
            children: [
              if (isActive)
                Container(
                  width: 3,
                  height: 42,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              CircleAvatar(
                radius: 16,
                backgroundColor: status == 'done'
                    ? AppColors.softSurface
                    : isActive
                        ? AppColors.ink
                        : Colors.amber.shade50,
                child: Icon(
                  status == 'done'
                      ? Icons.check_circle_outline_rounded
                      : isActive
                          ? Icons.bolt_rounded
                          : Icons.access_time_rounded,
                  size: 17,
                  color: isActive ? AppColors.accent : AppColors.ink,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activity['tool'] ?? '',
                      style: TextStyle(
                        color: AppColors.ink.withOpacity( 0.40),
                        fontSize: 10,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      activity['detail'] ?? '',
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 12,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                activity['time'] ?? '',
                style: const TextStyle(color: AppColors.textSoft, fontSize: 10, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
