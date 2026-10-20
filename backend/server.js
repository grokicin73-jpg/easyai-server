import "dotenv/config";
import express from "express";
import cors from "cors";
import path from "path";
import crypto from "crypto";
import { fileURLToPath } from "url";
import {
  mkdir,
  writeFile,
  readFile,
  access as fileAccess,
} from "fs/promises";
import multer from "multer";
import { initializeApp, cert } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { google } from "googleapis";

import { attachJarvis } from "./jarvis_server.js";
import { createJarvisAutomation } from "./jarvis_automation.js";
import { attachInstagram } from "./instagram_server.js";
import { attachInstagramWebhook } from "./instagram_webhook.js";

const app = express();
app.get("/business", (_req, res) => {
  res.type("html").send(`<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>EasyAI — Business Information</title>
  <style>
    body {
      margin: 0;
      background: #101010;
      color: #eeeeee;
      font: 17px/1.7 Arial, sans-serif;
    }
    main {
      max-width: 800px;
      margin: auto;
      padding: 40px 24px;
    }
    h1, h2 { color: white; }
    section {
      border-bottom: 1px solid #444;
      padding-bottom: 20px;
      margin-bottom: 24px;
    }
    a { color: #9acaff; }
    address { font-style: normal; }
  </style>
</head>
<body>
<main>
  <h1>EasyAI</h1>

  <section lang="en">
    <h2>About EasyAI</h2>
    <p>EasyAI is a mobile application offering AI video creation,
    a voice assistant, and tools for managing supported professional
    Instagram accounts with the account owner's permission.
    Instagram features depend on Meta permissions and account eligibility.</p>
  </section>

  <section lang="ky">
    <h2>EasyAI жөнүндө</h2>
    <p>EasyAI — жасалма интеллект менен видео түзүү,
    үн жардамчысы жана аккаунт ээсинин уруксаты менен
    кесипкөй Instagram аккаунттарын башкаруу куралдарын
    сунуштаган мобилдик тиркеме. Instagram функциялары
    Meta уруксаттарына жана аккаунттун талаптарга шайкештигине жараша иштейт.</p>
  </section>

  <section lang="ru">
    <h2>О приложении EasyAI</h2>
    <p>EasyAI — мобильное приложение для создания видео
    с помощью ИИ, общения с голосовым помощником и управления
    поддерживаемыми профессиональными аккаунтами Instagram
    с разрешения владельца. Функции Instagram зависят
    от разрешений Meta и соответствия аккаунта требованиям.</p>
  </section>

  <section lang="tr">
    <h2>EasyAI hakkında</h2>
    <p>EasyAI; yapay zekayla video oluşturma, sesli asistan
    ve hesap sahibinin izniyle desteklenen profesyonel Instagram
    hesaplarını yönetme araçları sunan bir mobil uygulamadır.
    Instagram özellikleri Meta izinlerine ve hesap uygunluğuna bağlıdır.</p>
  </section>

  <section>
  <h2>Business owner / Владелец</h2>
  <p>Индивидуальный предприниматель:
  Расулжан уулу Шерзодбек</p>
  <p>Кыргызская Республика, Базар-Коргон</p>
  <p>Email:
    <a href="mailto:grokicin73@gmail.com">grokicin73@gmail.com</a>
  </p>
</section>

  <p>
    <a href="https://doc-hosting.flycricket.io/easyai-pro-privacy-policy/e2ef82e2-9968-4bee-bc2b-161b76c8dc68/privacy">
      Privacy Policy / Политика конфиденциальности
    </a>
  </p>
</main>
</body>
</html>`);
});

const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 10 * 1024 * 1024,
    files: 1,
    fields: 5,
    fieldSize: 100000,
  },
});

const PORT = process.env.PORT || 3002;

const GEMINI_API_KEY =
  process.env.GEMINI_API_KEY || process.env.GOOGLE_API_KEY;

const PUBLIC_BASE_URL = (
  process.env.PUBLIC_BASE_URL ||
  "https://easyai-server.onrender.com"
).replace(/\/+$/, "");

if (
  process.env.RENDER === "true" &&
  !process.env.FIREBASE_CREDENTIALS
) {
  throw new Error(
    "Set FIREBASE_CREDENTIALS in Render Environment; " +
    "never deploy a service account key from Git.",
  );
}

const firebaseCredentials = process.env.FIREBASE_CREDENTIALS
  ? JSON.parse(process.env.FIREBASE_CREDENTIALS)
  : JSON.parse(
      await readFile(
        new URL(
          "./easyai-bc97f-4e135dcd7bac.json",
          import.meta.url,
        ),
        "utf8",
      ),
    );

initializeApp({
  credential: cert(firebaseCredentials),
});

const db = getFirestore();

const vertexAuth = new google.auth.GoogleAuth({
  credentials: firebaseCredentials,
  scopes: [
    "https://www.googleapis.com/auth/cloud-platform",
  ],
});

const androidPublisher = google.androidpublisher("v3");

const googleAuth = new google.auth.GoogleAuth({
  credentials: firebaseCredentials,
  scopes: [
    "https://www.googleapis.com/auth/androidpublisher",
  ],
});

const FREE_VIDEOS = 1;
const VIDEO_CREDIT_COST = 6;

const REVIEW_ACCESS_CODE = (
  process.env.REVIEW_ACCESS_CODE || ""
).trim();

function logError(label, error) {
  let message = String(
    error?.message || error || "Unknown error",
  );

  if (GEMINI_API_KEY) {
    message = message
      .split(GEMINI_API_KEY)
      .join("[HIDDEN]");
  }

  console.error(label, message);
}

function requestError(status, code) {
  const error = new Error(code);
  error.status = status;
  error.code = code;
  return error;
}

function readDeviceId(value) {
  const deviceId =
    typeof value === "string"
      ? value.trim().toLowerCase()
      : "";

  if (!/^[a-f0-9]{16}$/.test(deviceId)) {
    throw requestError(400, "INVALID_DEVICE_ID");
  }

  return deviceId;
}

function assertDeviceSession(req, usage) {
  if (!usage?.jarvisCredentialHash) return;

  if (
    req.jarvisIdentity?.credentialHash ===
    usage.jarvisCredentialHash
  ) {
    return;
  }

  const header = req.headers.authorization;

  const credential =
    typeof header === "string" &&
    header.startsWith("Bearer ")
      ? header.slice(7)
      : "";

  const hash = crypto
    .createHash("sha256")
    .update(credential)
    .digest("hex");

  if (
    !/^[a-f0-9]{64}$/.test(credential) ||
    hash !== usage.jarvisCredentialHash
  ) {
    throw requestError(403, "DEVICE_SESSION_MISMATCH");
  }
}

async function getUserUsage(userId) {
  const userRef = db.collection("users").doc(userId);

  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(userRef);

    if (snapshot.exists) {
      return snapshot.data();
    }

    const user = {
      freeVideosRemaining: FREE_VIDEOS,
      credits: 0,
      createdAt: FieldValue.serverTimestamp(),
    };

    transaction.set(userRef, user);

    return user;
  });
}

async function reserveVideo(req, deviceId, videoId) {
  const userRef = db.collection("users").doc(deviceId);

  const reservationRef = db
    .collection("videoCreditReservations")
    .doc(videoId);

  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(userRef);
    const prior = await transaction.get(reservationRef);

    const usage = snapshot.data() || {};

    assertDeviceSession(req, usage);

    if (prior.exists) {
      if (
        prior.data().deviceId !== deviceId ||
        prior.data().status === "refunded"
      ) {
        throw requestError(
          409,
          "VIDEO_RESERVATION_CONFLICT",
        );
      }

      return;
    }

    const free =
      Number.isSafeInteger(usage.freeVideosRemaining) &&
      usage.freeVideosRemaining > 0;

    const credits = Number.isSafeInteger(usage.credits)
      ? usage.credits
      : 0;

    if (!free && credits < VIDEO_CREDIT_COST) {
      throw requestError(403, "FREE_LIMIT_REACHED");
    }

    const field = free
      ? "freeVideosRemaining"
      : "credits";

    const amount = free ? 1 : VIDEO_CREDIT_COST;

    transaction.update(userRef, {
      [field]: FieldValue.increment(-amount),
    });

    transaction.set(reservationRef, {
      deviceId,
      status: "reserved",
      refundField: field,
      refundAmount: amount,
      createdAt: FieldValue.serverTimestamp(),
    });
  });

  return reservationRef;
}

async function completeVideoReservation(ref, videoUrl) {
  if (!ref) return;

  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);

    if (
      snapshot.data()?.status === "completed" &&
      snapshot.data()?.videoUrl === videoUrl
    ) {
      return;
    }

    if (snapshot.data()?.status !== "reserved") {
      throw requestError(
        409,
        "VIDEO_RESERVATION_CONFLICT",
      );
    }

    transaction.update(ref, {
      status: "completed",
      videoUrl,
      completedAt: FieldValue.serverTimestamp(),
    });
  });
}

async function refundVideoReservation(ref) {
  if (!ref) return;

  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const saved = snapshot.data();

    if (saved?.status !== "reserved") return;

    transaction.update(
      db.collection("users").doc(saved.deviceId),
      {
        [saved.refundField]: FieldValue.increment(
          saved.refundAmount,
        ),
      },
    );

    transaction.update(ref, {
      status: "refunded",
      refundedAt: FieldValue.serverTimestamp(),
    });
  });
}

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const videosDirectory = path.join(
  __dirname,
  "generated-videos",
);

await mkdir(videosDirectory, {
  recursive: true,
});

app.use(cors());

app.get("/instagram/webhook", (req, res) => {
  const expectedToken = (
    process.env.INSTAGRAM_VERIFY_TOKEN || ""
  ).trim();

  const mode = req.query["hub.mode"];
  const token = req.query["hub.verify_token"];
  const challenge = req.query["hub.challenge"];

  if (!expectedToken) {
    return res.status(503).send(
      "Webhook token sozlanmagan.",
    );
  }

  if (
    mode === "subscribe" &&
    typeof token === "string" &&
    token === expectedToken &&
    typeof challenge === "string" &&
    challenge.length > 0
  ) {
    return res.status(200)
      .type("text/plain")
      .send(challenge);
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

const instagramService = attachInstagram(
  app,
  db,
  { videosDirectory },
);

attachInstagramWebhook(app, db);

app.use(
  "/videos",
  express.static(videosDirectory, {
    acceptRanges: true,
    cacheControl: true,
    maxAge: "1h",
  }),
);

async function parseJsonResponse(response) {
  const responseText = await response.text();

  try {
    return JSON.parse(responseText);
  } catch {
    throw new Error(
      `Invalid JSON response. HTTP ${response.status}`,
    );
  }
}

async function saveVideo(remoteVideoUrl, videoId) {
  let videoBuffer;

  if (remoteVideoUrl.startsWith("data:")) {
    const match = remoteVideoUrl.match(
      /^data:video\/[^;,]+;base64,([\s\S]+)$/,
    );

    if (!match) {
      throw new Error(
        "Video base64 formati noto'g'ri.",
      );
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
        "Tayyor videoni yuklab olishda xato. " +
        `HTTP ${response.status}`,
      );
    }

    videoBuffer = Buffer.from(
      await response.arrayBuffer(),
    );
  }

  if (videoBuffer.length === 0) {
    throw new Error("Video fayli bo'sh.");
  }

  const fileName = `${videoId}.mp4`;

  await writeFile(
    path.join(videosDirectory, fileName),
    videoBuffer,
  );

  return fileName;
}

async function fetchWithRetry(
  url,
  options = {},
  retries = 3,
) {
  for (let attempt = 1; attempt <= retries; attempt++) {
    try {
      const response = await fetch(url, options);

      if (
        response.ok ||
        ![429, 500, 502, 503, 504].includes(
          response.status,
        )
      ) {
        return response;
      }

      console.log(
        `VEO temporary error ${response.status}. ` +
        `Retry ${attempt}/${retries}`,
      );
    } catch (error) {
      logError(
        `VEO network error. Retry ${attempt}/${retries}:`,
        error,
      );

      if (attempt === retries) {
        throw error;
      }
    }

    if (attempt < retries) {
      await new Promise((resolve) =>
        setTimeout(resolve, attempt * 65000),
      );
    }
  }

  throw new Error("Veo request failed after retries");
}
async function prepareVideoPrompt(rawPrompt) {
  const text = rawPrompt.trim();

  if (text.length <= 2200) {
    return text;
  }

  if (!GEMINI_API_KEY) {
    throw new Error("VIDEO_PROMPT_API_KEY_MISSING");
  }

  const response = await fetch(
    "https://generativelanguage.googleapis.com/v1beta/" +
    "models/gemini-3.1-flash-lite:generateContent",
    {
      method: "POST",
      signal: AbortSignal.timeout(45000),
      headers: {
        "Content-Type": "application/json",
        "x-goog-api-key": GEMINI_API_KEY,
      },
      body: JSON.stringify({
        systemInstruction: {
          parts: [
            {
              text:
                "Adapt the user's brief into an English " +
                "video prompt for one 8-second clip. " +
                "Preserve the main subject, identity requirements, " +
                "appearance, setting, essential actions, " +
                "camera style, lighting and audio instructions. " +
                "Make movements physically plausible. " +
                "Do not invent dialogue or additional events. " +
                "Do not remove safety restrictions. " +
                "If the brief explicitly requires more than " +
                "8 seconds, return only MULTI_CLIP_REQUIRED. " +
                "Otherwise return only the finished prompt, " +
                "under 1800 characters, without commentary.",
            },
          ],
        },
        contents: [
          {
            role: "user",
            parts: [{ text }],
          },
        ],
        generationConfig: {
          temperature: 0.2,
          maxOutputTokens: 2048,
        },
      }),
    },
  );

  const data = await parseJsonResponse(response);

  if (!response.ok) {
    logError(
      "VIDEO PROMPT ERROR:",
      new Error(JSON.stringify(data.error || {})),
    );
    throw new Error("VIDEO_PROMPT_PREPARATION_FAILED");
  }

  const candidate = data.candidates?.[0];

  if (candidate?.finishReason !== "STOP") {
    throw new Error("VIDEO_PROMPT_PREPARATION_FAILED");
  }

  const prepared = (candidate.content?.parts || [])
    .filter(
      (part) =>
        !part.thought &&
        typeof part.text === "string",
    )
    .map((part) => part.text)
    .join("")
    .trim();

  if (prepared === "MULTI_CLIP_REQUIRED") {
    throw new Error("VIDEO_MULTI_CLIP_REQUIRED");
  }

  if (!prepared || prepared.length > 2200) {
    throw new Error("VIDEO_PROMPT_PREPARATION_FAILED");
  }

  return prepared;
}

async function createVeoLiteVideo(
  prompt,
  imageFile = null,
  attempt = 1,
  onStage = async () => {},
) {
  await onStage("preparing");
  const model = "veo-3.1-lite-generate-001";
  const projectId = "easyai-bc97f";
  const location = "us-central1";

  const modelUrl =
    `https://${location}-aiplatform.googleapis.com/v1/` +
    `projects/${projectId}/locations/${location}/` +
    `publishers/google/models/${model}`;

  const preparedPrompt = await prepareVideoPrompt(prompt);

const instance = {
  prompt: preparedPrompt,
};

  if (imageFile) {
    instance.image = {
      bytesBase64Encoded:
        imageFile.buffer.toString("base64"),
      mimeType: imageFile.mimetype || "image/jpeg",
    };
  }

  const authClient = await vertexAuth.getClient();
  const accessToken = await authClient.getAccessToken();
  const token = accessToken.token || accessToken;

  console.log(
    "VEO REQUEST START:",
    new Date().toISOString(),
    "IMAGE:",
    !!imageFile,
  );

  const response = await fetch(
    `${modelUrl}:predictLongRunning`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        instances: [instance],
        parameters: {
          resolution: "1080p",
          aspectRatio:
  prompt.match(/\b(16:9|9:16)\b/)?.[1] ||
  (imageFile ? "9:16" : "16:9"),
          durationSeconds: 8,
        },
      }),
    },
  );

  const data = await response.json();

 if (!response.ok) {
  logError(
    "VEO CREATE FAILED:",
    new Error(
      JSON.stringify({
        httpStatus: response.status,
        error: data.error || null,
      }),
    ),
  );

  throw new Error(
    `Veo video creation failed. HTTP ${response.status}`,
  );
}

  const operationName = data?.name;

  if (!operationName) {
    throw new Error("Veo operation name missing");
  }
  await onStage("generating");

  for (let i = 0; i < 120; i++) {
    await new Promise((resolve) =>
      setTimeout(resolve, 10000),
    );

    const statusResponse = await fetchWithRetry(
      `${modelUrl}:fetchPredictOperation`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          operationName,
        }),
      },
    );

    const statusData = await statusResponse.json();

    console.log("VEO STATUS:", {
      done: statusData?.done === true,
      errorCode: statusData?.error?.code || null,
    });

    if (!statusResponse.ok) {
      throw new Error("Veo status check failed");
    }

    if (statusData?.done === true) {
  if (statusData.error) {
    logError(
      "VEO GENERATION FAILED:",
      new Error(JSON.stringify(statusData.error)),
    );

    throw new Error("VIDEO_PROVIDER_GENERATION_FAILED");
  }

  if (statusData.response?.raiMediaFilteredCount > 0) {
    console.warn(
      "VEO FILTER:",
      JSON.stringify({
        count: statusData.response.raiMediaFilteredCount,
        reasons:
          statusData.response.raiMediaFilteredReasons || [],
      }),
    );
  }
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
  await onStage("generated");
  return videoUrl;
}

      if (videoBase64) {
        await onStage("generated");
        return (
          `data:${video?.mimeType || "video/mp4"};base64,` +
          videoBase64
        );
      }

      if (
        statusData?.error?.code === 13 &&
        attempt < 3
      ) {
        console.warn(
          `VEO internal error. Retry ${attempt + 1}/3 ` +
          "in 10 seconds.",
        );

        await new Promise((resolve) =>
          setTimeout(resolve, 10000),
        );

        return createVeoLiteVideo(
          prompt,
          imageFile,
          attempt + 1,
        );
      }

      throw new Error("Veo video data missing");
    }
  }

  throw new Error("Veo video timed out");
}

app.get("/", (req, res) =>
  res.json({ success: true }),
);

app.get("/health", (req, res) =>
  res.json({
    success: true,
    status: "healthy",
  }),
);

app.get("/privacy", (req, res) => {
  res.type("html").send(PRIVACY_HTML);
});

app.post("/api/content-reports", async (req, res) => {
  try {
    const body = req.body;

    if (
      !body ||
      typeof body !== "object" ||
      Array.isArray(body)
    ) {
      return res.status(400).json({
        success: false,
        code: "INVALID_CONTENT_REPORT",
      });
    }

    const allowedTypes = new Set([
      "video",
      "chat",
      "voice",
    ]);

    const allowedReasons = new Set([
      "sexual",
      "violence",
      "hate",
      "child_safety",
      "misleading",
      "other",
    ]);

    const allowedLanguages = new Set([
      "English",
      "Кыргызча",
      "Русский",
      "Türkçe",
    ]);

    if (
      !allowedTypes.has(body.contentType) ||
      !allowedReasons.has(body.reason) ||
      !allowedLanguages.has(body.language)
    ) {
      return res.status(400).json({
        success: false,
        code: "INVALID_CONTENT_REPORT",
      });
    }

    const limits = {
      details: 2000,
      content: 20000,
      prompt: 20000,
      model: 100,
      videoUrl: 4096,
    };

    const fields = {};

    for (const [name, limit] of Object.entries(limits)) {
      const value = body[name] ?? "";

      if (
        typeof value !== "string" ||
        value.length > limit
      ) {
        return res.status(400).json({
          success: false,
          code: "INVALID_CONTENT_REPORT",
        });
      }

      fields[name] = value.trim();
    }

    const reportRef = db.collection("contentReports").doc();

    await reportRef.set({
      contentType: body.contentType,
      reason: body.reason,
      language: body.language,
      ...fields,
      status: "new",
      createdAt: FieldValue.serverTimestamp(),
    });

    return res.status(201).json({
      success: true,
      reportId: reportRef.id,
    });
  } catch (error) {
    logError("CONTENT REPORT SAVE FAILED:", error);

    return res.status(500).json({
      success: false,
      code: "CONTENT_REPORT_FAILED",
    });
  }
});
app.get("/api/video-status/:requestId", async (req, res) => {
  try {
    const requestId = req.params.requestId;

    if (!/^[a-f0-9]{64}$/.test(requestId)) {
      return res.status(400).json({
        success: false,
        code: "INVALID_VIDEO_REQUEST_ID",
      });
    }

    const authorization = req.headers.authorization;

    const credential =
      typeof authorization === "string" &&
      authorization.startsWith("Bearer ")
        ? authorization.slice(7)
        : "";

    if (!/^[a-f0-9]{64}$/.test(credential)) {
      return res.status(403).json({
        success: false,
        code: "DEVICE_SESSION_MISMATCH",
      });
    }

    const credentialHash = crypto
      .createHash("sha256")
      .update(credential)
      .digest("hex");

    const snapshot = await db
      .collection("videoGenerationStatus")
      .doc(requestId)
      .get();

    const saved = snapshot.data();

    if (!saved || saved.credentialHash !== credentialHash) {
      return res.status(404).json({
        success: false,
        code: "VIDEO_STATUS_NOT_FOUND",
      });
    }

    res.set("Cache-Control", "no-store");

    return res.json({
      success: true,
      stage: saved.stage,
    });
  } catch (error) {
    logError("VIDEO STATUS ERROR:", error);

    return res.status(503).json({
      success: false,
      code: "VIDEO_STATUS_UNAVAILABLE",
    });
  }
});

app.post(
  "/api/generate-video",
  upload.single("image"),
  async (req, res) => {
    let reservation;
let statusRef;

const reportStage = async (stage) => {
  if (!statusRef) return;

  try {
    await statusRef.update({
      stage,
      updatedAt: FieldValue.serverTimestamp(),
    });
  } catch (error) {
    logError("VIDEO STATUS UPDATE FAILED:", error);
  }
};

    try {
      const prompt =
        typeof req.body?.prompt === "string"
          ? req.body.prompt.trim()
          : "";

      if (!prompt || prompt.length > 20000) {
        return res.status(400).json({
          success: false,
          code: "INVALID_VIDEO_PROMPT",
        });
      }

      if (req.file) {
        const bytes = req.file.buffer;

        const png =
          bytes.length >= 8 &&
          bytes.subarray(0, 8).equals(
            Buffer.from([
              137, 80, 78, 71, 13, 10, 26, 10,
            ]),
          );

        const jpeg =
          bytes.length >= 3 &&
          bytes[0] === 255 &&
          bytes[1] === 216 &&
          bytes[2] === 255;

        if (!png && !jpeg) {
          return res.status(400).json({
            success: false,
            code: "INVALID_IMAGE_FORMAT",
          });
        }

        req.file.mimetype = png
          ? "image/png"
          : "image/jpeg";
      }

      const deviceId = readDeviceId(req.body?.deviceId);

      const reviewCode =
        typeof req.body?.reviewCode === "string"
          ? req.body.reviewCode.trim()
          : "";

      const isReviewAccess =
        REVIEW_ACCESS_CODE.length > 0 &&
        reviewCode === REVIEW_ACCESS_CODE;

      const usage = await getUserUsage(deviceId);

      assertDeviceSession(req, usage);

      const videoId =
        `veo-${Date.now()}-` +
        crypto.randomBytes(6).toString("hex");

      if (!isReviewAccess) {
        reservation = await reserveVideo(
          req,
          deviceId,
          videoId,
        );
      }

      const requestId = req.body?.requestId;

if (requestId !== undefined) {
  if (
    typeof requestId !== "string" ||
    !/^[a-f0-9]{64}$/.test(requestId)
  ) {
    throw requestError(400, "INVALID_VIDEO_REQUEST_ID");
  }

  const authorization = req.headers.authorization;

  const credential =
    typeof authorization === "string" &&
    authorization.startsWith("Bearer ")
      ? authorization.slice(7)
      : "";

  if (!/^[a-f0-9]{64}$/.test(credential)) {
    throw requestError(403, "DEVICE_SESSION_MISMATCH");
  }

  const credentialHash = crypto
    .createHash("sha256")
    .update(credential)
    .digest("hex");

  const ref = db
    .collection("videoGenerationStatus")
    .doc(requestId);

  await ref.create({
    deviceId,
    credentialHash,
    stage: "preparing",
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  statusRef = ref;
}

const remoteVideoUrl = await createVeoLiteVideo(
  prompt,
  req.file || null,
  1,
  reportStage,
);

await reportStage("saving");

      const fileName = await saveVideo(
        remoteVideoUrl,
        videoId,
      );

      const videoUrl =
        `${PUBLIC_BASE_URL}/videos/${fileName}`;

      await completeVideoReservation(
        reservation,
        videoUrl,
      );
      await reportStage("completed");

      return res.json({
        success: true,
        videoUrl,
        video_url: videoUrl,
        url: videoUrl,
        videoId,
      });
    } catch (error) {
      await reportStage("failed");
      try {
        await refundVideoReservation(reservation);
      } catch (refundError) {
        logError(
          "VIDEO REFUND REQUIRES REVIEW:",
          refundError,
        );
      }

      if (
        [
          "FREE_LIMIT_REACHED",
          "DEVICE_SESSION_MISMATCH",
          "INVALID_DEVICE_ID",
        ].includes(error?.code)
      ) {
        return res.status(error.status).json({
          success: false,
          code: error.code,
        });
      }

      logError("GENERATE VIDEO ERROR:", error);

      return res.status(500).json({
        success: false,
        code: "VIDEO_GENERATION_FAILED",
        error: "Video yaratishda xato.",
      });
    }
  },
);

const CREDIT_PACKAGES = Object.freeze({
  credits_20: 20,
  credits_200: 200,
  credits_500: 500,
  credits_100: 100,
});

app.post("/api/verify-purchase", async (req, res) => {
  try {
    const body = req.body || {};

    const purchaseToken =
      typeof body.purchaseToken === "string"
        ? body.purchaseToken.trim()
        : "";

    const productId = body.productId;
    const deviceId = readDeviceId(body.deviceId);

    if (
      !purchaseToken ||
      purchaseToken.includes("/") ||
      purchaseToken === "." ||
      purchaseToken === ".." ||
      Buffer.byteLength(purchaseToken, "utf8") > 1500 ||
      typeof productId !== "string" ||
      !Object.hasOwn(CREDIT_PACKAGES, productId)
    ) {
      return res.status(400).json({
        success: false,
        code: "INVALID_PURCHASE",
      });
    }

    const creditsToAdd = CREDIT_PACKAGES[productId];

    const userRef = db.collection("users").doc(deviceId);

    assertDeviceSession(
      req,
      (await userRef.get()).data(),
    );

    const purchaseRef = db
      .collection("usedPurchases")
      .doc(purchaseToken);

    const savedPurchase = await purchaseRef.get();

    if (savedPurchase.exists) {
      const previous = savedPurchase.data();

      if (
        previous.deviceId !== deviceId ||
        previous.productId !== productId
      ) {
        throw requestError(
          409,
          "PURCHASE_ALREADY_LINKED",
        );
      }

      return res.json({
        success: true,
        credits: 0,
        alreadyCredited: true,
      });
    }

    const authClient = await googleAuth.getClient();

    const result =
      await androidPublisher.purchases.products.get({
        auth: authClient,
        packageName: "com.easyai.video",
        productId,
        token: purchaseToken,
      });

    if (result.data.purchaseState !== 0) {
      return res.status(400).json({
        success: false,
        code: "PURCHASE_NOT_CONFIRMED",
      });
    }

    const credited = await db.runTransaction(
      async (transaction) => {
        const purchaseDoc = await transaction.get(
          purchaseRef,
        );

        const ownerDoc = await transaction.get(userRef);

        assertDeviceSession(req, ownerDoc.data());

        if (purchaseDoc.exists) {
          const previous = purchaseDoc.data();

          if (
            previous.deviceId !== deviceId ||
            previous.productId !== productId
          ) {
            throw requestError(
              409,
              "PURCHASE_ALREADY_LINKED",
            );
          }

          return false;
        }

        transaction.set(
          userRef,
          {
            ...(ownerDoc.exists
              ? {}
              : {
                  freeVideosRemaining: FREE_VIDEOS,
                  createdAt: FieldValue.serverTimestamp(),
                }),
            credits: FieldValue.increment(creditsToAdd),
          },
          { merge: true },
        );

        transaction.set(purchaseRef, {
          deviceId,
          productId,
          credits: creditsToAdd,
          usedAt: FieldValue.serverTimestamp(),
        });

        return true;
      },
    );

    return res.json({
      success: true,
      credits: credited ? creditsToAdd : 0,
      alreadyCredited: !credited,
    });
  } catch (error) {
    if (
      [
        "DEVICE_SESSION_MISMATCH",
        "INVALID_DEVICE_ID",
        "PURCHASE_ALREADY_LINKED",
      ].includes(error?.code)
    ) {
      return res.status(error.status).json({
        success: false,
        code: error.code,
      });
    }

    logError("Google Play verify error:", error);

    return res.status(500).json({
      success: false,
      code: "PURCHASE_VERIFICATION_FAILED",
    });
  }
});
const PRIVACY_HTML = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>EasyAI Pro — Privacy Policy</title>
  <style>
    body { margin:0; background:#111; color:#eee; font:16px/1.7 Arial,sans-serif; }
    main { max-width:850px; margin:auto; padding:28px 20px; }
    a { color:#91caff; }
    section { margin:32px 0; padding-bottom:24px; border-bottom:1px solid #444; }
    h1,h2,h3 { line-height:1.3; }
  </style>
</head>
<body><main>
  <h1>EasyAI / EasyAI Pro</h1>
  <nav><a href="#en">English</a> · <a href="#ky">Кыргызча</a> · <a href="#ru">Русский</a> · <a href="#tr">Türkçe</a></nav>

  <section id="en" lang="en">
    <h2>Privacy Policy</h2>
    <p>Updated: 14 October 2026. Contact: <a href="mailto:grokicin73@gmail.com">grokicin73@gmail.com</a>.</p>
    <h3>Data and purposes</h3>
    <p>EasyAI processes prompts, selected images, and microphone audio when you use the corresponding AI features.
    These inputs are sent to Google AI services to generate responses or videos.
    Device or installation identifiers, usage counters, credit balances, and purchase verification data are used
    to provide free allowances, manage credits, verify purchases, and prevent misuse.</p>
    <p>For Jarvis, a random app session credential is stored on the device and its hash is stored on the server.
    Jarvis usage and billing records include request identifiers, request hashes, generated chat replies,
    free allowances, credit reservations, refunds, and live-session minute records.
    These records are stored in Firebase Firestore to manage access, billing, and duplicate requests.
    This billing storage does not attach microphone audio. No automatic deletion period is configured.</p>
    <p>If you connect Instagram, we process account identifiers, profile information, granted permissions,
    encrypted access tokens, connection dates, publishing records, and product catalogue data.
    When messaging is enabled, we receive message text, sender and recipient identifiers,
    message identifiers, and available timestamps. This supports the Instagram features you use.
    Instagram login takes place through Instagram; do not send your Instagram password to EasyAI support.</p>
    <h3>AI content reports</h3>
    <p>When you submit an in-app content report, EasyAI receives your selected reason, optional comments,
    app language, and the relevant content available on that screen. This may include AI response text,
    conversation transcripts, prompts, captions, model names, and a generated video URL.
    This reporting feature does not attach microphone audio.</p>
    <p>Reports are stored in Firebase Firestore with a report identifier, submission time, and review status.
    They are used to investigate reported content and improve content safety. Reports remain stored until
    manually deleted; no automatic deletion period is currently configured. To request deletion, contact
    grokicin73@gmail.com and provide the submission time and enough information to identify your report.
    Do not include passwords or access tokens.</p>
    <h3>Service providers and access</h3>
    <p>Google AI, Firebase, Render, Meta/Instagram, and Google Play process relevant data to provide AI,
    storage, hosting, Instagram, and payment services. Their own privacy policies also apply.
    Generated videos can be accessible to anyone who has their direct video URL. Avoid submitting confidential content.</p>
    <h3>Storage and deletion</h3>
    <p>Backend connections use HTTPS, and stored Instagram access tokens are encrypted. Database records
    remain stored until removed; no general automatic deletion period is currently configured.
    Generated files may become unavailable when server storage is reset. Automated video tasks store your command, prompt, caption, selected Instagram account, provider operation identifier, publication status and credit ledger in Firestore. Explicit create-and-publish commands authorize a single publication. Uncertain results may require manual reconciliation; no automatic deletion period is configured. Disconnecting Instagram should
    not be treated as deletion of all previously stored data.</p>
    <p>To request access to or deletion of your EasyAI data, email <a href="mailto:grokicin73@gmail.com">grokicin73@gmail.com</a>
    with the subject “EasyAI data deletion” and identify the connected Instagram account or relevant app installation.
    Requests are handled manually and ownership must be verified. Do not include passwords or access tokens.
    We will explain which records can be removed and any records that must be retained before completing the request.
    Data already published on Instagram or held by service providers is also subject to their own controls and retention practices.</p>
  </section>

  <section id="ky" lang="ky">
    <h2>Купуялык саясаты</h2>
    <p>Жаңыртылган күнү: 2026-жылдын 14-октябры. Байланыш: <a href="mailto:grokicin73@gmail.com">grokicin73@gmail.com</a>.</p>
    <h3>Маалыматтар жана максаттар</h3>
    <p>Тиешелүү AI функцияларын колдонгондо EasyAI тексттик суроо-талаптарды, тандалган сүрөттөрдү жана микрофон үнүн иштетет.
    Алар жооп же видео түзүү үчүн Google AI кызматтарына жөнөтүлөт. Түзмөк же орнотуу идентификаторлору,
    колдонуу эсептегичтери, кредит балансы жана сатып алууну текшерүү маалыматтары акысыз мүмкүнчүлүктөрдү,
    кредиттерди жана төлөмдөрдү башкаруу, ошондой эле кыянаттык менен пайдаланууну алдын алуу үчүн колдонулат.</p>
    <p>Jarvis үчүн түзмөктө кокустук сессия ачкычы, серверде анын хэши сакталат. Колдонуу жана төлөм жазууларына
    сурам идентификаторлору, сурам хэштери, чаттын түзүлгөн жооптору, акысыз мүмкүнчүлүктөр, кредит резервдери,
    кайтаруулар жана жандуу сүйлөшүүнүн мүнөттөрү кирет. Алар кирүүнү, төлөмдү жана кайталанган сурамдарды
    башкаруу үчүн Firebase Firestore базасында сакталат. Бул төлөм жазууларына микрофондун аудиосу тиркелбейт.
    Автоматтык өчүрүү мөөнөтү коюлган эмес.</p>
    <p>Instagram туташтырылса, аккаунт идентификаторлору, профиль, берилген уруксаттар, шифрленген кирүү токендери,
    туташуу даталары, жарыялоо жазуулары жана товар каталогу иштетилет. Билдирүүлөр иштетилгенде билдирүү тексти,
    жөнөтүүчү жана алуучу идентификаторлору, билдирүү идентификатору жана жеткиликтүү убакыт белгилери алынат.
    Бул колдонулган Instagram функцияларын камсыз кылат. Кирүү Instagram аркылуу жүргүзүлөт;
    колдоо кызматына Instagram сырсөзүңүздү жөнөтпөңүз.</p>
    <p>Автоматтык видео тапшырмаларынын буйругу, промпту, сүрөттөмөсү, тандалган Instagram аккаунту, провайдердин иш идентификатору, жарыялоо абалы жана кредит жазуулары Firestore базасында сакталат. Так түзүү жана жарыялоо буйругу бир жарыялоого уруксат берет. Белгисиз натыйжа кол менен текшерилиши мүмкүн; автоматтык өчүрүү мөөнөтү коюлган эмес.</p>
    <h3>AI контентине даттануулар</h3>
    <p>Колдонмонун ичинен даттануу жөнөткөндө EasyAI тандалган себепти, кошумча комментарийди,
    колдонмонун тилин жана ошол экрандагы тиешелүү контентти алат. Аларга AI жообунун тексти,
    сүйлөшүүнүн тексттик жазмасы, промпттор, сүрөттөмөлөр, моделдин аты жана түзүлгөн видеонун шилтемеси
    кириши мүмкүн. Бул даттануу функциясы микрофондун аудиосун тиркебейт.</p>
    <p>Даттануулар Firebase Firestore базасында идентификатору, жөнөтүлгөн убактысы жана текшерүү абалы менен сакталат.
    Алар билдирилген контентти текшерүү жана контенттин коопсуздугун жакшыртуу үчүн колдонулат.
    Даттануулар кол менен өчүрүлгөнгө чейин сакталат; автоматтык өчүрүү мөөнөтү азырынча коюлган эмес.
    Өчүрүүнү сурануу үчүн grokicin73@gmail.com дарегине жөнөтүлгөн убакытты жана даттанууну табууга жетиштүү
    маалыматты жазыңыз. Сырсөздөрдү же кирүү токендерин жөнөтпөңүз.</p>
    <h3>Кызматтар жана жеткиликтүүлүк</h3>
    <p>Google AI, Firebase, Render, Meta/Instagram жана Google Play тиешелүү маалыматтарды AI, сактоо, хостинг,
    Instagram жана төлөм кызматтары үчүн иштетет. Алардын купуялык саясаттары да колдонулат.
    Түзүлгөн видеонун түз шилтемесин билген адам аны көрө алышы мүмкүн. Жашыруун маалыматтарды жөнөтүүдөн сак болуңуз.</p>
    <h3>Сактоо жана өчүрүү</h3>
    <p>Сервер байланыштары HTTPS колдонот, сакталган Instagram токендери шифрленет. База жазуулары өчүрүлгөнгө чейин сакталат;
    жалпы автоматтык өчүрүү мөөнөтү азырынча коюлган эмес. Сервер сактагычы жаңырганда видео файлдар жеткиликсиз болушу мүмкүн.
    Instagram байланышын үзүү бардык мурдагы маалыматтарды өчүрбөйт.</p>
    <p>Маалыматтарга жетүү же аларды өчүрүү үчүн <a href="mailto:grokicin73@gmail.com">grokicin73@gmail.com</a>
    дарегине “EasyAI data deletion” темасы менен жазыңыз. Туташкан Instagram аккаунтун же колдонмонун тиешелүү
    орнотуусун көрсөтүңүз. Сурам кол менен каралат жана ээлик текшерилет. Сырсөздөрдү же токендерди жөнөтпөңүз.
    Өчүрүлө турган жана сакталууга тийиш болгон жазуулар тууралуу сурам аткарылганга чейин түшүндүрөбүз.
    Instagramда жарыяланган же башка кызматтар сактаган маалыматтарга ошол кызматтардын башкаруу жана сактоо эрежелери да колдонулат.</p>
  </section>

  <section id="ru" lang="ru">
    <h2>Политика конфиденциальности</h2>
    <p>Обновлено: 14 октября 2026 года. Контакт: <a href="mailto:grokicin73@gmail.com">grokicin73@gmail.com</a>.</p>
    <h3>Данные и цели</h3>
    <p>При использовании соответствующих функций EasyAI обрабатывает запросы, выбранные изображения и звук микрофона.
    Эти данные передаются сервисам Google AI для создания ответов или видео. Идентификаторы устройства или установки,
    счётчики использования, баланс кредитов и данные проверки покупок используются для предоставления бесплатного лимита,
    управления кредитами, проверки платежей и предотвращения злоупотреблений.</p>
    <p>Для Jarvis на устройстве хранится случайный ключ сессии приложения, а на сервере — его хэш.
    Записи использования и оплаты включают идентификаторы и хэши запросов, созданные ответы чата, бесплатный лимит,
    резервирование и возврат кредитов, а также записи минут живого разговора. Они сохраняются в Firebase Firestore
    для управления доступом, оплатой и повторными запросами. Эти платёжные записи не прикрепляют аудио с микрофона.
    Срок автоматического удаления не настроен.</p>
    <p>При подключении Instagram обрабатываются идентификаторы аккаунта, профиль, предоставленные разрешения,
    зашифрованные токены доступа, даты подключения, записи публикаций и каталог товаров. При включении сообщений
    принимаются текст, идентификаторы отправителя, получателя и сообщения, а также доступные временные отметки.
    Это обеспечивает используемые функции Instagram. Авторизация проходит через Instagram;
    не отправляйте пароль Instagram службе поддержки EasyAI.</p>
    <p>Автоматические видеозадачи сохраняют команду, промпт, описание, выбранный аккаунт Instagram, идентификатор операции провайдера, статус публикации и записи кредитов в Firestore. Явная команда создать и опубликовать разрешает одну публикацию. Неопределённые результаты могут требовать ручной проверки; автоматическое удаление не настроено.</p>
    <h3>Жалобы на контент ИИ</h3>
    <p>При отправке жалобы внутри приложения EasyAI получает выбранную причину, необязательный комментарий,
    язык приложения и соответствующий контент, доступный на этом экране. Это может включать текст ответа ИИ,
    текстовую расшифровку разговора, промпты, описания, названия моделей и ссылку на созданное видео.
    Эта функция подачи жалоб не прикрепляет аудио с микрофона.</p>
    <p>Жалобы сохраняются в Firebase Firestore с идентификатором, временем отправки и статусом проверки.
    Они используются для рассмотрения указанного контента и улучшения его безопасности. Жалобы хранятся до ручного удаления;
    срок автоматического удаления пока не настроен. Для запроса удаления напишите на grokicin73@gmail.com,
    указав время отправки и сведения, достаточные для поиска вашей жалобы. Не отправляйте пароли и токены доступа.</p>
    <h3>Поставщики услуг и доступ</h3>
    <p>Google AI, Firebase, Render, Meta/Instagram и Google Play обрабатывают соответствующие данные для работы AI,
    хранения, хостинга, Instagram и платежей. Также действуют их собственные политики конфиденциальности.
    Созданное видео может быть доступно любому, кто знает его прямую ссылку. Не отправляйте конфиденциальные материалы.</p>
    <h3>Хранение и удаление</h3>
    <p>Соединения с сервером используют HTTPS, а сохранённые токены Instagram зашифрованы. Записи базы хранятся до удаления;
    общий срок автоматического удаления пока не настроен. Видео могут стать недоступными при сбросе серверного хранилища.
    Отключение Instagram не означает удаление всех ранее сохранённых данных.</p>
    <p>Для доступа к своим данным или запроса удаления напишите на <a href="mailto:grokicin73@gmail.com">grokicin73@gmail.com</a>
    с темой «EasyAI data deletion». Укажите подключённый аккаунт Instagram или соответствующую установку приложения.
    Запросы рассматриваются вручную с проверкой принадлежности. Не присылайте пароли и токены. До выполнения запроса
    мы объясним, какие записи можно удалить и какие необходимо сохранить. На опубликованные в Instagram данные
    и данные у поставщиков услуг также распространяются их правила управления и хранения.</p>
  </section>

  <section id="tr" lang="tr">
    <h2>Gizlilik Politikası</h2>
    <p>Güncelleme: 14 Ekim 2026. İletişim: <a href="mailto:grokicin73@gmail.com">grokicin73@gmail.com</a>.</p>
    <h3>Veriler ve amaçlar</h3>
    <p>İlgili AI özelliklerini kullandığınızda EasyAI istemleri, seçilen görselleri ve mikrofon sesini işler.
    Bu girdiler yanıt veya video oluşturmak için Google AI hizmetlerine gönderilir. Cihaz veya kurulum kimlikleri,
    kullanım sayaçları, kredi bakiyesi ve satın alma doğrulama verileri ücretsiz kullanım hakkını ve kredileri yönetmek,
    ödemeleri doğrulamak ve kötüye kullanımı önlemek için kullanılır.</p>
    <p>Jarvis için cihazda rastgele bir uygulama oturum anahtarı, sunucuda ise bunun özeti saklanır.
    Kullanım ve ödeme kayıtları istek kimliklerini ve özetlerini, oluşturulan sohbet yanıtlarını, ücretsiz hakları,
    kredi rezervasyonlarını, iadeleri ve canlı sohbet dakika kayıtlarını içerir. Erişim, ödeme ve yinelenen istekleri
    yönetmek için Firebase Firestore içinde saklanır. Bu ödeme kayıtlarına mikrofon sesi eklenmez.
    Otomatik silme süresi yapılandırılmamıştır.</p>
    <p>Instagram bağlandığında hesap kimlikleri, profil bilgileri, verilen izinler, şifrelenmiş erişim belirteçleri,
    bağlantı tarihleri, yayın kayıtları ve ürün kataloğu işlenir. Mesajlaşma etkinse mesaj metni, gönderen ve alıcı kimlikleri,
    mesaj kimliği ve mevcut zaman bilgileri alınır. Bunlar kullandığınız Instagram özelliklerini sağlar.
    Giriş Instagram üzerinden yapılır; Instagram şifrenizi EasyAI desteğine göndermeyin.</p>
    <p>Otomatik video görevleri komutu, istemi, açıklamayı, seçilen Instagram hesabını, sağlayıcı işlem kimliğini, yayın durumunu ve kredi kayıtlarını Firestore içinde saklar. Açık bir oluştur ve yayınla komutu bir yayına izin verir. Belirsiz sonuçlar elle kontrol gerektirebilir; otomatik silme süresi yapılandırılmamıştır.</p>
    <h3>AI içerik bildirimleri</h3>
    <p>Uygulama içinden bir içerik bildirimi gönderdiğinizde EasyAI seçtiğiniz nedeni, isteğe bağlı yorumunuzu,
    uygulama dilini ve o ekrandaki ilgili içeriği alır. Bunlar AI yanıt metnini, konuşmanın yazılı dökümünü,
    istemleri, açıklamaları, model adlarını ve oluşturulan videonun bağlantısını içerebilir.
    Bu bildirim özelliği mikrofon sesini eklemez.</p>
    <p>Bildirimler Firebase Firestore içinde bir kimlik, gönderim zamanı ve inceleme durumu ile saklanır.
    Bildirilen içeriği incelemek ve içerik güvenliğini iyileştirmek için kullanılır. Bildirimler elle silinene kadar saklanır;
    otomatik silme süresi henüz yapılandırılmamıştır. Silme talebi için grokicin73@gmail.com adresine gönderim zamanını
    ve bildiriminizi bulmaya yeterli bilgileri yazın. Şifre veya erişim belirteci göndermeyin.</p>
    <h3>Hizmet sağlayıcıları ve erişim</h3>
    <p>Google AI, Firebase, Render, Meta/Instagram ve Google Play, AI, depolama, barındırma, Instagram ve ödeme hizmetleri
    için ilgili verileri işler. Kendi gizlilik politikaları da geçerlidir. Oluşturulan videolar doğrudan video bağlantısını
    bilen kişilere açık olabilir. Gizli içerik göndermekten kaçının.</p>
    <h3>Saklama ve silme</h3>
    <p>Sunucu bağlantıları HTTPS kullanır ve saklanan Instagram erişim belirteçleri şifrelenir. Veritabanı kayıtları silinene
    kadar saklanır; genel bir otomatik silme süresi henüz yapılandırılmamıştır. Sunucu depolaması sıfırlandığında videolar
    erişilemez olabilir. Instagram bağlantısını kesmek, önceki tüm verileri silmez.</p>
    <p>Verilerinize erişim veya silme talebi için <a href="mailto:grokicin73@gmail.com">grokicin73@gmail.com</a>
    adresine “EasyAI data deletion” konusuyla yazın. Bağlı Instagram hesabını veya ilgili uygulama kurulumunu belirtin.
    Talepler elle incelenir ve sahiplik doğrulanır. Şifre veya erişim belirteci göndermeyin. Talebi tamamlamadan önce
    silinebilecek kayıtları ve saklanması gereken kayıtları açıklayacağız. Instagram'da yayınlanan veya hizmet
    sağlayıcılarında tutulan veriler onların yönetim ve saklama kurallarına da tabidir.</p>
  </section>
</main></body></html>`;

// Automated and manual videos share the same credit ledger.
const automation = createJarvisAutomation(
  db,
  instagramService,
  {
    reserve: (job, id) =>
      reserveVideo(
        {
          jarvisIdentity: {
            credentialHash: job.ownerId,
          },
          headers: {},
        },
        job.deviceId,
        `jarvis-${id}`,
      ),

    refund: (id) =>
      refundVideoReservation(
        db.collection("videoCreditReservations")
          .doc(`jarvis-${id}`),
      ),

    complete: (id, url) =>
      completeVideoReservation(
        db.collection("videoCreditReservations")
          .doc(`jarvis-${id}`),
        url,
      ),

    async start(job) {
      const client = await vertexAuth.getClient();
      const token = await client.getAccessToken();

      const url =
        "https://us-central1-aiplatform.googleapis.com/v1/" +
        "projects/easyai-bc97f/locations/us-central1/" +
        "publishers/google/models/" +
        "veo-3.1-lite-generate-001:predictLongRunning";

      const response = await fetch(url, {
        method: "POST",
        signal: AbortSignal.timeout(60000),
        headers: {
          Authorization: `Bearer ${token.token || token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          instances: [
            {
              prompt: job.prompt,
            },
          ],
          parameters: {
            resolution: "720p",
            aspectRatio: "9:16",
            durationSeconds: 8,
          },
        }),
      });

      const data = await parseJsonResponse(response);

      if (!response.ok) {
        const error = Object.assign(
          new Error("VIDEO_START_FAILED"),
          {
            code: "VIDEO_START_FAILED",
          },
        );

        // Never blindly repeat a possibly accepted generation.
        error.definite = [
          400,
          401,
          403,
          404,
          429,
        ].includes(response.status);

        throw error;
      }

      if (
        typeof data.name !== "string" ||
        !data.name.startsWith("projects/easyai-bc97f/")
      ) {
        throw new Error("VIDEO_OPERATION_UNKNOWN");
      }

      return data.name;
    },

    async poll(job, id) {
      if (
        typeof job.operation !== "string" ||
        !job.operation.startsWith("projects/easyai-bc97f/")
      ) {
        throw new Error("INVALID_OPERATION");
      }

      const client = await vertexAuth.getClient();
      const token = await client.getAccessToken();

      const response = await fetch(
        "https://us-central1-aiplatform.googleapis.com/v1/" +
        "projects/easyai-bc97f/locations/us-central1/" +
        "publishers/google/models/" +
        "veo-3.1-lite-generate-001:fetchPredictOperation",
        {
          method: "POST",
          signal: AbortSignal.timeout(30000),
          headers: {
            Authorization: `Bearer ${token.token || token}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            operationName: job.operation,
          }),
        },
      );

      const data = await parseJsonResponse(response);

      if (!response.ok) {
        throw new Error("VIDEO_STATUS_UNAVAILABLE");
      }

      if (!data.done) {
        return {
          done: false,
        };
      }

      if (data.error) {
        return {
          done: true,
          error: "VIDEO_GENERATION_FAILED",
        };
      }

      const value =
        data.response?.generateVideoResponse
          ?.generatedSamples?.[0]?.video ||
        data.response?.videos?.[0];

      const bytes =
        value?.bytesBase64Encoded ||
        value?.encodedVideo ||
        value?.videoBytes ||
        value?.inlineData?.data;

      const remote =
        value?.uri ||
        (
          bytes
            ? `data:video/mp4;base64,${bytes}`
            : null
        );

      if (!remote) {
        return {
          done: true,
          error: "VIDEO_FILTERED_OR_EMPTY",
        };
      }

      const filename = await saveVideo(
        remote,
        `jarvis-${id}`,
      );

      return {
        done: true,
        videoUrl:
          `${PUBLIC_BASE_URL}/videos/${filename}`,
      };
    },

    async ensureAvailable(job, id) {
      try {
        await fileAccess(
          path.join(
            videosDirectory,
            `jarvis-${id}.mp4`,
          ),
        );
      } catch {
        const restored = await this.poll(job, id);

        if (!restored.videoUrl) {
          throw new Error("VIDEO_FILE_UNAVAILABLE");
        }
      }
    },
  },
);

const server = app.listen(
  PORT,
  "0.0.0.0",
  () => {
    console.log(`EasyAI server porti: ${PORT}`);
  },
);

attachJarvis(app, server, {
  automation,
  db,
});

app.use((error, req, res, next) => {
  if (res.headersSent) {
    return next(error);
  }

  if (error instanceof multer.MulterError) {
    return res.status(400).json({
      success: false,
      code:
        error.code === "LIMIT_FILE_SIZE"
          ? "IMAGE_TOO_LARGE"
          : "INVALID_UPLOAD",
    });
  }

  logError("Server error:", error);

  return res.status(500).json({
    success: false,
    error: "Serverda kutilmagan xato yuz berdi.",
  });
});