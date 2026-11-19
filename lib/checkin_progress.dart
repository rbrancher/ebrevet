import 'package:flutter/material.dart';
import 'checkin.dart';

class CheckinProgress extends StatelessWidget {
  final List<Checkin?> checklist;
  final int numControls;

  const CheckinProgress(
      {super.key, required this.checklist, required this.numControls});

  @override
  Widget build(BuildContext context) {
    if (numControls <= 0) {
      return const Text("No controls");
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final completedColor = scheme.primary;
    final onCompletedColor = scheme.onPrimary;
    final remainingColor = scheme.surfaceContainerHighest;
    final onRemainingColor = scheme.onSurfaceVariant;
    final labelStyle =
        theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold);

    return LayoutBuilder(
      builder: (context, constraints) {
        // final count = checklist!
        // .length;
        final maxWidth = constraints.maxWidth;
        final circleDiameter = (maxWidth / numControls) - 6;
        final radius = (circleDiameter / 2).clamp(8.0, 15.0);

        final completed = List<bool>.generate(
          numControls,
          (i) => i < checklist.length && checklist[i] != null,
        );

        return SizedBox(
          height: radius * 2,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _ChecklistProgressLinePainter(
                    circleCount: numControls,
                    radius: radius,
                    width: maxWidth,
                    completed: completed,
                    completedColor: completedColor,
                    remainingColor: remainingColor,
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (int i = 0; i < numControls; i++)
                    CircleAvatar(
                      radius: radius,
                      backgroundColor:
                          completed[i] ? completedColor : remainingColor,
                      child: Text(
                        "${i + 1}",
                        style: labelStyle?.copyWith(
                          color: completed[i]
                              ? onCompletedColor
                              : onRemainingColor,
                        ),
                      ),
                    )
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ChecklistProgressLinePainter extends CustomPainter {
  final int circleCount;
  final double radius;
  final double width;
  final List<bool> completed;
  final Color completedColor;
  final Color remainingColor;

  _ChecklistProgressLinePainter({
    required this.circleCount,
    required this.radius,
    required this.width,
    required this.completed,
    required this.completedColor,
    required this.remainingColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (circleCount < 2) return;

    final y = size.height / 2;
    final gap = width / circleCount;

    final paint = Paint()
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < circleCount - 1; i++) {
      final startX = gap * i + gap / 2;
      final endX = gap * (i + 1) + gap / 2;

      paint.color =
          completed[i] && completed[i + 1] ? completedColor : remainingColor;

      canvas.drawLine(Offset(startX, y), Offset(endX, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ChecklistProgressLinePainter oldDelegate) {
    return circleCount != oldDelegate.circleCount ||
        radius != oldDelegate.radius ||
        width != oldDelegate.width ||
        completed != oldDelegate.completed ||
        completedColor != oldDelegate.completedColor ||
        remainingColor != oldDelegate.remainingColor;
  }
}
