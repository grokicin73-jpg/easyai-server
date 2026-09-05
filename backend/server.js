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
const app = express();
const upload = multer({ storage: multer.memoryStorage() });
const PORT = process.env.PORT || 3002;



const GEMINI_API_KEY =
  process.env.GEMINI_API_KEY || process.env.GOOGLE_API_KEY;

const firebaseCredentials = process.env.FIREBASE_CREDENTIALS
  ? JSON.parse(process.env.FIREBASE_CREDENTIALS)
  : JSON.parse(
      await readFile(
        new URL("./easyai-bc97f-firebase-adminsdk-fbsvc-ac12d8de25.json", import.meta.url),
        "utf8"
      )
    );

initializeApp({
  credential: cert(firebaseCredentials),
});

const db = getFirestore();
const androidPublisher = google.androidpublisher("v3");

const googleAuth = new google.auth.GoogleAuth({
  credentials: firebaseCredentials,
  scopes: ["https://www.googleapis.com/auth/androidpublisher"],
});
const FREE_VIDEOS = 1;
const VIDEO_CREDIT_COST = 6;

async function getUserUsage(userId) {
  const userRef = db.collection("users").doc(userId);
  const userDoc = await userRef.get();

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
app.use(express.json({ limit: "2mb" }));

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
  const response = await fetch(remoteVideoUrl, {
  headers: {
    "x-goog-api-key": GEMINI_API_KEY,
  },
});

  if (!response.ok) {
    throw new Error(
      `Tayyor videoni yuklab olishda xato. HTTP ${response.status}`,
    );
  }

  const videoBuffer = Buffer.from(await response.arrayBuffer());
  const fileName = `${videoId}.mp4`;

  const filePath = path.join(videosDirectory, fileName);

  await writeFile(filePath, videoBuffer);

  return fileName;
}
async function createVeoLiteVideo(prompt, imageFile = null) {
  const model = "veo-3.1-lite-generate-preview";
  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:predictLongRunning`;

  const instance = { prompt };

  if (imageFile) {
  instance.image = {
    bytesBase64Encoded: imageFile.buffer.toString("base64"),
    mimeType: imageFile.mimetype || "image/jpeg",
  };
}
  
  
console.log("VEO REQUEST START:", new Date().toISOString(), "IMAGE:", !!imageFile);
  const response = await fetch(url, {
    method: "POST",
    headers: {
      "x-goog-api-key": GEMINI_API_KEY,
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

    const statusResponse = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/${operationName}`,
      {
        headers: {
          "x-goog-api-key": GEMINI_API_KEY,
        },
      }
    );

    const statusData = await statusResponse.json();
    console.log("VEO STATUS:", JSON.stringify(statusData, null, 2));

    if (!statusResponse.ok) {
      console.error("Veo status error:", statusData);
      throw new Error("Veo status check failed");
    }

    if (statusData?.done === true) {
      const videoUrl =
        statusData?.response?.generateVideoResponse
          ?.generatedSamples?.[0]?.video?.uri;

      if (!videoUrl) {
        console.error("Veo video URL missing:", statusData);
        throw new Error("Veo video URL missing");
      }

      return videoUrl;
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

app.post("/api/generate-video", upload.single("image"), async (req, res) => {
  try {
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

    if (prompt.length > 2048) {
      return res.status(400).json({
        success: false,
        error: "Prompt juda uzun. 2048 belgidan oshirmang.",
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

const usage = await getUserUsage(deviceId);

console.log("USAGE CHECK:", {
  freeVideosRemaining: usage.freeVideosRemaining,
  credits: usage.credits,
});
if (usage.freeVideosRemaining <= 0 && usage.credits < VIDEO_CREDIT_COST) {
  return res.status(403).json({
    success: false,
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

if (usage.freeVideosRemaining > 0) {
  await userRef.update({
    freeVideosRemaining: FieldValue.increment(-1),
  });
} else {
  await userRef.update({
    credits: FieldValue.increment(-VIDEO_CREDIT_COST),
  });
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

app.listen(PORT, "0.0.0.0", () => {
});
