import 'package:flutter/material.dart';

import '../models/ai_workflow.dart';

/// Colors shared by the outcome chip (list) and banner (detail).
(Color, Color) outcomeColors(ColorScheme scheme, AiOutcome outcome) =>
    switch (outcome) {
      AiOutcome.ready ||
      AiOutcome.approved =>
        (scheme.primaryContainer, scheme.onPrimaryContainer),
      AiOutcome.awaitingApproval =>
        (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      AiOutcome.rejected => (scheme.errorContainer, scheme.onErrorContainer),
      AiOutcome.revisionRequested ||
      AiOutcome.flagged =>
        (scheme.secondaryContainer, scheme.onSecondaryContainer),
    };

IconData outcomeIcon(AiOutcome outcome) => switch (outcome) {
      AiOutcome.ready || AiOutcome.approved => Icons.check_circle_outline,
      AiOutcome.awaitingApproval => Icons.hourglass_top,
      AiOutcome.rejected => Icons.cancel_outlined,
      AiOutcome.revisionRequested => Icons.edit_note,
      AiOutcome.flagged => Icons.warning_amber,
    };

class AiOutcomeChip extends StatelessWidget {
  final AiOutcome outcome;
  const AiOutcomeChip(this.outcome, {super.key});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = outcomeColors(Theme.of(context).colorScheme, outcome);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(outcome.label,
          style:
              TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
