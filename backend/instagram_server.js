import crypto from "node:crypto";
import { FieldValue } from "firebase-admin/firestore";
import multer from "multer";
import path from "node:path";
import { open, unlink } from "node:fs/promises";

const BASE = "https://easyai-server.onrender.com";
const REDIRECT = `${BASE}/instagram/callback`;

const COOKIE = {
  httpOnly: true,
  secure: true,
  sameSite: "lax",
  path: "/instagram",
};

const hash = (value) =>
  crypto.createHash("sha256").update(value).digest("hex");

const nonce = () => crypto.randomBytes(32).toString("hex");

const isKey = (value) =>
  typeof value === "string" && /^[a-f0-9]{64}$/.test(value);

export function attachInstagram(app, db, { videosDirectory }) {
  const identities = db.collection("instagramPrivateIdentities");
  const tickets = db.collection("instagramPrivateTickets");
  const states = db.collection("instagramPrivateStates");
  const connections = db.collection("instagramPrivateConnections");

  function settings() {
    const appId = process.env.INSTAGRAM_APP_ID?.trim();
    const appSecret = process.env.INSTAGRAM_APP_SECRET?.trim();

    const encryptionSecret =
      process.env.INSTAGRAM_TOKEN_ENCRYPTION_KEY?.trim();

    if (
      !appId ||
      !appSecret ||
      !encryptionSecret ||
      encryptionSecret.length < 32
    ) {
      throw new Error("INSTAGRAM_CONFIG_MISSING");
    }

    return {
      appId,
      appSecret,
      key: crypto
        .createHash("sha256")
        .update(encryptionSecret)
        .digest(),
    };
  }

  function seal(token, key, ownerId) {
    const iv = crypto.randomBytes(12);

    const cipher = crypto.createCipheriv(
      "aes-256-gcm",
      key,
      iv,
    );

    cipher.setAAD(Buffer.from(ownerId));

    const ciphertext = Buffer.concat([
      cipher.update(token, "utf8"),
      cipher.final(),
    ]);

    return {
      iv: iv.toString("base64"),
      ciphertext: ciphertext.toString("base64"),
      tag: cipher.getAuthTag().toString("base64"),
      version: 1,
    };
  }

  const wrap = (fn) => (req, res, next) =>
    Promise.resolve(fn(req, res)).catch(next);

  function credential(req) {
    const match = /^Bearer ([a-f0-9]{64})$/.exec(
      req.get("authorization") || "",
    );

    return match?.[1];
  }

  async function owner(req, res) {
    const token = credential(req);

    if (!token) {
      res.status(401).json({
        success: false,
        error: "INSTAGRAM_SESSION_INVALID",
      });

      return null;
    }

    const ownerId = hash(token);
    const identity = await identities.doc(ownerId).get();

    if (!identity.exists) {
      res.status(401).json({
        success: false,
        error: "INSTAGRAM_SESSION_INVALID",
      });

      return null;
    }

    return ownerId;
  }

  async function consume(ref) {
    return db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(ref);

      if (
        !snapshot.exists ||
        snapshot.data().expiresAt.toMillis() <= Date.now()
      ) {
        return null;
      }

      const record = snapshot.data();

      transaction.delete(ref);

      return record;
    });
  }

  async function meta(url, options = {}) {
    const response = await fetch(url, {
      ...options,
      signal: AbortSignal.timeout(30000),
    });

    const data = await response.json();

    if (!response.ok || data.error) {
      throw new Error("INSTAGRAM_TOKEN_REQUEST_FAILED");
    }

    return data;
  }
  const videoUpload = multer({
    storage: multer.diskStorage({
      destination: videosDirectory,
      filename: (req, file, done) => {
        done(null, `instagram-${nonce()}.mp4`);
      },
    }),
    limits: {
      fileSize: 100 * 1024 * 1024,
      files: 1,
      fields: 0,
      parts: 1,
    },
  }).single("video");

  const activeUploads = new Set();

  app.post(
    "/api/instagram/videos/upload",

    async (req, res, next) => {
      try {
        res.set("Cache-Control", "no-store");

        const ownerId = await owner(req, res);
        if (!ownerId) return;

        const snapshot = await connections.doc(ownerId).get();
        const account = snapshot.data();

        if (
          !account ||
          account.expiresAt.toMillis() <= Date.now()
        ) {
          return res.status(409).json({
            success: false,
            error: "INSTAGRAM_RECONNECT_REQUIRED",
          });
        }

        if (activeUploads.has(ownerId)) {
          return res.status(429).json({
            success: false,
            error: "VIDEO_UPLOAD_BUSY",
          });
        }

        activeUploads.add(ownerId);

        const release = () => activeUploads.delete(ownerId);
        res.once("finish", release);
        res.once("close", release);

        next();
      } catch (error) {
        next(error);
      }
    },

    (req, res) => {
      videoUpload(req, res, async (uploadError) => {
        const removeFile = async () => {
          if (req.file?.path) {
            await unlink(req.file.path).catch(() => {});
          }
        };

        try {
          if (uploadError) {
            await removeFile();

            return res.status(400).json({
              success: false,
              error:
                uploadError.code === "LIMIT_FILE_SIZE"
                  ? "VIDEO_TOO_LARGE"
                  : "INVALID_VIDEO_UPLOAD",
            });
          }

          if (!req.file || req.file.size < 16) {
            await removeFile();

            return res.status(400).json({
              success: false,
              error: "INVALID_MP4_VIDEO",
            });
          }

          const file = await open(req.file.path, "r");
          const header = Buffer.alloc(12);

          try {
            await file.read(header, 0, header.length, 0);
          } finally {
            await file.close();
          }

          const boxSize = header.readUInt32BE(0);
          const brand = header.toString("ascii", 8, 12);

          if (
            header.toString("ascii", 4, 8) !== "ftyp" ||
            boxSize < 16 ||
            boxSize > req.file.size ||
            ["qt  ", "heic", "heix", "avif", "avis"].includes(brand)
          ) {
            await removeFile();

            return res.status(400).json({
              success: false,
              error: "INVALID_MP4_VIDEO",
            });
          }

          return res.json({
            success: true,
            videoUrl:
              `${BASE}/videos/${path.basename(req.file.path)}`,
          });
        } catch {
          await removeFile();

          if (!res.headersSent) {
            return res.status(500).json({
              success: false,
              error: "VIDEO_UPLOAD_FAILED",
            });
          }
        }
      });
    },
  );

  // Ilovaning maxfiy kalitini ro'yxatdan o'tkazish
  app.post(
    "/api/instagram/session",
    wrap(async (req, res) => {
      const token = credential(req);

      if (!token) {
        return res.status(400).json({
          success: false,
          error: "INVALID_SESSION_KEY",
        });
      }

      const ownerId = hash(token);

      await db.runTransaction(async (transaction) => {
        const ref = identities.doc(ownerId);
        const snapshot = await transaction.get(ref);

        if (!snapshot.exists) {
          transaction.create(ref, {
            createdAt: FieldValue.serverTimestamp(),
            connectionGeneration: 0,
          });
        }
      });

      return res
        .set("Cache-Control", "no-store")
        .json({ success: true });
    }),
  );

  // Ilova uchun bir martalik ulanish havolasi
  app.post(
    "/api/instagram/connect",
    wrap(async (req, res) => {
      const ownerId = await owner(req, res);

      if (!ownerId) return;

      try {
        settings();
      } catch {
        return res.status(503).json({
          success: false,
          error: "INSTAGRAM_CONFIG_MISSING",
        });
      }

      const ticket = nonce();
      const identityRef = identities.doc(ownerId);

      await db.runTransaction(async (transaction) => {
        const identity = await transaction.get(identityRef);

        const generation =
          (identity.data().connectionGeneration || 0) + 1;

        transaction.update(identityRef, {
          connectionGeneration: generation,
        });

        transaction.set(tickets.doc(hash(ticket)), {
          ownerId,
          generation,
          expiresAt: new Date(Date.now() + 5 * 60 * 1000),
        });
      });

      return res
        .set("Cache-Control", "no-store")
        .json({
          success: true,
          connectUrl: `${BASE}/instagram/login?ticket=${ticket}`,
        });
    }),
  );

  // Instagram ruxsat oynasiga yo'naltirish
  app.get(
    "/instagram/login",
    wrap(async (req, res) => {
      res.set({
        "Cache-Control": "no-store",
        "Referrer-Policy": "no-referrer",
      });

      const ticket = req.query.ticket;

      if (!isKey(ticket)) {
        return res.status(400).send(
          "Instagramga ulanishni EasyAI ilovasidan boshlang.",
        );
      }

      const config = settings();
      const record = await consume(tickets.doc(hash(ticket)));

      if (!record) {
        return res.status(403).send(
          "Ulanish havolasi eskirgan. Ilovadan qayta boshlang.",
        );
      }

      const state = nonce();

      await states.doc(hash(state)).set({
        ownerId: record.ownerId,
        generation: record.generation,
        expiresAt: new Date(Date.now() + 10 * 60 * 1000),
      });

      res.cookie("ig_login_state", state, {
        ...COOKIE,
        maxAge: 10 * 60 * 1000,
      });

      const params = new URLSearchParams({
        client_id: config.appId,
        redirect_uri: REDIRECT,
        response_type: "code",
        scope: "instagram_business_basic,instagram_business_content_publish",
        state,
      });

      return res.redirect(
        `https://www.instagram.com/oauth/authorize?${params}`,
      );
    }),
  );

  // Instagramdan qaytish va tokenni saqlash
  app.get(
    "/instagram/callback",
    wrap(async (req, res) => {
      res.set({
        "Cache-Control": "no-store",
        "Referrer-Policy": "no-referrer",
      });

      const state = req.query.state;

      const cookie = (req.headers.cookie || "")
        .split(";")
        .map((item) => item.trim())
        .find((item) => item.startsWith("ig_login_state="))
        ?.slice("ig_login_state=".length);

      if (!isKey(state) || state !== cookie) {
        return res.status(403).send(
          "Ulanish tekshiruvi o'tmadi. Ilovadan qayta boshlang.",
        );
      }

      const record = await consume(states.doc(hash(state)));

      res.clearCookie("ig_login_state", COOKIE);

      if (!record) {
        return res.status(403).send(
          "Ulanish muddati tugagan. Ilovadan qayta boshlang.",
        );
      }

      if (req.query.error) {
        return res.status(400).send(
          "Instagramga ulanish bekor qilindi.",
        );
      }

      if (
        typeof req.query.code !== "string" ||
        !req.query.code
      ) {
        return res.status(400).send(
          "Tasdiqlash kodi kelmadi.",
        );
      }

      try {
        const config = settings();
        const form = new FormData();

        const fields = {
          client_id: config.appId,
          client_secret: config.appSecret,
          grant_type: "authorization_code",
          redirect_uri: REDIRECT,
          code: req.query.code,
        };

        for (const [name, value] of Object.entries(fields)) {
          form.set(name, value);
        }

        const result = await meta(
          "https://api.instagram.com/oauth/access_token",
          {
            method: "POST",
            body: form,
          },
        );

        const short = Array.isArray(result.data)
          ? result.data.length === 1
            ? result.data[0]
            : null
          : result;

        if (!short?.access_token || !short?.user_id) {
          throw new Error("INVALID_TOKEN_RESPONSE");
        }

        const url = new URL(
          "https://graph.instagram.com/access_token",
        );

        url.search = new URLSearchParams({
          grant_type: "ig_exchange_token",
          client_secret: config.appSecret,
          access_token: short.access_token,
        }).toString();

        const long = await meta(url);

        if (
          !long.access_token ||
          !Number.isFinite(long.expires_in) ||
          long.expires_in <= 0
        ) {
          throw new Error("INVALID_LONG_TOKEN");
        }

        const account = {
          instagramUserId: String(short.user_id),

          permissions:
            typeof short.permissions === "string"
              ? short.permissions.split(",")
              : Array.isArray(short.permissions)
                ? short.permissions
                : [],

          token: seal(
            long.access_token,
            config.key,
            record.ownerId,
          ),

          expiresAt: new Date(
            Date.now() + long.expires_in * 1000,
          ),

          connectedAt: FieldValue.serverTimestamp(),
        };

        await db.runTransaction(async (transaction) => {
          const identity = await transaction.get(
            identities.doc(record.ownerId),
          );

          if (
            !identity.exists ||
            identity.data().connectionGeneration !==
              record.generation
          ) {
            throw new Error("CONNECTION_SUPERSEDED");
          }

          transaction.set(
            connections.doc(record.ownerId),
            account,
          );
        });

        return res.type("text/plain").send(
          "Instagram hisobi saqlandi! EasyAI ilovasiga qaytib, ulanish holatini tekshiring.",
        );
      } catch (error) {
        console.error(
          "INSTAGRAM CONNECT FAILED:",
          error?.message === "CONNECTION_SUPERSEDED"
            ? "CONNECTION_SUPERSEDED"
            : "TOKEN_OR_STORAGE_FAILED",
        );

        return res.status(502).send(
          "Instagram hisobini saqlashda xato. Ilovadan qayta urinib ko'ring.",
        );
      }
    }),
  );

  // Faqat shu ilovaning ulanish holatini qaytarish
  app.get(
    "/api/instagram/status",
    wrap(async (req, res) => {
      const ownerId = await owner(req, res);

      if (!ownerId) return;

      const snapshot = await connections.doc(ownerId).get();
      const account = snapshot.data();

      const expired = account
        ? account.expiresAt.toMillis() <= Date.now()
        : false;

      return res
        .set("Cache-Control", "no-store")
        .json({
          success: true,
          connected: snapshot.exists && !expired,
          needsReconnect: expired,
          instagramUserId: account?.instagramUserId || null,
          expiresAt:
            account?.expiresAt.toDate().toISOString() || null,
        });
    }),
  );

  // Serverdagi ulanishni o'chirish
  app.delete(
    "/api/instagram/connection",
    wrap(async (req, res) => {
      const ownerId = await owner(req, res);

      if (!ownerId) return;

      await db.runTransaction(async (transaction) => {
        const ref = identities.doc(ownerId);
        const identity = await transaction.get(ref);

        transaction.update(ref, {
          connectionGeneration:
            (identity.data().connectionGeneration || 0) + 1,
        });

        transaction.delete(connections.doc(ownerId));
      });

      return res.json({ success: true });
    }),
  );
  // Instagram Reels uchun videoni tayyorlash.
  const reelJobs = db.collection("instagramPrivateReelJobs");

  function openInstagramToken(account, ownerId) {
    const saved = account.token;

    if (!saved || saved.version !== 1) {
      throw new Error("INVALID_STORED_TOKEN");
    }

    const decipher = crypto.createDecipheriv(
      "aes-256-gcm",
      settings().key,
      Buffer.from(saved.iv, "base64"),
    );

    decipher.setAAD(Buffer.from(ownerId));
    decipher.setAuthTag(Buffer.from(saved.tag, "base64"));

    return Buffer.concat([
      decipher.update(Buffer.from(saved.ciphertext, "base64")),
      decipher.final(),
    ]).toString("utf8");
  }

  app.post(
    "/api/instagram/reels/prepare",
    wrap(async (req, res) => {
      res.set("Cache-Control", "no-store");

      const ownerId = await owner(req, res);
      if (!ownerId) return;

      const { requestId, videoUrl, caption = "" } = req.body || {};

      if (
        !isKey(requestId) ||
        typeof videoUrl !== "string" ||
        typeof caption !== "string" ||
        caption.length > 2200
      ) {
        return res.status(400).json({
          success: false,
          error: "INVALID_REEL_REQUEST",
        });
      }

      // Hozir faqat EasyAI serveridagi MP4 videolar qabul qilinadi.
      let url;

      try {
        url = new URL(videoUrl);
      } catch {
        return res.status(400).json({
          success: false,
          error: "INVALID_VIDEO_URL",
        });
      }

      if (
        url.origin !== BASE ||
        url.username ||
        url.password ||
        url.search ||
        url.hash ||
        !/^\/videos\/[a-zA-Z0-9_-]+\.mp4$/.test(url.pathname)
      ) {
        return res.status(400).json({
          success: false,
          error: "USE_EASYAI_VIDEO_URL",
        });
      }

      const snapshot = await connections.doc(ownerId).get();
      const account = snapshot.data();

      if (
        !account ||
        account.expiresAt.toMillis() <= Date.now()
      ) {
        return res.status(409).json({
          success: false,
          error: "INSTAGRAM_RECONNECT_REQUIRED",
        });
      }

      if (
        !Array.isArray(account.permissions) ||
        !account.permissions.includes(
          "instagram_business_content_publish",
        )
      ) {
        return res.status(403).json({
          success: false,
          error: "INSTAGRAM_PUBLISH_PERMISSION_REQUIRED",
        });
      }

      const jobId = hash(`${ownerId}:${requestId}`);
      const jobRef = reelJobs.doc(jobId);
      const fingerprint = hash(
        JSON.stringify([url.href, caption, account.instagramUserId]),
      );

      // Bir xil so'rov qayta yuborilsa yangi konteyner ochilmaydi.
      const existing = await db.runTransaction(async (tx) => {
        const job = await tx.get(jobRef);

        if (job.exists) return job.data();

        tx.create(jobRef, {
          ownerId,
          instagramUserId: account.instagramUserId,
          fingerprint,
          state: "creating",
          createdAt: FieldValue.serverTimestamp(),
        });

        return null;
      });

      if (existing) {
        if (existing.fingerprint !== fingerprint) {
          return res.status(409).json({
            success: false,
            error: "REQUEST_ID_ALREADY_USED",
          });
        }

        return res.json({
          success: existing.state === "processing",
          jobId,
          state: existing.state,
        });
      }

      try {
        const accessToken = openInstagramToken(account, ownerId);

        const body = new URLSearchParams({
          media_type: "REELS",
          video_url: url.href,
          caption,
          share_to_feed: "true",
        });

        const response = await fetch(
          `https://graph.instagram.com/v25.0/${account.instagramUserId}/media`,
          {
            method: "POST",
            headers: {
              Authorization: `Bearer ${accessToken}`,
              "Content-Type": "application/x-www-form-urlencoded",
            },
            body,
            signal: AbortSignal.timeout(30000),
          },
        );

        const result = await response.json();

        if (!response.ok || result.error || !result.id) {
          throw new Error("INSTAGRAM_PREPARE_FAILED");
        }

        await jobRef.update({
          containerId: String(result.id),
          state: "processing",
          updatedAt: FieldValue.serverTimestamp(),
        });

        return res.json({
          success: true,
          jobId,
          state: "processing",
        });
      } catch {
        // Noaniq natijada avtomatik takrorlash qilinmaydi.
        await jobRef.update({
          state: "needs_check",
          updatedAt: FieldValue.serverTimestamp(),
        });

        return res.status(502).json({
          success: false,
          jobId,
          error: "INSTAGRAM_PREPARE_NEEDS_CHECK",
        });
      }
    }),
  );
  app.get(
    "/api/instagram/reels/:jobId/status",
    wrap(async (req, res) => {
      res.set("Cache-Control", "no-store");

      const ownerId = await owner(req, res);
      if (!ownerId) return;

      if (!isKey(req.params.jobId)) {
        return res.status(400).json({
          success: false,
          error: "INVALID_JOB_ID",
        });
      }

      const jobRef = reelJobs.doc(req.params.jobId);
      const jobSnapshot = await jobRef.get();
      const job = jobSnapshot.data();

      if (!job || job.ownerId !== ownerId) {
        return res.status(404).json({
          success: false,
          error: "REEL_NOT_FOUND",
        });
      }

      if (!job.containerId || job.state === "published") {
        return res.json({
          success: true,
          jobId: req.params.jobId,
          state: job.state,
          mediaId: job.mediaId || null,
        });
      }

      const accountSnapshot = await connections.doc(ownerId).get();
      const account = accountSnapshot.data();

      if (
        !account ||
        account.expiresAt.toMillis() <= Date.now() ||
        account.instagramUserId !== job.instagramUserId
      ) {
        return res.status(409).json({
          success: false,
          error: "INSTAGRAM_RECONNECT_REQUIRED",
        });
      }

      try {
        const accessToken = openInstagramToken(account, ownerId);

        const url = new URL(
          `https://graph.instagram.com/v25.0/${job.containerId}`,
        );
        url.searchParams.set("fields", "status_code");

        const response = await fetch(url, {
          headers: {
            Authorization: `Bearer ${accessToken}`,
          },
          signal: AbortSignal.timeout(30000),
        });

        const result = await response.json();
        const allowedStatuses = [
          "IN_PROGRESS",
          "FINISHED",
          "ERROR",
          "EXPIRED",
          "PUBLISHED",
        ];

        if (
          !response.ok ||
          result.error ||
          !allowedStatuses.includes(result.status_code)
        ) {
          throw new Error("INSTAGRAM_STATUS_FAILED");
        }

        await jobRef.update({
          containerStatus: result.status_code,
          checkedAt: FieldValue.serverTimestamp(),
        });

        return res.json({
          success: true,
          jobId: req.params.jobId,
          state: job.state,
          containerStatus: result.status_code,
          readyToPublish:
            job.state === "processing" &&
            result.status_code === "FINISHED",
        });
      } catch {
        return res.status(502).json({
          success: false,
          error: "INSTAGRAM_STATUS_FAILED",
        });
      }
    }),
  );
  app.post(
    "/api/instagram/reels/:jobId/publish",
    wrap(async (req, res) => {
      res.set("Cache-Control", "no-store");

      const ownerId = await owner(req, res);
      if (!ownerId) return;

      if (
        !isKey(req.params.jobId) ||
        req.body?.confirm !== true
      ) {
        return res.status(400).json({
          success: false,
          error: "PUBLISH_CONFIRMATION_REQUIRED",
        });
      }

      const jobRef = reelJobs.doc(req.params.jobId);
      const accountRef = connections.doc(ownerId);

      // Bir videoni ikki so'rov bir vaqtda joylamasin.
      const claimed = await db.runTransaction(async (tx) => {
        const jobSnapshot = await tx.get(jobRef);
        const accountSnapshot = await tx.get(accountRef);

        const job = jobSnapshot.data();
        const account = accountSnapshot.data();

        if (!job || job.ownerId !== ownerId) {
          return { error: "REEL_NOT_FOUND", status: 404 };
        }

        if (job.state === "published") {
          return { published: true, mediaId: job.mediaId };
        }

        if (
          !account ||
          account.expiresAt.toMillis() <= Date.now() ||
          account.instagramUserId !== job.instagramUserId
        ) {
          return {
            error: "INSTAGRAM_RECONNECT_REQUIRED",
            status: 409,
          };
        }

        if (
          !Array.isArray(account.permissions) ||
          !account.permissions.includes(
            "instagram_business_content_publish",
          )
        ) {
          return {
            error: "INSTAGRAM_PUBLISH_PERMISSION_REQUIRED",
            status: 403,
          };
        }

        if (!job.containerId || job.state !== "processing") {
          return {
            error: "REEL_NOT_READY_OR_ALREADY_SUBMITTED",
            status: 409,
          };
        }

        tx.update(jobRef, {
          state: "publishing",
          updatedAt: FieldValue.serverTimestamp(),
        });

        return { job, account };
      });

      if (claimed.error) {
        return res.status(claimed.status).json({
          success: false,
          error: claimed.error,
        });
      }

      if (claimed.published) {
        return res.json({
          success: true,
          state: "published",
          mediaId: claimed.mediaId,
        });
      }

      let publishStarted = false;

      try {
        const accessToken = openInstagramToken(
          claimed.account,
          ownerId,
        );

        const headers = {
          Authorization: `Bearer ${accessToken}`,
        };

        // Joylashdan oldin Instagramdan holatini tekshiramiz.
        const statusUrl = new URL(
          `https://graph.instagram.com/v25.0/${claimed.job.containerId}`,
        );
        statusUrl.searchParams.set("fields", "status_code");

        const statusResponse = await fetch(statusUrl, {
          headers,
          signal: AbortSignal.timeout(30000),
        });

        const statusResult = await statusResponse.json();

        if (!statusResponse.ok || statusResult.error) {
          throw new Error("STATUS_FAILED");
        }

        if (statusResult.status_code !== "FINISHED") {
          await jobRef.update({
            state: "processing",
            containerStatus: statusResult.status_code || "UNKNOWN",
            updatedAt: FieldValue.serverTimestamp(),
          });

          return res.status(409).json({
            success: false,
            error: "REEL_NOT_READY",
            containerStatus: statusResult.status_code || "UNKNOWN",
          });
        }

        const body = new URLSearchParams({
          creation_id: claimed.job.containerId,
        });

        publishStarted = true;

        const response = await fetch(
          `https://graph.instagram.com/v25.0/${claimed.job.instagramUserId}/media_publish`,
          {
            method: "POST",
            headers: {
              ...headers,
              "Content-Type": "application/x-www-form-urlencoded",
            },
            body,
            signal: AbortSignal.timeout(30000),
          },
        );

        const result = await response.json();

        if (!response.ok || result.error || !result.id) {
          throw new Error("PUBLISH_FAILED");
        }

        const mediaId = String(result.id);

        await jobRef.update({
          state: "published",
          mediaId,
          publishedAt: FieldValue.serverTimestamp(),
        });

        return res.json({
          success: true,
          jobId: req.params.jobId,
          state: "published",
          mediaId,
        });
      } catch {
        // Joylash so'rovi yuborilgan bo'lsa avtomatik takrorlamaymiz.
        await jobRef.update({
          state: publishStarted ? "publish_needs_check" : "processing",
          updatedAt: FieldValue.serverTimestamp(),
        });

        return res.status(502).json({
          success: false,
          jobId: req.params.jobId,
          error: publishStarted
            ? "INSTAGRAM_PUBLISH_NEEDS_CHECK"
            : "INSTAGRAM_STATUS_FAILED",
        });
      }
    }),
  );
}