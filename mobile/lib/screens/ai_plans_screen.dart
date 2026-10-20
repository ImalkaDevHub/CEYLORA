import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ai_workflow.dart';
import '../providers/ai_workflows_provider.dart';
import '../providers/trips_provider.dart' show LoadState;
import '../utils/format.dart';
import '../widgets/ai_outcome_chip.dart';
import 'ai_plan_detail_screen.dart';
import 'ai_plan_form_screen.dart';

/// "AI plans" tab body: the traveler's own plans with pull-to-refresh.
class AiPlansScreen extends StatelessWidget {
  const AiPlansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final plans = context.watch<AiWorkflowsProvider>();

    Widget body;
    if (plans.state == LoadState.loading && plans.items.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (plans.state == LoadState.failed && plans.items.isEmpty) {
      body = _Message(
        icon: Icons.cloud_off,
        text: plans.error ?? 'Could not load your plans.',
        action:
            FilledButton(onPressed: plans.load, child: const Text('Try again')),
      );
    } else if (plans.items.isEmpty) {
      body = const _Message(
        icon: Icons.auto_awesome_outlined,
        text: 'No AI plans yet. Tap "Plan with AI" and describe your trip.',
      );
    } else {
      body = ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        itemCount: plans.items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _PlanCard(workflow: plans.items[i]),
      );
    }

    return Scaffold(
      body: RefreshIndicator(onRefresh: plans.load, child: body),
      floatingActionButton: FloatingActionButton.extended(
        // Null tag: every tab keeps its own Scaffold alive in the IndexedStack.
        heroTag: null,
        onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AiPlanFormScreen())),
        icon: const Icon(Icons.auto_awesome),
        label: const Text('Plan with AI'),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final AiWorkflow workflow;
  const _PlanCard({required this.workflow});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = workflow.days;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => AiPlanDetailScreen(workflowId: workflow.id))),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(workflow.goal,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 8),
                  AiOutcomeChip(workflow.outcome),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                  '$days ${days == 1 ? 'day' : 'days'}'
                  ' · ${formatLkr(workflow.budget)}',
                  style: theme.textTheme.bodyMedium),
              const SizedBox(height: 4),
              Text('Created ${formatDate(workflow.createdAt)}',
                  style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;
  const _Message({required this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    // ListView so pull-to-refresh still works on the empty/error states.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 80),
        Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
        const SizedBox(height: 16),
        Text(text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge),
        if (action != null) ...[const SizedBox(height: 16), Center(child: action)],
      ],
    );
  }
}
