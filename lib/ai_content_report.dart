import 'package:flutter/material.dart';
import 'api_service.dart';
import 'translations.dart';

Future<void> showAIContentReport({
  required BuildContext context,
  required ApiService api,
  required String language,
  required String contentType,
  String content = '',
  String prompt = '',
  String model = '',
  String videoUrl = '',
}) async {
  final sent = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AIContentReportDialog(
      api: api,
      language: language,
      contentType: contentType,
      content: content,
      prompt: prompt,
      model: model,
      videoUrl: videoUrl,
    ),
  );

  if (!context.mounted || sent != true) return;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        AppTranslations.translate(language, 'aiReportSent'),
      ),
    ),
  );
}

class _AIContentReportDialog extends StatefulWidget {
  const _AIContentReportDialog({
    required this.api,
    required this.language,
    required this.contentType,
    required this.content,
    required this.prompt,
    required this.model,
    required this.videoUrl,
  });

  final ApiService api;
  final String language;
  final String contentType;
  final String content;
  final String prompt;
  final String model;
  final String videoUrl;

  @override
  State<_AIContentReportDialog> createState() =>
      _AIContentReportDialogState();
}

class _AIContentReportDialogState
    extends State<_AIContentReportDialog> {
  final _detailsController = TextEditingController();

  String _reason = 'other';
  bool _sending = false;
  bool _failed = false;

  static const _reasons = {
    'sexual': 'aiReportSexual',
    'violence': 'aiReportViolence',
    'hate': 'aiReportHate',
    'child_safety': 'aiReportChildSafety',
    'misleading': 'aiReportMisleading',
    'other': 'aiReportOther',
  };

  String _t(String key) =>
      AppTranslations.translate(widget.language, key);

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _sending = true;
      _failed = false;
    });

    try {
      await widget.api.reportAIContent(
        contentType: widget.contentType,
        reason: _reason,
        language: widget.language,
        details: _detailsController.text,
        content: widget.content,
        prompt: widget.prompt,
        model: widget.model,
        videoUrl: widget.videoUrl,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _sending = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_sending,
      child: AlertDialog(
        title: Text(_t('aiReportTitle')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_t('aiReportNotice')),
              const SizedBox(height: 20),
              Text(_t('aiReportReason')),
              const SizedBox(height: 8),
              DropdownButton<String>(
                value: _reason,
                isExpanded: true,
                items: _reasons.entries.map((entry) {
                  return DropdownMenuItem<String>(
                    value: entry.key,
                    child: Text(
                      _t(entry.value),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: _sending
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() => _reason = value);
                      },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _detailsController,
                enabled: !_sending,
                maxLength: 2000,
                minLines: 2,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: _t('aiReportDetails'),
                  border: const OutlineInputBorder(),
                ),
              ),
              if (_failed) ...[
                const SizedBox(height: 12),
                Text(
                  _t('aiReportFailed'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _sending
                ? null
                : () => Navigator.of(context).pop(false),
            child: Text(_t('cancel')),
          ),
          FilledButton(
            onPressed: _sending ? null : _send,
            child: Text(
              _t(_sending ? 'aiReportSending' : 'aiReportSend'),
            ),
          ),
        ],
      ),
    );
  }
}