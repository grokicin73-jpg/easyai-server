import 'dotenv/config';
import express from "express";
import cors from "cors";
import dotenv from "dotenv";
import path from "path";
import { fileURLToPath } from "url";
import { mkdir } from "fs/promises";
import { GoogleGenAI } from "@google/genai";
import { initializeApp, cert } from "firebase-admin/app";
import serviceAccount from "./easyai-bc97f-4e135dcd7bac.json" with { type: "json" };
dotenv.config({ path: '../.env' });
initializeApp({
  credential: cert(serviceAccount),
});
const app = express();
app.use(cors());
const PORT = process.env.PORT || 3001;

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const videosDirectory = path.join(__dirname, "generated-videos");

await mkdir(videosDirectory, { recursive: true });

app.use(cors());
app.use(express.json({ limit: "2mb" }));
app.use("/videos", express.static(videosDirectory));

if (!process.env.GEMINI_API_KEY) {
  console.error("GEMINI_API_KEY .env faylida topilmadi.");
  process.exit(1);
}

const ai = new GoogleGenAI({
  apiKey: process.env.GEMINI_API_KEY,
});

app.get("/", (req, res) => {
  res.json({
    success: true,
    status: "EasyAI Backend is running",
  });
});

app.post("/api/generate-video", async (req, res) => {
  res.setTimeout(300000);
  const prompt =
    typeof req.body?.prompt === "string" ? req.body.prompt.trim() : "";

  const selectedModel =
    typeof req.body?.selectedModel === "string"
      ? req.body.selectedModel.trim()
      : "";

  if (!prompt) {
    return res.status(400).json({
      success: false,
      message: "Prompt is required",
    });
  }

  if (!selectedModel || selectedModel === "No model selected") {
    return res.status(400).json({
      success: false,
      message: "AI model must be selected",
    });
  }

  console.log("Video request received");
  console.log("Prompt:", prompt);
  console.log("Selected model:", selectedModel);

  try {
    let operation = await ai.models.generateVideos({
    model: "veo-3.1-lite-generate-preview",
      prompt,
      config: {
        numberOfVideos: 1,
        aspectRatio: "16:9",
      },
    });

    while (!operation.done) {
      console.log("Video yaratilmoqda, kuting...");

      await new Promise((resolve) => setTimeout(resolve, 5000));

      operation = await ai.operations.getVideosOperation({
        operation,
      });
    }
console.log("Google final response:", JSON.stringify(operation, null, 2));
    const generatedVideo =
      operation.response?.generatedVideos?.[0]?.video;

    if (!generatedVideo) {
      throw new Error("Google javobida video topilmadi.");
    }

    const fileName = `easyai-${Date.now()}.mp4`;
    const downloadPath = path.join(videosDirectory, fileName);

    await ai.files.download({
      file: generatedVideo,
      downloadPath,
    });

    const videoUrl = `${req.protocol}://${req.get('host')}/videos/${fileName}`;

    console.log("Video tayyor:", videoUrl);

    return res.json({
      success: true,
      message: videoUrl,
      videoUrl,
    });
  } catch (error) {
    console.error("Veo video generation error:", error);

    return res.status(500).json({
      success: false,
      message: error?.message ?? String(error),
    });
  }
});

app.listen(PORT, () => {
  console.log(`EasyAI backend running on port ${PORT}`);
});