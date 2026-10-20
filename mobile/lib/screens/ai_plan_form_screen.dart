import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ai_workflow.dart';
import '../providers/ai_workflows_provider.dart';
import '../providers/trips_provider.dart';
import '../utils/format.dart';
import 'ai_plan_detail_screen.dart';

/// Request form for a new AI plan. [prefill] seeds the fields when planning
/// again from an earlier plan.
class AiPlanFormScreen extends StatefulWidget {
  final AiWorkflow? prefill;
  const AiPlanFormScreen({super.key, this.prefill});

  @override
  State<AiPlanFormScreen> createState() => _AiPlanFormScreenState();
}

class _AiPlanFormScreenState extends State<AiPlanFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _goal;
  late final TextEditingController _days;
  late final TextEditingController _budget;
  late final Set<String> _interests;
  DateTime? _startDate;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.prefill;
    _goal = TextEditingController(text: p?.goal ?? '');
    _days = TextEditingController(text: p == null ? '' : '${p.days}');
    _budget = TextEditingController(
        text: p == null
            ? ''
            : (p.budget == p.budget.roundToDouble()
                ? p.budget.toStringAsFixed(0)
                : '${p.budget}'));
    _interests = {...?p?.interests};
  }

  @override
  void dispose() {
    _goal.dispose();
    _days.dispose();
    _budget.dispose();
    super.dispose();
  }

  Future<void> _pickStartDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? today.add(const Duration(days: 1)),
      firstDate: today,
      lastDate: DateTime(today.year + 2, today.month, today.day),
    );
    if (picked != null && mounted) setState(() => _startDate = picked);
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    final trips = context.read<TripsProvider>();
    final (workflow, error) = await context.read<AiWorkflowsProvider>().start(
          goal: _goal.text.trim(),
          days: int.parse(_days.text.trim()),
          budget: double.parse(_budget.text.trim()),
          // Keep the chips' display order for a stable request body.
          interests: [for (final i in aiInterests) if (_interests.contains(i)) i],
          startDate: _startDate,
        );
    if (!mounted) return;
    if (workflow != null) {
      // Starting a plan also creates its trip, so refresh My trips.
      trips.load();
      Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => AiPlanDetailScreen(workflowId: workflow.id)));
    } else {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return PopScope(
      // The request can't be cancelled; stay put until it finishes.
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('New AI plan')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(_error!,
                          style: TextStyle(color: scheme.onErrorContainer)),
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: _goal,
                    enabled: !_busy,
                    minLines: 2,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                        labelText: 'Trip goal',
                        hintText:
                            'e.g. A relaxed beach and culture trip on the south coast',
                        border: OutlineInputBorder()),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Describe what you want from this trip'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _days,
                          enabled: !_busy,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                              labelText: 'Days', border: OutlineInputBorder()),
                          validator: (v) {
                            final n = int.tryParse((v ?? '').trim());
                            if (n == null) return 'Enter the number of days';
                            if (n < 1 || n > 60) return 'Between 1 and 60 days';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _budget,
                          enabled: !_busy,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                              labelText: 'Budget',
                              prefixText: 'LKR ',
                              border: OutlineInputBorder()),
                          validator: (v) {
                            final n = double.tryParse((v ?? '').trim());
                            if (n == null || !n.isFinite) {
                              return 'Enter your budget';
                            }
                            if (n < 0) return 'Budget cannot be negative';
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: _busy ? null : _pickStartDate,
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Start date (optional)',
                        border: const OutlineInputBorder(),
                        suffixIcon: _startDate == null
                            ? const Icon(Icons.calendar_today, size: 18)
                            : IconButton(
                                tooltip: 'Clear start date',
                                icon: const Icon(Icons.close),
                                onPressed: _busy
                                    ? null
                                    : () => setState(() => _startDate = null),
                              ),
                      ),
                      child: Text(_startDate == null
                          ? 'Tomorrow'
                          : formatPickedDate(_startDate!)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('Interests (optional)',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final i in aiInterests)
                        FilterChip(
                          label: Text(interestLabel(i)),
                          selected: _interests.contains(i),
                          onSelected: _busy
                              ? null
                              : (on) => setState(() =>
                                  on ? _interests.add(i) : _interests.remove(i)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (_busy) ...[
                    Row(
                      children: [
                        const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                              'Planning your trip... this can take up to 30 seconds',
                              style: Theme.of(context).textTheme.bodyMedium),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: const Text('Create plan'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
