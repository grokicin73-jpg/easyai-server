class AppTranslations {
  static const Map<String, Map<String, String>> translations = {
    'English': {
      'appName': 'EasyAI',
      'promptPage': 'Prompt Page',
      'createVideo': 'Create Video',
      'enterPrompt': 'Enter your video prompt',
      'generateVideo': 'Generate Video',
      'chooseModel': 'Choose AI Model',
      'startGeneration': 'Start Generation',
      'generatingVideo': 'Generating your AI video...',
      'pleaseWait': 'Please wait...',
      'preparingRequest': 'Preparing request...',
'checkingConnection': 'Checking connection...',
'generationCompleted': 'Generation completed',
      'videoReady': 'Your video is ready!',
      'videoReadyIn': 'Your video was ready in',
      'seconds': 'seconds',
      'downloadVideo': 'Download Video',
      'shareTikTok': 'Share to TikTok',
      'backHome': 'Back to Home',
      'selectLanguage': 'Select Language',
      'selectedModel': 'Selected AI model',
      'aiPreview': 'AI Preview',
      'noModelSelected': 'No model selected',
      'yourPrompt': 'Your prompt',
      'createAnotherVideo': 'Create another video',
    },

    'Кыргызча': {
      'appName': 'EasyAI',
      'promptPage': 'Сүрөттөмө барагы',
      'createVideo': 'Видео түзүү',
      'enterPrompt': 'Видео үчүн сүрөттөмө жазыңыз',
      'generateVideo': 'Видео түзүү',
      'chooseModel': 'AI моделин тандоо',
      'startGeneration': 'Түзүүнү баштоо',
      'generatingVideo': 'AI видео түзүлүп жатат...',
      'pleaseWait': 'Сураныч, күтө туруңуз...',
      'preparingRequest': 'Сурам даярдалууда...',
'checkingConnection': 'Байланыш текшерилүүдө...',
'generationCompleted': 'Түзүү аяктады',
      'videoReady': 'Видео даяр!',
      'videoReadyIn': 'Видео даяр болду',
      'seconds': 'секундада',
      'downloadVideo': 'Видеону жүктөө',
      'shareTikTok': 'TikTok менен бөлүшүү',
      'backHome': 'Башкы бетке кайтуу',
      'selectLanguage': 'Тилди тандоо',
      'selectedModel': 'Тандалган AI модель',
      'aiPreview': 'AI алдын ала көрүү',
      'noModelSelected': 'Модель тандалган жок',
      'yourPrompt': 'Сиздин сүрөттөмөңүз',
      'createAnotherVideo': 'Дагы бир видео түзүү',
    },
  };

  static String translate(String language, String key) {
    return translations[language]?[key] ??
        translations['English']?[key] ??
        key;
  }
}