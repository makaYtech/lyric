import 'package:flutter/material.dart';

import '../../services/feedback_service.dart';
import '../shell/adaptive_sheet.dart';

/// Открывает окно обратной связи. На узком экране — нижняя шторка,
/// на широком — диалог по центру (см. [showAdaptiveSheet]).
/// Возвращает true, если отзыв ушёл.
Future<bool> showFeedbackSheet(BuildContext context, FeedbackType type) async {
  final result = await showAdaptiveSheet<bool>(
    context,
    useSafeArea: true,
    selfScrolling: true,
    builder: (_, _) => FeedbackSheet(type: type),
  );
  return result == true;
}

class FeedbackSheet extends StatefulWidget {
  final FeedbackType type;

  const FeedbackSheet({super.key, required this.type});

  @override
  State<FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<FeedbackSheet> {
  final _message = TextEditingController();
  final _details = TextEditingController();
  final _contact = TextEditingController();

  bool _attach = true;
  bool _sending = false;
  String? _error;

  bool get _isBug => widget.type == FeedbackType.bug;

  @override
  void dispose() {
    _message.dispose();
    _details.dispose();
    _contact.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _message.text.trim();
    if (text.length < FeedbackService.minLength) {
      setState(() {
        _error =
            'Опиши чуть подробнее (минимум ${FeedbackService.minLength} символов)';
      });
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    final result = await FeedbackService.send(
      type: widget.type,
      message: text,
      details: _isBug ? _details.text : '',
      contact: _contact.text,
      attachDiagnostics: _attach,
    );
    if (!mounted) return;

    if (result == FeedbackResult.sent) {
      Navigator.of(context).pop(true);
      return;
    }

    setState(() {
      _sending = false;
      _error = switch (result) {
        FeedbackResult.tooFast => 'Подожди немного перед следующей отправкой',
        FeedbackResult.notConfigured => 'Форма обратной связи ещё не настроена',
        _ => 'Не удалось отправить. Проверь интернет и попробуй ещё раз',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: !_sending,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _isBug ? 'Сообщить об ошибке' : 'Отзыв или предложение',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _message,
                enabled: !_sending,
                minLines: 3,
                maxLines: 6,
                maxLength: FeedbackService.maxLength,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: _isBug
                      ? 'Что пошло не так?'
                      : 'Расскажи подробнее',
                  alignLabelWithHint: true,
                ),
              ),
              if (_isBug) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _details,
                  enabled: !_sending,
                  minLines: 2,
                  maxLines: 5,
                  maxLength: FeedbackService.maxLength,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Как это повторить (необязательно)',
                    alignLabelWithHint: true,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _contact,
                enabled: !_sending,
                maxLength: 200,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Как с тобой связаться (необязательно)',
                  hintText: 'Telegram, почта…',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Приложить сведения об устройстве'),
                subtitle: const Text(
                  'Только версия приложения и ОС. Данные аккаунта, оценки '
                  'и расписание не отправляются',
                ),
                value: _attach,
                onChanged: _sending ? null : (v) => setState(() => _attach = v),
              ),
              if (_error != null) ...[
                const SizedBox(height: 4),
                Text(
                  _error!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _sending ? null : _submit,
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: Text(_sending ? 'Отправляем…' : 'Отправить'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
