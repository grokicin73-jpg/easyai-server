import "dotenv/config";
import express from "express";
import cors from "cors";
import path from "path";
import crypto from "crypto";
import { fileURLToPath } from "url";
import { mkdir, writeFile, readFile } from "fs/promises";
import multer from "multer";
import { initializeApp, cert } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { google } from "googleapis";
import { attachJarvis } from "./jarvis_server.js";
import { attachInstagram } from "./instagram_server.js";
import { attachInstagramWebhook } from "./instagram_webhook.js";
const app = express();
const upload = multer({ storage: multer.memoryStorage() });
const PORT = process.env.PORT || 3002;



const GEMINI_API_KEY =
  process.env.GEMINI_API_KEY || process.env.GOOGLE_API_KEY;

const firebaseCredentials = process.env.FIREBASE_CREDENTIALS
  ? JSON.parse(process.env.FIREBASE_CREDENTIALS)
  : JSON.parse(
      await readFile(
        new URL("./easyai-bc97f-4e135dcd7bac.json", import.meta.url),
        "utf8"
      )
    );

initializeApp({
  credential: cert(firebaseCredentials),
});

const db = getFirestore();
const vertexAuth = new google.auth.GoogleAuth({
  credentials: firebaseCredentials,
  scopes: ["https://www.googleapis.com/auth/cloud-platform"],
});
const androidPublisher = google.androidpublisher("v3");

const googleAuth = new google.auth.GoogleAuth({
  credentials: firebaseCredentials,
  scopes: ["https://www.googleapis.com/auth/androidpublisher"],
});
const FREE_VIDEOS = 1;
const VIDEO_CREDIT_COST = 6;
const REVIEW_ACCESS_CODE =
  (process.env.REVIEW_ACCESS_CODE || "").trim();

async function getUserUsage(userId) {
  const userRef = db.collection("users").doc(userId);
  const userDoc = await userRef.get();
  console.log("FIRESTORE RAW USER:", userId, userDoc.exists, userDoc.data());

  if (!userDoc.exists) {
    const newUser = {
      freeVideosRemaining: FREE_VIDEOS,
      credits: 0,
      createdAt: FieldValue.serverTimestamp(),
    };

    await userRef.set(newUser);
    return newUser;
  }

  return userDoc.data();
}
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const videosDirectory = path.join(__dirname, "generated-videos");

await mkdir(videosDirectory, { recursive: true });

app.use(cors());
app.get("/instagram/webhook", (req, res) => {
  const expectedToken =
    (process.env.INSTAGRAM_VERIFY_TOKEN || "").trim();

  const mode = req.query["hub.mode"];
  const token = req.query["hub.verify_token"];
  const challenge = req.query["hub.challenge"];

  if (!expectedToken) {
    return res.status(503).send("Webhook token sozlanmagan.");
  }

  if (
    mode === "subscribe" &&
    typeof token === "string" &&
    token === expectedToken &&
    typeof challenge === "string" &&
    challenge.length > 0
  ) {
    return res.status(200).type("text/plain").send(challenge);
  }

  return res.sendStatus(403);
});
app.use(express.json({
  limit: "2mb",
  verify: (req, res, buffer) => {
    if (req.path === "/instagram/webhook") {
      req.instagramRawBody = Buffer.from(buffer);
    }
  },
}));
attachInstagram(app, db, { videosDirectory });
attachInstagramWebhook(app, db);

app.use(
  "/videos",
  express.static(videosDirectory, {
    acceptRanges: true,
    cacheControl: true,
    maxAge: "1h",
  }),
);



function wait(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function parseJsonResponse(response) {
  const responseText = await response.text();

  let data;

  try {
    data = JSON.parse(responseText);
  } catch {
    throw new Error(
      `JSON bo'lmagan javob qaytardi. HTTP ${response.status}`,
    );
  }

  return data;
}



  



      
        
      
    

    

    
      
        
          
      
    

    
    

    
      
    


      
        
      

      
    

  
      
        
      
    

    
      
        
      
    

  
  

  
    
  


async function saveVideo(remoteVideoUrl, videoId) {
  let videoBuffer;

  if (remoteVideoUrl.startsWith("data:")) {
    const match = remoteVideoUrl.match(
      /^data:video\/[^;,]+;base64,([\s\S]+)$/
    );

    if (!match) {
      throw new Error("Video base64 formati noto'g'ri.");
    }

    videoBuffer = Buffer.from(match[1], "base64");
  } else {
    const response = await fetch(remoteVideoUrl, {
      headers: {
        "x-goog-api-key": GEMINI_API_KEY,
      },
    });

    if (!response.ok) {
      throw new Error(
        `Tayyor videoni yuklab olishda xato. HTTP ${response.status}`
      );
    }

    videoBuffer = Buffer.from(await response.arrayBuffer());
  }

  if (videoBuffer.length === 0) {
    throw new Error("Video fayli bo'sh.");
  }

  const fileName = `${videoId}.mp4`;
  const filePath = path.join(videosDirectory, fileName);

  await writeFile(filePath, videoBuffer);
  return fileName;
}
async function fetchWithRetry(url, options = {}, retries = 3) {
  for (let attempt = 1; attempt <= retries; attempt++) {
    try {
      const response = await fetch(url, options);

      if (
        response.ok ||
        ![429, 500, 502, 503, 504].includes(response.status)
      ) {
        return response;
      }

      console.log(`VEO temporary error ${response.status}. Retry ${attempt}/${retries}`);
      if (response.status === 429) console.log("VEO 429 BODY:", await response.clone().text());
    } catch (error) {
      console.log(`VEO network error. Retry ${attempt}/${retries}:`, error.message);

      if (attempt === retries) {
        throw error;
      }
    }

    if (attempt < retries) {
      await new Promise((resolve) =>
        setTimeout(resolve, attempt * 65000)
      );
    }
  }

  throw new Error("Veo request failed after retries");
}
async function createVeoLiteVideo(prompt, imageFile = null, attempt = 1) {
  const model = "veo-3.1-lite-generate-001";
const projectId = "easyai-bc97f";
const location = "us-central1";
const url =
  `https://${location}-aiplatform.googleapis.com/v1/projects/${projectId}/locations/${location}/publishers/google/models/${model}:predictLongRunning`;

  const instance = { prompt };

  if (imageFile) {
  instance.image = {
    bytesBase64Encoded: imageFile.buffer.toString("base64"),
    mimeType: imageFile.mimetype || "image/jpeg",
  };
}
  
 const authClient = await vertexAuth.getClient();
const accessToken = await authClient.getAccessToken();
console.log("TOKEN BOR:", !!(accessToken.token || accessToken)); 
console.log("VEO REQUEST START:", new Date().toISOString(), "IMAGE:", !!imageFile);
  const response = await fetchWithRetry(url, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${accessToken.token || accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      instances: [instance],
      parameters: {
        
        resolution: "720p",
        aspectRatio: imageFile ? "9:16" : "16:9",
        durationSeconds: 8,
      },
    }),
  });

  const data = await response.json();
  console.log("VEO REQUEST RESPONSE:", new Date().toISOString(), "IMAGE:", !!imageFile);

  if (!response.ok) {
    console.error("Veo start error:", data);
    throw new Error("Veo video creation failed");
  }

  const operationName = data?.name;

  if (!operationName) {
    console.error("Veo operation missing:", data);
    throw new Error("Veo operation name missing");
  }

  for (let i = 0; i < 120; i++) {
    await new Promise((resolve) => setTimeout(resolve, 10000));

    const statusResponse = await fetchWithRetry(
  `https://${location}-aiplatform.googleapis.com/v1/projects/${projectId}/locations/${location}/publishers/google/models/${model}:fetchPredictOperation`,
  {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${accessToken.token || accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      operationName: operationName,
    }),
  }
);

    const statusData = await statusResponse.json();
    console.log("VEO STATUS:", {
  done: statusData?.done === true,
  error: statusData?.error || null,
});

    if (!statusResponse.ok) {
      console.error("Veo status error:", statusData);
      throw new Error("Veo status check failed");
    }

    if (statusData?.done === true) {
  const video =
  statusData?.response?.generateVideoResponse
    ?.generatedSamples?.[0]?.video ||
  statusData?.response?.videos?.[0];

  const videoUrl = video?.uri;
  
    const videoBase64 =
  video?.bytesBase64Encoded ||
  video?.encodedVideo ||
  video?.videoBytes ||
  video?.inlineData?.data ||
  video?.data ||
  Object.entries(video || {}).find(
    ([key, value]) =>
      key !== "mimeType" &&
      typeof value === "string" &&
      value.length > 1000,
  )?.[1];

  if (videoUrl) {
    return videoUrl;
  }

  if (videoBase64) {
    const mimeType = video?.mimeType || "video/mp4";
    return `data:${mimeType};base64,${videoBase64}`;
  }

  const errorCode = statusData?.error?.code;

  if (errorCode === 13 && attempt < 3) {
    console.warn(
      `VEO internal server error. Automatic retry ${attempt + 1}/3 in 10 seconds...`,
    );
    await new Promise((resolve) => setTimeout(resolve, 10000));
    return createVeoLiteVideo(prompt, imageFile, attempt + 1);
  }

  console.error("Veo video data missing:", {
  error: statusData?.error || null,
  responseKeys: Object.keys(statusData?.response || {}),
  filteredCount: statusData?.response?.raiMediaFilteredCount || 0,
  filteredReasons: statusData?.response?.raiMediaFilteredReasons || [],
});
  throw new Error("Veo video data missing");
}
  }

  throw new Error("Veo video timed out");
}
app.get("/", (req, res) => {
  res.json({
    success: true,
  });
});

app.get("/health", (req, res) => {
  res.json({
    success: true,
    status: "healthy",
  });
});
app.get("/privacy", (req, res) => {
  res.type("html").send(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>EasyAI Pro — Privacy Policy</title>
  <style>
    body {
      margin: 0;
      background: #111;
      color: #eee;
      font: 16px/1.7 Arial, sans-serif;
    }
    main {
      max-width: 850px;
      margin: auto;
      padding: 28px 20px;
    }
    a { color: #91caff; }
    section {
      margin: 32px 0;
      padding-bottom: 24px;
      border-bottom: 1px solid #444;
    }
    h1, h2, h3 { line-height: 1.3; }
  </style>
</head>
<body>
<main>
  <h1>EasyAI / EasyAI Pro</h1>
  <nav>
    <a href="#en">English</a> ·
    <a href="#ky">Кыргызча</a> ·
    <a href="#ru">Русский</a> ·
    <a href="#tr">Türkçe</a>
  </nav>

  <section id="en" lang="en">
    <h2>Privacy Policy</h2>
    <p>Updated: 12 October 2026.
    Contact: <a href="mailto:grokicin73@gmail.com">grokicin73@gmail.com</a>.</p>

    <h3>Data and purposes</h3>
    <p>EasyAI processes prompts, selected images, and microphone audio
    when you use the corresponding AI features. These inputs are sent
    to Google AI services to generate responses or videos.
    Device or installation identifiers, usage counters, credit balances,
    and purchase verification data are used to provide free allowances,
    manage credits, verify purchases, and prevent misuse.</p>

    <p>If you connect Instagram, we process account identifiers,
    profile information, granted permissions, encrypted access tokens,
    connection dates, publishing records, and product catalogue data.
    When messaging is enabled, we receive message text, sender and
    recipient identifiers, message identifiers, and available timestamps.
    This supports the Instagram features you use.
    Instagram login takes place through Instagram; do not send your
    Instagram password to EasyAI support.</p>

    <h3>Service providers and access</h3>
    <p>Google AI, Firebase, Render, Meta/Instagram, and Google Play
    process relevant data to provide AI, storage, hosting, Instagram,
    and payment services. Their own privacy policies also apply.
    Generated videos can be accessible to anyone who has their direct
    video URL. Avoid submitting confidential content.</p>

    <h3>Storage and deletion</h3>
    <p>Backend connections use HTTPS, and stored Instagram access tokens
    are encrypted. Database records remain stored until removed;
    no general automatic deletion period is currently configured.
    Generated files may become unavailable when server storage is reset.
    Disconnecting Instagram should not be treated as deletion of all
    previously stored data.</p>

    <p>To request access to or deletion of your EasyAI data, email
    <a href="mailto:grokicin73@gmail.com">grokicin73@gmail.com</a>
    with the subject “EasyAI data deletion” and identify the connected
    Instagram account or relevant app installation.
    Requests are handled manually and ownership must be verified.
    Do not include passwords or access tokens.
    We will explain which records can be removed and any records that
    must be retained before completing the request.
    Data already published on Instagram or held by service providers
    is also subject to their own controls and retention practices.</p>
  </section>

  <section id="ky" lang="ky">
    <h2>Купуялык саясаты</h2>
    <p>Жаңыртылган күнү: 2026-жылдын 12-октябры.
    Байланыш: <a href="mailto:grokicin73@gmail.com">grokicin73@gmail.com</a>.</p>

    <h3>Маалыматтар жана максаттар</h3>
    <p>Тиешелүү AI функцияларын колдонгондо EasyAI тексттик
    суроо-талаптарды, тандалган сүрөттөрдү жана микрофон үнүн иштетет.
    Алар жооп же видео түзүү үчүн Google AI кызматтарына жөнөтүлөт.
    Түзмөк же орнотуу идентификаторлору, колдонуу эсептегичтери,
    кредит балансы жана сатып алууну текшерүү маалыматтары акысыз
    мүмкүнчүлүктөрдү, кредиттерди жана төлөмдөрдү башкаруу,
    ошондой эле кыянаттык менен пайдаланууну алдын алуу үчүн колдонулат.</p>

    <p>Instagram туташтырылса, аккаунт идентификаторлору, профиль,
    берилген уруксаттар, шифрленген кирүү токендери, туташуу даталары,
    жарыялоо жазуулары жана товар каталогу иштетилет.
    Билдирүүлөр иштетилгенде билдирүү тексти, жөнөтүүчү жана алуучу
    идентификаторлору, билдирүү идентификатору жана жеткиликтүү
    убакыт белгилери алынат. Бул колдонулган Instagram функцияларын
    камсыз кылат. Кирүү Instagram аркылуу жүргүзүлөт;
    колдоо кызматына Instagram сырсөзүңүздү жөнөтпөңүз.</p>

    <h3>Кызматтар жана жеткиликтүүлүк</h3>
    <p>Google AI, Firebase, Render, Meta/Instagram жана Google Play
    тиешелүү маалыматтарды AI, сактоо, хостинг, Instagram жана
    төлөм кызматтары үчүн иштетет. Алардын купуялык саясаттары да
    колдонулат. Түзүлгөн видеонун түз шилтемесин билген адам аны
    көрө алышы мүмкүн. Жашыруун маалыматтарды жөнөтүүдөн сак болуңуз.</p>

    <h3>Сактоо жана өчүрүү</h3>
    <p>Сервер байланыштары HTTPS колдонот, сакталган Instagram токендери
    шифрленет. База жазуулары өчүрүлгөнгө чейин сакталат;
    жалпы автоматтык өчүрүү мөөнөтү азырынча коюлган эмес.
    Сервер сактагычы жаңырганда видео файлдар жеткиликсиз болушу мүмкүн.
    Instagram байланышын үзүү бардык мурдагы маалыматтарды өчүрбөйт.</p>

    <p>Маалыматтарга жетүү же аларды өчүрүү үчүн
    <a href="mailto:grokicin73@gmail.com">grokicin73@gmail.com</a>
    дарегине “EasyAI data deletion” темасы менен жазыңыз.
    Туташкан Instagram аккаунтун же колдонмонун тиешелүү орнотуусун
    көрсөтүңүз. Сурам кол менен каралат жана ээлик текшерилет.
    Сырсөздөрдү же токендерди жөнөтпөңүз.
    Өчүрүлө турган жана сакталууга тийиш болгон жазуулар тууралуу
    сурам аткарылганга чейин түшүндүрөбүз.
    Instagramда жарыяланган же башка кызматтар сактаган маалыматтарга
    ошол кызматтардын башкаруу жана сактоо эрежелери да колдонулат.</p>
  </section>

  <section id="ru" lang="ru">
    <h2>Политика конфиденциальности</h2>
    <p>Обновлено: 12 октября 2026 года.
    Контакт: <a href="mailto:grokicin73@gmail.com">grokicin73@gmail.com</a>.</p>

    <h3>Данные и цели</h3>
    <p>При использовании соответствующих функций EasyAI обрабатывает
    запросы, выбранные изображения и звук микрофона.
    Эти данные передаются сервисам Google AI для создания ответов
    или видео. Идентификаторы устройства или установки, счётчики
    использования, баланс кредитов и данные проверки покупок
    используются для предоставления бесплатного лимита, управления
    кредитами, проверки платежей и предотвращения злоупотреблений.</p>

    <p>При подключении Instagram обрабатываются идентификаторы аккаунта,
    профиль, предоставленные разрешения, зашифрованные токены доступа,
    даты подключения, записи публикаций и каталог товаров.
    При включении сообщений принимаются текст, идентификаторы
    отправителя, получателя и сообщения, а также доступные временные
    отметки. Это обеспечивает используемые функции Instagram.
    Авторизация проходит через Instagram;
    не отправляйте пароль Instagram службе поддержки EasyAI.</p>

    <h3>Поставщики услуг и доступ</h3>
    <p>Google AI, Firebase, Render, Meta/Instagram и Google Play
    обрабатывают соответствующие данные для работы AI, хранения,
    хостинга, Instagram и платежей. Также действуют их собственные
    политики конфиденциальности. Созданное видео может быть доступно
    любому, кто знает его прямую ссылку.
    Не отправляйте конфиденциальные материалы.</p>

    <h3>Хранение и удаление</h3>
    <p>Соединения с сервером используют HTTPS, а сохранённые токены
    Instagram зашифрованы. Записи базы хранятся до удаления;
    общий срок автоматического удаления пока не настроен.
    Видео могут стать недоступными при сбросе серверного хранилища.
    Отключение Instagram не означает удаление всех ранее
    сохранённых данных.</p>

    <p>Для доступа к своим данным или запроса удаления напишите на
    <a href="mailto:grokicin73@gmail.com">grokicin73@gmail.com</a>
    с темой «EasyAI data deletion». Укажите подключённый аккаунт
    Instagram или соответствующую установку приложения.
    Запросы рассматриваются вручную с проверкой принадлежности.
    Не присылайте пароли и токены.
    До выполнения запроса мы объясним, какие записи можно удалить
    и какие необходимо сохранить.
    На опубликованные в Instagram данные и данные у поставщиков
    услуг также распространяются их правила управления и хранения.</p>
  </section>

  <section id="tr" lang="tr">
    <h2>Gizlilik Politikası</h2>
    <p>Güncelleme: 12 Ekim 2026.
    İletişim: <a href="mailto:grokicin73@gmail.com">grokicin73@gmail.com</a>.</p>

    <h3>Veriler ve amaçlar</h3>
    <p>İlgili AI özelliklerini kullandığınızda EasyAI istemleri,
    seçilen görselleri ve mikrofon sesini işler.
    Bu girdiler yanıt veya video oluşturmak için Google AI
    hizmetlerine gönderilir. Cihaz veya kurulum kimlikleri,
    kullanım sayaçları, kredi bakiyesi ve satın alma doğrulama
    verileri ücretsiz kullanım hakkını ve kredileri yönetmek,
    ödemeleri doğrulamak ve kötüye kullanımı önlemek için kullanılır.</p>

    <p>Instagram bağlandığında hesap kimlikleri, profil bilgileri,
    verilen izinler, şifrelenmiş erişim belirteçleri, bağlantı tarihleri,
    yayın kayıtları ve ürün kataloğu işlenir.
    Mesajlaşma etkinse mesaj metni, gönderen ve alıcı kimlikleri,
    mesaj kimliği ve mevcut zaman bilgileri alınır.
    Bunlar kullandığınız Instagram özelliklerini sağlar.
    Giriş Instagram üzerinden yapılır;
    Instagram şifrenizi EasyAI desteğine göndermeyin.</p>

    <h3>Hizmet sağlayıcıları ve erişim</h3>
    <p>Google AI, Firebase, Render, Meta/Instagram ve Google Play,
    AI, depolama, barındırma, Instagram ve ödeme hizmetleri için
    ilgili verileri işler. Kendi gizlilik politikaları da geçerlidir.
    Oluşturulan videolar doğrudan video bağlantısını bilen kişilere
    açık olabilir. Gizli içerik göndermekten kaçının.</p>

    <h3>Saklama ve silme</h3>
    <p>Sunucu bağlantıları HTTPS kullanır ve saklanan Instagram erişim
    belirteçleri şifrelenir. Veritabanı kayıtları silinene kadar
    saklanır; genel bir otomatik silme süresi henüz yapılandırılmamıştır.
    Sunucu depolaması sıfırlandığında videolar erişilemez olabilir.
    Instagram bağlantısını kesmek, önceki tüm verileri silmez.</p>

    <p>Verilerinize erişim veya silme talebi için
    <a href="mailto:grokicin73@gmail.com">grokicin73@gmail.com</a>
    adresine “EasyAI data deletion” konusuyla yazın.
    Bağlı Instagram hesabını veya ilgili uygulama kurulumunu belirtin.
    Talepler elle incelenir ve sahiplik doğrulanır.
    Şifre veya erişim belirteci göndermeyin.
    Talebi tamamlamadan önce silinebilecek kayıtları ve saklanması
    gereken kayıtları açıklayacağız.
    Instagram'da yayınlanan veya hizmet sağlayıcılarında tutulan
    veriler onların yönetim ve saklama kurallarına da tabidir.</p>
  </section>
</main>
</body>
</html>`);
});

app.post("/api/generate-video", upload.single("image"), async (req, res) => {
  console.log("=== GENERATE VIDEO REQUEST KELDI ===");
  try {
    console.log("UPLOAD DEBUG:", {
  hasImage: !!req.file,
  mimeType: req.file?.mimetype,
  size: req.file?.size,
});
    const prompt =
      typeof req.body?.prompt === "string"
        ? req.body.prompt.trim()
        : "";

    if (!prompt) {
      return res.status(400).json({
        success: false,
        error: "Prompt yozilmagan.",
      });
    }

    
const deviceId =
  typeof req.body?.deviceId === "string"
    ? req.body.deviceId.trim()
    : "";

if (!deviceId) {
  return res.status(400).json({
    success: false,
    error: "Device ID topilmadi.",
  });
}
console.log("DEVICE ID:", deviceId);
const reviewCode =
  typeof req.body?.reviewCode === "string"
    ? req.body.reviewCode.trim()
    : "";

const isReviewAccess =
  REVIEW_ACCESS_CODE.length > 0 &&
  reviewCode === REVIEW_ACCESS_CODE;
const usage = await getUserUsage(deviceId);

console.log("USAGE CHECK:", {
  freeVideosRemaining: usage.freeVideosRemaining,
  credits: usage.credits,
});
if (!isReviewAccess && usage.freeVideosRemaining <= 0 && usage.credits < VIDEO_CREDIT_COST) {
  return res.status(403).json({
    success: false,
    code: "FREE_LIMIT_REACHED",
    error: "Bepul video limiti tugadi. Davom etish uchun kredit sotib oling.",
  });
}
    console.log(`Prompt: ${prompt}`);

   const videoId = `veo-${Date.now()}`;
const remoteVideoUrl = await createVeoLiteVideo(prompt, req.file || null);


    


    const fileName = await saveVideo(remoteVideoUrl, videoId);

    const baseUrl = `${req.protocol}://${req.get("host")}`;
    const videoUrl = `${baseUrl}/videos/${fileName}`;
const userRef = db.collection("users").doc(deviceId);

if (!isReviewAccess) {
  if (usage.freeVideosRemaining > 0) {
    await userRef.update({
      freeVideosRemaining: FieldValue.increment(-1),
    });
  } else {
    await userRef.update({
      credits: FieldValue.increment(-VIDEO_CREDIT_COST),
    });
  }
}
    return res.json({
      success: true,
      videoUrl,
      video_url: videoUrl,
      url: videoUrl,
      videoId,
      
    });
  } catch (error) {
    console.error("GENERATE VIDEO ERROR:", error);

    return res.status(500).json({
      success: false,
      error:
        error instanceof Error
          ? error.message
          : "Noma’lum server xatosi.",
    });
  }
});
app.use((error, req, res, next) => {
  console.error("Server xatosi:", error);

  return res.status(500).json({
    success: false,
    error: "Serverda kutilmagan xato yuz berdi.",
  });
});


    
app.post("/api/verify-purchase", async (req, res) => {
  try {
    const { purchaseToken, productId, deviceId } = req.body;

    if (!purchaseToken || !productId || !deviceId) {
      return res.status(400).json({
        success: false,
        error: "purchaseToken, productId va deviceId kerak.",
      });
    }

    if (productId !== "credits_100") {
      return res.status(400).json({
        success: false,
        error: "Noto'g'ri productId.",
      });
    }

    const authClient = await googleAuth.getClient();

    const result = await androidPublisher.purchases.products.get({
      auth: authClient,
      packageName: "com.easyai.video",
      productId: productId,
      token: purchaseToken,
    });

    if (result.data.purchaseState !== 0) {
      return res.status(400).json({
        success: false,
        error: "Google Play xaridi tasdiqlanmadi.",
      });
    }
   const purchaseRef = db.collection("usedPurchases").doc(purchaseToken);
const userRef = db.collection("users").doc(deviceId);

const credited = await db.runTransaction(async (transaction) => {
  const purchaseDoc = await transaction.get(purchaseRef);

  if (purchaseDoc.exists) {
    return false;
  }

  transaction.set(
    userRef,
    {
      credits: FieldValue.increment(100),
    },
    { merge: true }
  );

  transaction.set(purchaseRef, {
    deviceId: deviceId,
    productId: productId,
    usedAt: FieldValue.serverTimestamp(),
  });

  return true;
});

if (!credited) {
  return res.status(409).json({
    success: false,
    error: "Bu xarid uchun kredit avval berilgan.",
  });
}
    return res.json({
      success: true,
      credits: 100,
    });
  } catch (error) {
    console.error("Google Play verify xato:", error);
    return res.status(500).json({
      success: false,
      error: "Xaridni tekshirishda xato.",
    });
  }
});

const server = app.listen(PORT, "0.0.0.0", () => {
  console.log(`EasyAI server porti: ${PORT}`);
});
attachJarvis(app, server);

