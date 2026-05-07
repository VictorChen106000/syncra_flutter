import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../data/mock/mock_agent_steps.dart';

class AgentTerminal extends StatelessWidget {
  const AgentTerminal({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity( 0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity( 0.15),
            blurRadius: 22,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              _WindowDot(color: AppColors.danger),
              SizedBox(width: 6),
              _WindowDot(color: AppColors.warning),
              SizedBox(width: 6),
              _WindowDot(color: AppColors.success),
              SizedBox(width: 10),
              Text(
                'AGENT THOUGHT PROCESS',
                style: TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.2),
              ),
            ],
          ),
          const Divider(height: 24, color: Colors.white12),
          ...MockAgentSteps.terminalSteps.map(
            (step) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                step,
                style: TextStyle(
                  color: step.startsWith('Agent Decision') ? AppColors.warning : Colors.white.withOpacity( 0.80),
                  fontSize: 11,
                  height: 1.35,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WindowDot extends StatelessWidget {
  const _WindowDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(radius: 4.5, backgroundColor: color);
  }
}
