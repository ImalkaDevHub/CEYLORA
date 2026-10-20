import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/trips_provider.dart';
import '../utils/format.dart';

class CreateTripScreen extends StatefulWidget {
  const CreateTripScreen({super.key});

  @override
  State<CreateTripScreen> createState() => _CreateTripScreenState();
}

class _CreateTripScreenState extends State<CreateTripScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _budget = TextEditingController();
  DateTime? _start;
  DateTime? _end;
  bool _datesTouched = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _budget.dispose();
    super.dispose();
  }

  String? get _dateError {
    if (!_datesTouched) return null;
    if (_start == null || _end == null) return 'Pick a start and end date';
    if (_end!.isBefore(_start!)) return 'End date cannot be before start date';
    return null;
  }

  Future<void> _pick({required bool start}) async {
    final now = DateTime.now();
    final initial = (start ? _start : _end) ?? _start ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = picked;
        // Keep the range valid when the start moves past the end.
        if (_end != null && _end!.isBefore(picked)) _end = picked;
      } else {
        _end = picked;
      }
    });
  }

  Future<void> _submit() async {
    setState(() => _datesTouched = true);
    final formOk = _formKey.currentState!.validate();
    if (!formOk || _dateError != null) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await context.read<TripsProvider>().create(
          title: _title.text.trim(),
          startDate: _start!,
          endDate: _end!,
          budget: double.parse(_budget.text.trim()),
        );
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dateError = _dateError;

    return Scaffold(
      appBar: AppBar(title: const Text('New trip')),
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
                  controller: _title,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                      labelText: 'Trip title', border: OutlineInputBorder()),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Give your trip a title'
                      : null,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _DateField(
                        label: 'Start date',
                        value: _start,
                        onTap: () => _pick(start: true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DateField(
                        label: 'End date',
                        value: _end,
                        onTap: () => _pick(start: false),
                      ),
                    ),
                  ],
                ),
                if (dateError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, left: 12),
                    child: Text(dateError,
                        style: TextStyle(color: scheme.error, fontSize: 12)),
                  ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _budget,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                      labelText: 'Budget',
                      prefixText: 'LKR ',
                      border: OutlineInputBorder()),
                  validator: (v) {
                    final n = double.tryParse((v ?? '').trim());
                    if (n == null) return 'Enter your budget';
                    if (n <= 0) return 'Budget must be more than 0';
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Create trip'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  const _DateField(
      {required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.calendar_today, size: 18),
        ),
        child: Text(value == null ? 'Select' : formatDate(value!)),
      ),
    );
  }
}
