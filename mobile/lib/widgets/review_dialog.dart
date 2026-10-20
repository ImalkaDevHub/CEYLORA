import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/accommodations_provider.dart';
import '../providers/reviews_provider.dart';
import 'rating.dart';

/// Asks for a rating and comment and posts the review. Resolves to true when the review
/// was saved. The API decides who may review (only after a finished stay), so its message
/// is shown right in the dialog instead of being guessed here.
Future<bool?> showReviewDialog(
  BuildContext context, {
  required String accommodationId,
  required String accommodationName,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _ReviewDialog(
        accommodationId: accommodationId, accommodationName: accommodationName),
  );
}

class _ReviewDialog extends StatefulWidget {
  final String accommodationId;
  final String accommodationName;
  const _ReviewDialog(
      {required this.accommodationId, required this.accommodationName});

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  static const maxComment = 1000;

  final _comment = TextEditingController();
  int _rating = 0;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0) {
      setState(() => _error = 'Choose a rating from 1 to 5 stars.');
      return;
    }
    final reviews = context.read<ReviewsProvider>();
    final stays = context.read<AccommodationsProvider>();
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await reviews.add(widget.accommodationId,
        rating: _rating, comment: _comment.text);
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _busy = false;
        _error = error;
      });
      return;
    }
    // The stay's average rating changed.
    stays.fetch(widget.accommodationId);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text('Review ${widget.accommodationName}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StarPicker(
                value: _rating,
                onChanged: _busy ? (_) {} : (v) => setState(() => _rating = v)),
            TextField(
              controller: _comment,
              enabled: !_busy,
              minLines: 3,
              maxLines: 5,
              maxLength: maxComment,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'Your review (optional)',
                  border: OutlineInputBorder()),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: TextStyle(color: scheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Submit'),
        ),
      ],
    );
  }
}
