import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_service.dart';
import 'ai_content_report.dart';
import 'credits_page.dart';
import 'instagram_reel_page.dart';
import 'jarvis_tasks_page.dart';
import 'translations.dart';

class JarvisVideoPage extends StatefulWidget {
  const JarvisVideoPage({
    super.key,
    required this.language,
    required this.title,
    required this.prompt,
    required this.caption,
  });

  final String language;
  final String title;
  final String prompt;
  final String caption;

  @override
  State<JarvisVideoPage> createState() => _JarvisVideoPageState();
}

class _JarvisVideoPageState extends State<JarvisVideoPage> {
  static const _storage = FlutterSecureStorage();
  static const _key = 'easyai_jarvis_task_request_v2';

  final _api = ApiService();
  final _prompt = TextEditingController();
  final _caption = TextEditingController();

  bool _loaded = false;
  bool _busy = false;
  bool _locked = false;

  String? _requestId;
  String? _legacyUrl;
  String? _notice;

  String _title = '';
  String _mode = 'create';

  String _t(String en, String ky, String ru, String tr) {
    return switch (widget.language) {
      'Кыргызча' => ky,
      'Русский' => ru,
      'Türkçe' => tr,
      _ => en,
    };
  }

  @override
  void initState() {
    super.initState();

    _title = widget.title;
    _prompt.text = widget.prompt;
    _caption.text = widget.caption;

    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final saved = await _storage.read(key: _key);

      if (saved != null) {
        final data = jsonDecode(saved) as Map;
        final id = data['requestId'];

        if (id is! String ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(id)) {
          throw const FormatException('INVALID_TASK');
        }

        _requestId = id;
        _title = data['title'] as String;
        _prompt.text = data['prompt'] as String;
        _caption.text = data['caption'] as String;
        _mode = data['mode'] as String;

        _notice = _t(
          'A previous command was saved. Check Tasks before '
              'starting anything else.',
          'Мурунку буйрук сакталган. Башкасын баштоодон мурун '
              '«Тапшырмалар» бөлүмүн текшериңиз.',
          'Предыдущая команда сохранена. Проверьте «Задачи» '
              'перед новым запуском.',
          'Önceki komut kaydedilmiş. Yeni bir işlemden önce '
              'Görevler’i kontrol edin.',
        );
      } else {
        final legacy = await _storage.read(
          key: 'easyai_jarvis_video_task_v1',
        );

        if (legacy != null) {
          final data = jsonDecode(legacy) as Map;

          _locked = true;

          if (data['state'] == 'ready' &&
              data['videoUrl'] is String) {
            _legacyUrl = data['videoUrl'] as String;
          }

          _notice = _t(
            'A video from the previous version is saved. '
                'Finish or check that result first.',
            'Мурунку версиядан видео сакталган. Адегенде анын '
                'натыйжасын бүтүрүңүз же текшериңиз.',
            'Сохранено видео из предыдущей версии. Сначала '
                'завершите или проверьте его результат.',
            'Önceki sürümden bir video kaydedilmiş. Önce '
                'sonucunu tamamlayın veya kontrol edin.',
          );
        }
      }
    } catch (_) {
      _locked = true;

      _notice = _t(
        'Could not read the saved task. Reopen this page.',
        'Сакталган тапшырма окулган жок. Баракты кайра ачыңыз.',
        'Не удалось прочитать задачу. Откройте страницу снова.',
        'Kayıtlı görev okunamadı. Sayfayı yeniden açın.',
      );
    }

    if (mounted) {
      setState(() => _loaded = true);
    }
  }

  Future<void> _start(bool publish) async {
    if (!_loaded || _busy || _locked) return;

    if (_prompt.text.trim().isEmpty ||
        _prompt.text.length > 2000 ||
        _caption.text.length > 2200) {
      return;
    }

    setState(() {
      _busy = true;
      _notice = null;
    });

    try {
      _requestId ??= _api.createJarvisRequestId();

      if (_requestId != null && _mode == 'create_publish') {
        publish = true;
      }

      _mode = publish ? 'create_publish' : 'create';

      await _storage.write(
        key: _key,
        value: jsonEncode({
          'requestId': _requestId,
          'title': _title,
          'prompt': _prompt.text.trim(),
          'caption': _caption.text.trim(),
          'mode': _mode,
        }),
      );

      await _api.startAutomation(
        language: widget.language,
        requestId: _requestId!,
        command: publish
            ? 'Create a video and publish it to Instagram'
            : 'Create a video',
        title: _title,
        prompt: _prompt.text.trim(),
        caption: _caption.text.trim(),
      );

      await _storage.delete(key: _key);

      _locked = true;

      if (!mounted) return;

      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => JarvisTasksPage(
            language: widget.language,
          ),
        ),
      );
    } catch (error) {
      // Keep the same request ID after a timeout so retrying
      // does not create another charge or publication.
      if (error is DioException && error.response != null) {
        final data = error.response?.data;
        final code = data is Map ? data['code'] : null;

        if (code == 'FREE_LIMIT_REACHED') {
          _notice = _t(
            'Not enough credits. Open Credits below.',
            'Кредит жетишсиз. Төмөндөн «Кредиттер» бөлүмүн ачыңыз.',
            'Недостаточно кредитов. Откройте «Кредиты» ниже.',
            'Yeterli kredi yok. Aşağıdan Krediler’i açın.',
          );
        }
      }

      _notice ??= _t(
        'Check Tasks and your Instagram connection. You can '
            'resume this same command without creating a duplicate.',
        'Тапшырмаларды жана Instagram байланышын текшериңиз. '
            'Ушул эле буйрукту кайталанган видео жаратпай '
            'улантсаңыз болот.',
        'Проверьте задачи и подключение Instagram. Эту же '
            'команду можно продолжить без создания дубликата.',
        'Görevleri ve Instagram bağlantısını kontrol edin. '
            'Aynı komutu tekrar video oluşturmadan sürdürebilirsiniz.',
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  void dispose() {
    _prompt.dispose();
    _caption.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locked =
        !_loaded || _busy || _locked || _requestId != null;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          _t(
            'Video idea',
            'Видео идеясы',
            'Идея видео',
            'Video fikri',
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.flag_outlined),
            tooltip: AppTranslations.translate(
              widget.language,
              'aiReportButton',
            ),
            onPressed: !_loaded || _busy
                ? null
                : () => showAIContentReport(
                      context: context,
                      api: _api,
                      language: widget.language,
                      contentType: 'chat',
                      content: '$_title\n${_caption.text}',
                      prompt: _prompt.text,
                      model: 'Jarvis',
                    ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            _title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _prompt,
            readOnly: locked,
            minLines: 4,
            maxLines: 8,
            maxLength: 2000,
            decoration: InputDecoration(
              labelText: _t(
                'Video prompt',
                'Видео промпту',
                'Промпт видео',
                'Video istemi',
              ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _caption,
            readOnly: locked,
            minLines: 3,
            maxLines: 6,
            maxLength: 2200,
            decoration: InputDecoration(
              labelText: _t(
                'Caption and hashtags',
                'Сүрөттөмө жана хештегдер',
                'Описание и хештеги',
                'Açıklama ve etiketler',
              ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _t(
              'One 8-second video uses your free video first, '
                  'otherwise 6 credits. Create and publish also '
                  'posts it to the connected Instagram account. '
                  'If you already gave Jarvis a voice command, '
                  'check Tasks instead of starting another video.',
              'Бир 8 секунддук видео адегенде акысыз укукту, '
                  'болбосо 6 кредитти колдонот. Түзүү жана жарыялоо '
                  'аны туташкан Instagram аккаунтуна жайгаштырат. '
                  'Jarvisке үн менен буйрук берген болсоңуз, башка '
                  'видео баштабай «Тапшырмалар» бөлүмүн текшериңиз.',
              'Ролик на 8 секунд использует бесплатное видео, '
                  'иначе 6 кредитов. Создать и опубликовать также '
                  'размещает его в подключённом Instagram. Если '
                  'вы уже дали голосовую команду, проверьте '
                  '«Задачи» вместо повторного создания.',
              '8 saniyelik video önce ücretsiz hakkı, yoksa '
                  '6 krediyi kullanır. Oluştur ve yayınla ayrıca '
                  'bağlı Instagram hesabına gönderir. Zaten sesli '
                  'komut verdiyseniz yeni video yerine Görevler’i '
                  'kontrol edin.',
            ),
          ),
          const SizedBox(height: 16),
          if (_requestId == null) ...[
            FilledButton(
              onPressed: locked ? null : () => _start(false),
              child: Text(
                _t(
                  'Create video',
                  'Видео жаратуу',
                  'Создать видео',
                  'Video oluştur',
                ),
              ),
            ),
            OutlinedButton(
              onPressed: locked ? null : () => _start(true),
              child: Text(
                _t(
                  'Create and publish to Instagram',
                  'Жаратуу жана Instagramга жарыялоо',
                  'Создать и опубликовать в Instagram',
                  'Oluştur ve Instagram’da yayınla',
                ),
              ),
            ),
          ] else
            FilledButton(
              onPressed: _busy || _locked
                  ? null
                  : () => _start(_mode == 'create_publish'),
              child: Text(
                _t(
                  'Resume this command',
                  'Ушул буйрукту улантуу',
                  'Продолжить эту команду',
                  'Bu komutu sürdür',
                ),
              ),
            ),
          TextButton(
            onPressed: _busy
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => JarvisTasksPage(
                          language: widget.language,
                        ),
                      ),
                    ),
            child: Text(
              _t(
                'Tasks',
                'Тапшырмалар',
                'Задачи',
                'Görevler',
              ),
            ),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => CreditsPage(
                          language: widget.language,
                        ),
                      ),
                    ),
            child: Text(
              _t(
                'Credits',
                'Кредиттер',
                'Кредиты',
                'Krediler',
              ),
            ),
          ),
          if (_legacyUrl != null)
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => InstagramReelPage(
                    language: widget.language,
                    initialVideoUrl: _legacyUrl!,
                    initialCaption: _caption.text,
                  ),
                ),
              ),
              child: Text(
                _t(
                  'Open previous video',
                  'Мурунку видеону ачуу',
                  'Открыть предыдущее видео',
                  'Önceki videoyu aç',
                ),
              ),
            ),
          if (_busy) const LinearProgressIndicator(),
          if (_notice != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(_notice!),
            ),
        ],
      ),
    );
  }
}