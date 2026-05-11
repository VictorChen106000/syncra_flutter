import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../data/mock/mock_agent_steps.dart';

class AgentTerminal extends StatelessWidget {
  const AgentTerminal({super.key});

  // Determine text color per step type
  Color _stepColor(String step) {
    if (step.startsWith('Agent Decision')) return AppColors.warning;
    if (step.startsWith('Tool Call')) return Colors.white.withValues(alpha: 0.80);
    return Colors.white.withValues(alpha: 0.65);
  }

  // Prefix icon per step type
  String _stepPrefix(String step) {
    if (step.startsWith('Agent Decision')) return '🔍';
    return '⚙️';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 22,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Gradient shimmer line at the very top
          Container(
            height: 1,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  AppColors.accent,
                  Colors.transparent,
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Window control dots + label
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
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 22, color: Colors.white12),
                // Steps
                ...MockAgentSteps.terminalSteps.map(
                  (step) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _stepPrefix(step),
                          style: const TextStyle(fontSize: 11),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            step,
                            style: TextStyle(
                              color: _stepColor(step),
                              fontSize: 11,
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Animated "processing" line
                const _ProcessingLine(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Animated "processing…" indicator inside the terminal
// ---------------------------------------------------------------------------

class _ProcessingLine extends StatefulWidget {
  const _ProcessingLine();

  @override
  State<_ProcessingLine> createState() => _ProcessingLineState();
}

class _ProcessingLineState extends State<_ProcessingLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.25, end: 0.90).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacity,
      builder: (context, _) => Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accent.withValues(alpha: _opacity.value),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            'Processing...',
            style: TextStyle(
              color: Colors.white.withValues(alpha: _opacity.value * 0.5),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// macOS-style window dot
// ---------------------------------------------------------------------------

class _WindowDot extends StatelessWidget {
  const _WindowDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(radius: 4.5, backgroundColor: color);
  }
}
