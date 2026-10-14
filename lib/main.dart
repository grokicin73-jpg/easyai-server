import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:image_picker/image_picker.dart';
import 'package:in_app_update/in_app_update.dart';

import 'api_service.dart';
import 'translations.dart';
import 'download_service.dart';
import 'jarvis_page.dart';
import 'ai_content_report.dart';
import 'purchase_service.dart';
import 'credits_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  CreditPurchaseService.instance.start();
  runApp(const EasyAIApp());
}

final AudioPlayer _audioPlayer = AudioPlayer();

Future<void> playClickSound() async {
  try {
    await _audioPlayer.play(
      AssetSource('sounds/click.mp3'),
    );
  } catch (error) {
    debugPrint('Ovoz fayli topilmadi: $error');
  }
}

class AppData {
  static final apiService = ApiService();

  static String selectedModel = 'Veo 3';
  static String userPrompt = '';
  static String selectedLanguage = 'English';
  static String? selectedImagePath;

  static String t(String key) {
    return AppTranslations.translate(selectedLanguage, key);
  }

  static const Map<String, Map<String, String>> _messages = {
    'English': {
      'updateTitle': 'Update available',
      'updateBody': 'A new version of EasyAI is available. Update now?',
      'updateLater': 'Later',
      'updateNow': 'Update',
      'downloadFailed': 'Could not download the video.',
    },
    'Кыргызча': {
      'updateTitle': 'Жаңы версия жеткиликтүү',
      'updateBody':
          'EasyAI колдонмосунун жаңы версиясы бар. Азыр жаңыртасызбы?',
      'updateLater': 'Кийинчерээк',
      'updateNow': 'Жаңыртуу',
      'downloadFailed': 'Видеону жүктөп алуу мүмкүн болгон жок.',
    },
    'Русский': {
      'updateTitle': 'Доступно обновление',
      'updateBody': 'Доступна новая версия EasyAI. Обновить сейчас?',
      'updateLater': 'Позже',
      'updateNow': 'Обновить',
      'downloadFailed': 'Не удалось скачать видео.',
    },
    'Türkçe': {
      'updateTitle': 'Güncelleme mevcut',
      'updateBody':
          'EasyAI uygulamasının yeni bir sürümü mevcut. Şimdi güncellensin mi?',
      'updateLater': 'Daha sonra',
      'updateNow': 'Güncelle',
      'downloadFailed': 'Video indirilemedi.',
    },
  };

  static String message(String key) {
    return _messages[selectedLanguage]?[key] ??
        _messages['English']![key]!;
  }
}

class EasyAIApp extends StatelessWidget {
  const EasyAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'EasyAI',
      theme: ThemeData.dark(useMaterial3: true),
      builder: (context, child) {
        return ColoredBox(
          color: Colors.black,
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.only(bottom: 8),
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: const SplashPage(),
    );
  }
}

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    _startApp();
  }

  Future<void> _startApp() async {
    await Future<void>.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const LanguagePage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Text(
          'EasyAI',
          style: TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: 2,
          ),
        ),
      ),
    );
  }
}

class LanguagePage extends StatefulWidget {
  const LanguagePage({super.key});

  @override
  State<LanguagePage> createState() => _LanguagePageState();
}

class _LanguagePageState extends State<LanguagePage> {
  bool _selecting = false;

  Future<void> _selectLanguage(String language) async {
    if (_selecting) return;

    setState(() => _selecting = true);
    AppData.selectedLanguage = language;

    await _checkUpdate();

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const HomePage(),
      ),
    );
  }

  Future<void> _checkUpdate() async {
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    try {
      final info = await InAppUpdate.checkForUpdate()
          .timeout(const Duration(seconds: 8));

      if (!mounted) return;

      if (info.installStatus == InstallStatus.downloaded) {
        await InAppUpdate.completeFlexibleUpdate();
        return;
      }

      if (info.updateAvailability !=
              UpdateAvailability.updateAvailable ||
          (!info.immediateUpdateAllowed &&
              !info.flexibleUpdateAllowed)) {
        return;
      }

      final updateNow = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(AppData.message('updateTitle')),
          content: Text(AppData.message('updateBody')),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, false),
              child: Text(AppData.message('updateLater')),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, true),
              child: Text(AppData.message('updateNow')),
            ),
          ],
        ),
      );

      if (!mounted || updateNow != true) return;

      if (info.immediateUpdateAllowed) {
        await InAppUpdate.performImmediateUpdate();
      } else if (info.flexibleUpdateAllowed) {
        final result = await InAppUpdate.startFlexibleUpdate();

        if (result == AppUpdateResult.success) {
          await InAppUpdate.completeFlexibleUpdate();
        }
      }
    } catch (error) {
      debugPrint('Update check: $error');
    }
  }

  Widget _languageButton(String text, String language) {
    return SizedBox(
      width: double.infinity,
      height: 62,
      child: ElevatedButton(
        onPressed:
            _selecting ? null : () => _selectLanguage(language),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Тилди тандаңыз'),
        centerTitle: true,
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 35),
              _languageButton('🇰🇬 Кыргызча', 'Кыргызча'),
              const SizedBox(height: 16),
              _languageButton('🇺🇸 English', 'English'),
              const SizedBox(height: 16),
              _languageButton('🇷🇺 Русский', 'Русский'),
              const SizedBox(height: 16),
              _languageButton('🇹🇷 Türkçe', 'Türkçe'),
              if (_selecting) ...[
                const SizedBox(height: 24),
                const CircularProgressIndicator(
                  color: Colors.white,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  static Future<void> _buyCredits(
    BuildContext context,
  ) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CreditsPage(
          language: AppData.selectedLanguage,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('EasyAI'),
        centerTitle: true,
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(
              Icons.account_balance_wallet_outlined,
            ),
            onPressed: () => _buyCredits(context),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                AppData.t('welcome'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                AppData.t('createVideo'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PromptPage(),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: Text(
                    AppData.t('generateVideo'),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 58,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => JarvisPage(
                          language: AppData.selectedLanguage,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text(
                    'Jarvis',
                    style: TextStyle(fontSize: 20),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.lightBlueAccent,
                    side: const BorderSide(
                      color: Colors.lightBlueAccent,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PromptPage extends StatefulWidget {
  const PromptPage({super.key});

  @override
  State<PromptPage> createState() => _PromptPageState();
}

class _PromptPageState extends State<PromptPage> {
  final TextEditingController promptController =
      TextEditingController();

  final ImagePicker _picker = ImagePicker();

  XFile? selectedImage;

  @override
  void initState() {
    super.initState();
    AppData.selectedImagePath = null;
  }

  Future<void> _pickImage() async {
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
    );

    if (!mounted || image == null) return;

    setState(() {
      selectedImage = image;
      AppData.selectedImagePath = image.path;
    });
  }

  void _generateVideo() {
    AppData.userPrompt = promptController.text.trim();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AIPreviewPage(
          promptText: AppData.userPrompt,
          selectedModel: AppData.selectedModel,
        ),
      ),
    );
  }

  @override
  void dispose() {
    promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final modelText = AppData.selectedModel.isEmpty
        ? AppData.t('noModelSelected')
        : AppData.selectedModel;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(AppData.t('promptPage')),
        centerTitle: true,
        backgroundColor: Colors.black,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 25),
            Text(
              AppData.t('enterPrompt'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${AppData.t('selectedModel')}: $modelText',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 25),
            TextField(
              controller: promptController,
              maxLines: 6,
              maxLength: 2000,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: AppData.t('enterPrompt'),
                hintStyle: const TextStyle(
                  color: Colors.white54,
                ),
                filled: true,
                fillColor: Colors.white10,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(
                    color: Colors.white24,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(
                    color: Colors.white24,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            ElevatedButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.add_photo_alternate),
              label: Text(AppData.t('addPhoto')),
            ),
            if (selectedImage != null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  '✓',
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: 20,
                  ),
                ),
              ),
            const SizedBox(height: 45),
            SizedBox(
              width: double.infinity,
              height: 58,
              child: ElevatedButton(
                onPressed: _generateVideo,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: Text(
                  AppData.t('generateVideo'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AIPreviewPage extends StatelessWidget {
  const AIPreviewPage({
    super.key,
    required this.promptText,
    required this.selectedModel,
  });

  final String promptText;
  final String selectedModel;

  void _startGeneration(BuildContext context) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => LoadingPage(
          prompt: promptText,
          selectedModel: selectedModel,
          imagePath: AppData.selectedImagePath,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shownPrompt = promptText.isEmpty
        ? AppData.t('noPrompt')
        : promptText;

    final shownModel = selectedModel.isEmpty ||
            selectedModel == 'No model selected'
        ? AppData.t('noModelSelected')
        : selectedModel;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(AppData.t('aiPreview')),
        centerTitle: true,
        backgroundColor: Colors.black,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.video_collection,
                size: 120,
                color: Colors.white,
              ),
              const SizedBox(height: 25),
              Text(
                AppData.t('aiPreview'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '${AppData.t('selectedModel')}: $shownModel',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 25),
              Container(
                width: double.infinity,
                height: 140,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white24),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    shownPrompt,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 17,
                      color: Colors.white,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 35),
              SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            const ChooseModelPage(),
                      ),
                    );

                    if (!context.mounted) return;

                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AIPreviewPage(
                          promptText: promptText,
                          selectedModel:
                              AppData.selectedModel,
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: Text(
                    AppData.t('chooseModel'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 15),
              SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton(
                  onPressed: () => _startGeneration(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: Text(
                    AppData.t('startGeneration'),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LoadingPage extends StatefulWidget {
  const LoadingPage({
    super.key,
    required this.prompt,
    required this.selectedModel,
    this.imagePath,
  });

  final String prompt;
  final String selectedModel;
  final String? imagePath;

  @override
  State<LoadingPage> createState() => _LoadingPageState();
}

class _LoadingPageState extends State<LoadingPage> {
  bool isLoading = true;
  bool freeLimitReached = false;

  String statusText = AppData.t('generatingVideo');

  @override
  void initState() {
    super.initState();
    _generateVideo();
  }

  Future<void> _generateVideo() async {
    try {
      final videoUrl =
          await AppData.apiService.generateVideoWithVeo(
        prompt: widget.prompt,
        selectedModel: widget.selectedModel,
        imagePath: widget.imagePath,
      );

      if (!mounted) return;

      if (videoUrl.trim().isEmpty) {
        throw Exception('VIDEO_GENERATION_FAILED');
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ReadyPage(
            prompt: widget.prompt,
            selectedModel: widget.selectedModel,
            videoUrl: videoUrl,
          ),
        ),
      );
    } catch (error) {
      debugPrint('VIDEO XATO: $error');

      if (!mounted) return;

      final errorText = error.toString();

      setState(() {
        isLoading = false;
        freeLimitReached =
            errorText.contains('FREE_LIMIT_REACHED');

        if (freeLimitReached) {
          statusText = AppData.t('freeLimitReached');
        } else if (errorText.contains('API limiti tugagan') ||
            errorText.contains('Server band')) {
          statusText = AppData.t('serverBusy');
        } else {
          statusText = AppData.t('videoError');
        }
      });
    }
  }

  void _backHome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const HomePage(),
      ),
      (_) => false,
    );
  }

  Future<void> _buyCredits() async {
    await HomePage._buyCredits(context);

    if (!mounted) return;

    _backHome();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !isLoading,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  AppData.t(
                    isLoading
                        ? 'generatingVideo'
                        : 'videoFailed',
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '${AppData.t('selectedModel')}: '
                  '${widget.selectedModel}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 30),
                if (isLoading)
                  const CircularProgressIndicator(
                    color: Colors.white,
                  ),
                const SizedBox(height: 25),
                Text(
                  statusText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    color: Colors.white,
                  ),
                ),
                if (!isLoading) ...[
                  const SizedBox(height: 25),
                  if (freeLimitReached)
                    ElevatedButton(
                      onPressed: _buyCredits,
                      child: Text(AppData.t('buyCredits')),
                    ),
                  TextButton(
                    onPressed: _backHome,
                    child: Text(AppData.t('backHome')),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ReadyPage extends StatefulWidget {
  const ReadyPage({
    super.key,
    required this.prompt,
    required this.selectedModel,
    required this.videoUrl,
  });

  final String prompt;
  final String selectedModel;
  final String videoUrl;

  @override
  State<ReadyPage> createState() => _ReadyPageState();
}

class _ReadyPageState extends State<ReadyPage> {
  late String selectedModel;

  VideoPlayerController? _videoController;

  bool _videoReady = false;
  String? _videoError;

  @override
  void initState() {
    super.initState();

    selectedModel = widget.selectedModel;
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      final uri = Uri.tryParse(widget.videoUrl.trim());

      if (uri == null ||
          !uri.hasAuthority ||
          (uri.scheme != 'https' && uri.scheme != 'http')) {
        throw Exception('Invalid video URL');
      }

      final controller =
          VideoPlayerController.networkUrl(uri);

      _videoController = controller;

      await controller.initialize();

      if (!mounted) return;

      controller.addListener(_onVideoChanged);

      setState(() {
        _videoReady = true;
        _videoError = null;
      });
    } catch (error) {
      debugPrint('VIDEO PLAYER ERROR: $error');

      if (!mounted) return;

      setState(() {
        _videoReady = false;
        _videoError = AppData.t('videoError');
      });
    }
  }

  void _onVideoChanged() {
    if (!mounted) return;

    final controller = _videoController;

    if (controller == null) return;

    setState(() {
      if (controller.value.hasError) {
        _videoReady = false;
        _videoError = AppData.t('videoError');
      }
    });
  }

  @override
  void dispose() {
    _videoController?.removeListener(_onVideoChanged);
    _videoController?.dispose();

    super.dispose();
  }

  Future<void> _openModelPage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ChooseModelPage(),
      ),
    );

    if (!mounted) return;

    setState(() {
      selectedModel = AppData.selectedModel;
    });
  }

  void _backToHome() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => const HomePage(),
      ),
      (_) => false,
    );
  }

  Future<void> _downloadVideo() async {
    try {
      await DownloadService.downloadVideo(widget.videoUrl);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppData.t('downloadVideo')),
        ),
      );
    } catch (error) {
      debugPrint('VIDEO DOWNLOAD ERROR: $error');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppData.message('downloadFailed'),
          ),
        ),
      );
    }
  }

  Widget _premiumButton(
    String text,
    VoidCallback onPressed,
  ) {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shownModel = selectedModel.isEmpty
        ? AppData.t('noModelSelected')
        : selectedModel;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(AppData.t('videoReady')),
        actions: [
          IconButton(
            tooltip: AppData.t('aiReportButton'),
            icon: const Icon(Icons.flag_outlined),
            onPressed: () async {
              await showAIContentReport(
                context: context,
                api: AppData.apiService,
                language: AppData.selectedLanguage,
                contentType: 'video',
                prompt: widget.prompt,
                model: widget.selectedModel,
                videoUrl: widget.videoUrl,
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                if (_videoReady &&
                    _videoController != null) ...[
                  AspectRatio(
                    aspectRatio:
                        _videoController!.value.aspectRatio,
                    child: GestureDetector(
                      onTap: () async {
                        final controller = _videoController!;

                        if (controller.value.isPlaying) {
                          await controller.pause();
                        } else {
                          final position = controller
                              .value.position.inMilliseconds;

                          final duration = controller
                              .value.duration.inMilliseconds;

                          if (duration > 0 &&
                              position >= duration - 500) {
                            await controller.seekTo(
                              Duration.zero,
                            );
                          }

                          await controller.play();
                        }

                        if (mounted) {
                          setState(() {});
                        }
                      },
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          VideoPlayer(_videoController!),
                          if (!_videoController!
                              .value.isPlaying)
                            const Icon(
                              Icons.play_circle_fill,
                              color: Colors.white,
                              size: 80,
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Icon(
                  _videoError != null
                      ? Icons.error_outline
                      : Icons.check_circle,
                  color: Colors.white,
                  size: 90,
                ),
                const SizedBox(height: 24),
                Text(
                  _videoError ?? AppData.t('videoReady'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 28),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white24,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppData.t('yourPrompt'),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 120,
                        child: SingleChildScrollView(
                          child: Text(
                            widget.prompt,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        AppData.t('selectedModel'),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        shownModel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _premiumButton(
                  AppData.t('chooseModel'),
                  _openModelPage,
                ),
                const SizedBox(height: 16),
                _premiumButton(
                  AppData.t('downloadVideo'),
                  _downloadVideo,
                ),
                const SizedBox(height: 16),
                _premiumButton(
                  AppData.t('createAnotherVideo'),
                  _backToHome,
                ),
                const SizedBox(height: 16),
                _premiumButton(
                  AppData.t('shareTikTok'),
                  _downloadVideo,
                ),
                const SizedBox(height: 16),
                _premiumButton(
                  AppData.t('backHome'),
                  _backToHome,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ChooseModelPage extends StatelessWidget {
  const ChooseModelPage({super.key});

  void _selectModel(
    BuildContext context,
    String modelName,
  ) {
    AppData.selectedModel = modelName;
    Navigator.pop(context);
  }

  Widget _modelButton(
    String text,
    BuildContext context,
  ) {
    return SizedBox(
      width: double.infinity,
      height: 62,
      child: ElevatedButton(
        onPressed: text == 'Veo 3'
            ? () {
                unawaited(playClickSound());
                _selectModel(context, text);
              }
            : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(AppData.t('chooseModel')),
        centerTitle: true,
        backgroundColor: Colors.black,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                AppData.t('chooseModel'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${AppData.t('selectedModel')}: '
                '${AppData.selectedModel}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 35),
              _modelButton('Veo 3', context),
              const SizedBox(height: 16),
              _modelButton('Kling AI', context),
              const SizedBox(height: 16),
              _modelButton('Runway', context),
              const SizedBox(height: 16),
              _modelButton('PixVerse', context),
            ],
          ),
        ),
      ),
    );
  }
}