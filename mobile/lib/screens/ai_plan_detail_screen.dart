import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ai_workflow.dart';
import '../providers/ai_workflows_provider.dart';
import '../utils/format.dart';
import '../widgets/ai_outcome_chip.dart';
import 'ai_plan_form_screen.dart';

class AiPlanDetailScreen extends StatefulWidget {
  final String workflowId;
  const AiPlanDetailScreen({super.key, required this.workflowId});

  /// How often to re-check a plan that is waiting for an operator.
  static const pollInterval = Duration(seconds: 10);

  @override
  State<AiPlanDetailScreen> createState() => _AiPlanDetailScreenState();
}

class _AiPlanDetailScreenState extends State<AiPlanDetailScreen> {
  Timer? _poll;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// Poll only while an operator decision is pending; stop as soon as the
  /// status moves on.
  void _syncPolling(bool awaiting) {
    if (awaiting && _poll == null) {
      _poll = Timer.periodic(AiPlanDetailScreen.pollInterval, (_) {
        if (!mounted) return;
        context.read<AiWorkflowsProvider>().refresh(widget.workflowId);
      });
    } else if (!awaiting && _poll != null) {
      _poll!.cancel();
      _poll = null;
    }
  }

  Future<void> _pullToRefresh() async {
    final provider = context.read<AiWorkflowsProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final error = await provider.refresh(widget.workflowId);
    if (error != null) messenger.showSnackBar(SnackBar(content: Text(error)));
  }

  @override
  Widget build(BuildContext context) {
    final workflow = context.watch<AiWorkflowsProvider>().byId(widget.workflowId);

    if (workflow == null) {
      _syncPolling(false);
      return Scaffold(
        appBar: AppBar(title: const Text('AI plan')),
        body: const Center(child: Text('This plan is no longer available.')),
      );
    }

    final outcome = workflow.outcome;
    _syncPolling(outcome == AiOutcome.awaitingApproval);
    final theme = Theme.of(context);
    final days = workflow.days;
    final plan = workflow.finalPlan?.trim();

    return Scaffold(
      appBar: AppBar(title: const Text('AI plan')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _pullToRefresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            children: [
              _OutcomeBanner(outcome),
              const SizedBox(height: 24),
              Text('Your request', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              _InfoRow(
                  icon: Icons.flag_outlined, label: 'Goal', value: workflow.goal),
              _InfoRow(
                  icon: Icons.schedule,
                  label: 'Length',
                  value: '$days ${days == 1 ? 'day' : 'days'}'),
              _InfoRow(
                  icon: Icons.payments_outlined,
                  label: 'Budget',
                  value: formatLkr(workflow.budget)),
              if (workflow.interests.isNotEmpty)
                _InfoRow(
                    icon: Icons.favorite_border,
                    label: 'Interests',
                    value: workflow.interests.map(interestLabel).join(', ')),
              _InfoRow(
                  icon: Icons.event,
                  label: 'Created',
                  value: formatDate(workflow.createdAt)),
              if (workflow.steps.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('How it was planned', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final step in workflow.steps) _StepTile(step: step),
              ],
              const SizedBox(height: 24),
              Text('Plan', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              if (plan == null || plan.isEmpty)
                Text('No plan was produced for this request.',
                    style: theme.textTheme.bodyMedium)
              else
                SelectableText(plan, style: theme.textTheme.bodyMedium),
              if (outcome.canPlanAgain) ...[
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                          builder: (_) => AiPlanFormScreen(prefill: workflow))),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Plan again'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _OutcomeBanner extends StatelessWidget {
  final AiOutcome outcome;
  const _OutcomeBanner(this.outcome);

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = outcomeColors(Theme.of(context).colorScheme, outcome);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(outcomeIcon(outcome), color: fg),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(outcome.label,
                    style: TextStyle(
                        color: fg, fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(outcome.message, style: TextStyle(color: fg)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  final AiWorkflowStep step;
  const _StepTile({required this.step});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final detail = step.detail;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(step.succeeded ? Icons.check_circle : Icons.error,
              size: 20, color: step.succeeded ? scheme.primary : scheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.label,
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600)),
                if (detail != null)
                  Text(detail, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          SizedBox(
              width: 80, child: Text(label, style: theme.textTheme.bodySmall)),
          Expanded(child: Text(value, style: theme.textTheme.bodyLarge)),
        ],
      ),
    );
  }
}
