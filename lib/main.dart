import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'api_service.dart';
import 'translations.dart';
import 'download_service.dart';
import 'package:audioplayers/audioplayers.dart';
void main() {
  runApp(const EasyAIApp());
}

final AudioPlayer _audioPlayer = AudioPlayer();

Future<void> playClickSound() async {
  try {
    await _audioPlayer.play(
      AssetSource('sounds/click.mp3'),
    );
  } catch (e) {
    print("Ovoz fayli topilmadi: $e");
  }
}

class AppData {
  static final apiService = ApiService();
 static String selectedModel = '';
  static String userPrompt = '';
  static String selectedLanguage = "English";

  static String t(String key) {
    return AppTranslations.translations[selectedLanguage]?[key] ?? key;
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

    Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LanguagePage()),
      );
    });
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

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  void _openPromptPage(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PromptPage()),
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
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
               Text(
                AppData.selectedLanguage ==
                "Кыргызча"
               ? "Кош келиңиз"
                :"Welcome to EasyAI",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 14),
               Text(
                AppData.t('createVideo'), 
               
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, color: Colors.white70),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton(
                  onPressed: () => _openPromptPage(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: Text(
                    AppData.t('generateVideo'),
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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
  final TextEditingController promptController = TextEditingController();

  void _generateVideo() {
    AppData.userPrompt = promptController.text.trim();

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AIPreviewPage( 
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
    String modelText = AppData.selectedModel.isEmpty
    ? AppData.t('noModelSelected')
    : AppData.selectedModel;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(AppData.t('promptPage')),
        centerTitle: true,
        backgroundColor: Colors.black,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 25),
             Text(
              AppData.t('enterPrompt'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${AppData.t('selectedModel')}: $modelText',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: Colors.white70),
            ),
            const SizedBox(height: 25),
            TextField(
              controller: promptController,
              maxLines: 6,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: AppData.t('enterPrompt'),
                hintStyle: const TextStyle(color: Colors.white54),
                filled: true,
                fillColor: Colors.white10,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 58,
              child: ElevatedButton(
              onPressed: () {
  _generateVideo();
},
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child:  Text(
                  AppData.t('generateVideo'),
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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
      MaterialPageRoute(builder: (_) => LoadingPage(prompt: AppData.userPrompt,
      selectedModel: selectedModel,
      ),)
    );
  }

  @override
  Widget build(BuildContext context) {
    String selectedModel = AppData.selectedModel;
    String promptText = AppData.userPrompt.isEmpty
    ? 'Сүрөттөмө жазылган жок'
    : AppData.userPrompt;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(AppData.t('aiPreview')),
        centerTitle: true,
        backgroundColor: Colors.black,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
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
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  "${AppData.t('selectedModel')}: "
"${selectedModel == 'No model selected' ? AppData.t('noModelSelected') : selectedModel}",
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, color: Colors.white70),
                ),const SizedBox(height: 10),


                const SizedBox(height: 25),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(
                    promptText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 17,
                      color: Colors.white,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 35),
                const SizedBox(height: 20),

Text(
  "${AppData.t('selectedModel')}: ${AppData.selectedModel == 'No model selected' ? AppData.t('noModelSelected') : AppData.selectedModel}",

  style: const TextStyle(
    color: Colors.white70,
    fontSize: 16,
    fontWeight: FontWeight.w500,
  ),
),

const SizedBox(height: 20),
SizedBox(
  width: double.infinity,
  height: 58,
  child: ElevatedButton(
    onPressed: () async {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const ChooseModelPage(),
        ),
      );

      if (!context.mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AIPreviewPage(
            promptText: promptText,
            selectedModel: AppData.selectedModel,
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
      
      style: TextStyle(
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
                      style: TextStyle(
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
      ),
    );
  }
}

class LoadingPage extends StatefulWidget {
 final String prompt;
  final String selectedModel;

  const LoadingPage({
    super.key,
    required this.prompt,
    required this.selectedModel,
  }); 

  @override
  State<LoadingPage> createState() => _LoadingPageState();
}

class _LoadingPageState extends State<LoadingPage> {
  int percent = 0;
  String statusText = AppData.t('preparingRequest');
  Timer? timer;
bool apiFinished = false;
String aiResult = "";
  @override
  void initState() {
    super.initState();
    statusText = AppData.t('checkingConnection');
   AppData.apiService
    .generateVideoWithVeo(
      prompt: widget.prompt,
      selectedModel: widget.selectedModel,
    )
    .then((message) {
      debugPrint(message);

      if (!mounted) return;

    setState(() {
  aiResult = message;
  print("AI RESULT: $aiResult");
  statusText = AppData.t('generationCompleted');
  apiFinished = true;
});
    });

    timer = Timer.periodic(const Duration(milliseconds: 30), (t) {
      if (!mounted) return;

      setState(() {
  if (percent < 100) {
    percent++;
  }
});

      if (percent >= 100 && apiFinished) {
        t.cancel();

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => ReadyPage(
          prompt: widget.prompt,
            selectedModel: widget.selectedModel,
            videoUrl: aiResult,
          ),
          )
        );
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double progressValue = percent / 100;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
               Text(
                AppData.t('generatingVideo'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Model: ${AppData.selectedModel}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, color: Colors.white70),
              ),
              const SizedBox(height: 30),
              Text(
                '$percent%',
                style: const TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 25),
              Text(
                'About ${(100 - percent)
                ~/ 9} seconds remaining',
                ),
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: LinearProgressIndicator(
                  value: progressValue,
                  minHeight: 14,
                  backgroundColor: Colors.white12,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
class LanguagePage extends StatelessWidget {
  const LanguagePage({super.key});

  void _selectLanguage(BuildContext context, String language) {
  AppData.selectedLanguage = language;

  Navigator.pushReplacement(
    context,
    MaterialPageRoute(
      builder: (_) => const HomePage(),
    ),
  );
}

  Widget _languageButton({
    required BuildContext context,
    required String text,
    required String language,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 62,
      child: ElevatedButton(
        onPressed: () {
          _selectLanguage(context, language);
        },
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
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
             
              const SizedBox(height: 35),
              _languageButton(
                context: context,
                text: '🇰🇬 Кыргызча',
                language: 'Кыргызча',
              ),
              const SizedBox(height: 16),
              _languageButton(
                context: context,
                text: '🇺🇸 English',
                language: 'English',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
class ReadyPage extends StatefulWidget {
  final String prompt;
  final String selectedModel;
final String videoUrl;

 const ReadyPage({
  super.key,
  required this.prompt,
  required this.selectedModel,
  required this.videoUrl,
});
  @override
  State<ReadyPage> createState() => _ReadyPageState();
}

class _ReadyPageState extends State<ReadyPage> {
  late String selectedModel;
VideoPlayerController? _videoController;
bool _videoReady = false;
  @override
  void initState() {
    super.initState();
    selectedModel = widget.selectedModel;
  print("VIDEO URL: ${widget.videoUrl}");
if (widget.videoUrl.isNotEmpty) {
  _videoController = VideoPlayerController.networkUrl(
    Uri.parse(widget.videoUrl),
  )
    ..initialize().then((_) {
      if (!mounted) return;
      setState(() {
        _videoReady = true;
      });
      _videoController!.addListener(() {
  if (mounted) {
    setState(() {});
  }
});
    });
}
  }
  Future<void> _openModelPage(BuildContext context) async {
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

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  void _backToHome(BuildContext context) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => const HomePage(),
      ),
      (route) => false,
    );
  }

  Widget _premiumButton({
    required String text,
    required VoidCallback onPressed,
  }) {
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
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                if (_videoReady && _videoController != null) ...[
  AspectRatio(
    aspectRatio: _videoController!.value.aspectRatio,
    child: GestureDetector(
 onTap: () async {
  final controller = _videoController!;

  if (controller.value.isPlaying) {
    await controller.pause();
  } else {
    final position = controller.value.position.inMilliseconds;
    final duration = controller.value.duration.inMilliseconds;

    if (duration > 0 && position >= duration - 500) {
      await controller.seekTo(Duration.zero);
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
      if (!_videoController!.value.isPlaying)
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
                const Icon(
                  Icons.check_circle,
                  color: Colors.white,
                  size: 90,
                ),
                const SizedBox(height: 24),
                Text(
                  AppData.t('videoReady'),
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
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppData.t('yourPrompt'),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.prompt,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
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
                  text: AppData.t('chooseModel'),
                  onPressed: () {
                    _openModelPage(context);
                  },
                ),
                const SizedBox(height: 16),
                _premiumButton(
                  text: AppData.t('downloadVideo'),
                  onPressed: () async {
  try {
    await DownloadService.downloadVideo(widget.videoUrl);

    if (!mounted) return;

    if (!context.mounted) return;

_showMessage(
  context,
  AppData.t('downloadVideo'),
);
  } catch (e) {
    

   if (!context.mounted) return;

_showMessage(
  context,
  'Video yuklab olinmadi.',
);
  }
},
                ),
                const SizedBox(height: 16),
                _premiumButton(
                  text: AppData.t('createAnotherVideo'),
                  onPressed: () {
                    _backToHome(context);
                  },
                ),
                const SizedBox(height: 16),
                _premiumButton(
                  text: AppData.t('shareTikTok'),
                 onPressed: () async {
  try {
    await DownloadService.downloadVideo(widget.videoUrl);

    if (!mounted) return;

    _showMessage(
      context,
      AppData.t('downloadVideo'),
    );
  } catch (e) {
    if (!mounted) return;

    _showMessage(
      context,
      'Video yuklab olinmadi: $e',
    );
  }
},
                ),
                const SizedBox(height: 16),
                _premiumButton(
                  text: AppData.t('backHome'),
                  onPressed: () {
                    _backToHome(context);
                  },
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

  void _selectModel(BuildContext context, String modelName) {
    AppData.selectedModel = modelName;
    Navigator.pop(context);
  }

  Widget _modelButton({
    required String text,
    required BuildContext context,
  }) {
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
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String currentModel = AppData.selectedModel;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(AppData.t('chooseModel')),
        centerTitle: true,
        backgroundColor: Colors.black,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
               Text(
                AppData.t('chooseModel'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Учурда: $currentModel',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 17, color: Colors.white70),
              ),
              const SizedBox(height: 35),
              _modelButton(text: 'Veo 3', context: context),
              const SizedBox(height: 16),
              _modelButton(text: 'Kling AI', context: context),
              const SizedBox(height: 16),
              _modelButton(text: 'Runway', context: context),
              const SizedBox(height: 16),
              _modelButton(text: 'PixVerse', context: context),
            ],
          ),
        ),
      ),
    );
  }
}