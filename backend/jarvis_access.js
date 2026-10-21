import crypto from "crypto";
import {
  getFirestore,
  FieldValue,
} from "firebase-admin/firestore";

const digest = (value) =>
  crypto
    .createHash("sha256")
    .update(value)
    .digest("hex");

const hex64 = /^[a-f0-9]{64}$/;
const devicePattern = /^[a-f0-9]{16}$/;

export function isJarvisVoiceRecording(audio) {
  if (
    !Buffer.isBuffer(audio) ||
    audio.length < 44 ||
    audio.length > 2 * 1024 * 1024 ||
    audio.toString("ascii", 0, 4) !== "RIFF" ||
    audio.toString("ascii", 8, 12) !== "WAVE"
  ) {
    return false;
  }

  let validFormat = false;
  let dataBytes = 0;

  for (let offset = 12; offset + 8 <= audio.length;) {
    const name = audio.toString(
      "ascii",
      offset,
      offset + 4,
    );

    const size = audio.readUInt32LE(offset + 4);
    const start = offset + 8;

    if (start + size > audio.length) {
      return false;
    }

    if (name === "fmt ") {
      if (validFormat || size < 16) {
        return false;
      }

      validFormat =
        audio.readUInt16LE(start) === 1 &&
        audio.readUInt16LE(start + 2) === 1 &&
        audio.readUInt32LE(start + 4) === 16000 &&
        audio.readUInt32LE(start + 8) === 32000 &&
        audio.readUInt16LE(start + 12) === 2 &&
        audio.readUInt16LE(start + 14) === 16;

      if (!validFormat) {
        return false;
      }
    }

    if (name === "data") {
      dataBytes += size;
    }

    offset = start + size + (size % 2);
  }

  return (
    validFormat &&
    dataBytes > 0 &&
    dataBytes <= 31 * 32000 &&
    dataBytes % 2 === 0
  );
}

function integerSetting(name, fallback, max) {
  const raw = process.env[name];

  if (raw == null || raw === "") {
    return fallback;
  }

  const value = Number(raw);

  if (
    !Number.isSafeInteger(value) ||
    value < 0 ||
    value > max
  ) {
    throw new Error(`Invalid configuration: ${name}`);
  }

  return value;
}

function fail(status, code) {
  const error = new Error(code);
  error.status = status;
  error.code = code;

  return error;
}

export function createJarvisAccess(app) {
  const db = getFirestore();

  const settings = {
    // Keep these values in sync with the app's displayed terms.
    freeChats: 3,
    freeLiveMinutes: 1,
    chatCost: 1,
    liveCost: 1,

    dailyChats: integerSetting(
      "JARVIS_GLOBAL_DAILY_CHATS",
      100,
      100000,
    ),

    dailyTranscriptions: integerSetting(
      "JARVIS_GLOBAL_DAILY_TRANSCRIPTIONS",
      50,
      100000,
    ),

    dailySpeech: integerSetting(
      "JARVIS_GLOBAL_DAILY_SPEECH",
      100,
      100000,
    ),

    dailyLiveMinutes: integerSetting(
      "JARVIS_GLOBAL_DAILY_LIVE_MINUTES",
      30,
      100000,
    ),

    dailyRegistrations: integerSetting(
      "JARVIS_GLOBAL_DAILY_REGISTRATIONS",
      100,
      100000,
    ),
  };

  if (settings.chatCost < 1 || settings.liveCost < 1) {
    throw new Error(
      "Jarvis paid credit costs must be at least 1",
    );
  }

  function credentials(req) {
    const authorization = req.headers.authorization;

    const credential =
      typeof authorization === "string" &&
      authorization.startsWith("Bearer ")
        ? authorization.slice(7)
        : "";

    const deviceId = req.headers["x-easyai-device-id"];

    if (
      !hex64.test(credential) ||
      typeof deviceId !== "string" ||
      !devicePattern.test(deviceId)
    ) {
      throw fail(401, "JARVIS_AUTH_REQUIRED");
    }

    return {
      deviceId,
      credentialHash: digest(credential),
    };
  }

  const dailyRef = () =>
    db
      .collection("jarvisDailyUsage")
      .doc(new Date().toISOString().slice(0, 10));

  const number = (data, key) =>
    Number.isSafeInteger(data?.[key]) && data[key] >= 0
      ? data[key]
      : 0;

  function incrementDaily(
    transaction,
    ref,
    data,
    kind,
    cap,
  ) {
    if (number(data, kind) >= cap) {
      throw fail(429, "JARVIS_DAILY_LIMIT");
    }

    transaction.set(
      ref,
      {
        [kind]: number(data, kind) + 1,
      },
      { merge: true },
    );
  }

  // Register this route before the authorization middleware.
  app.post("/api/jarvis/session", async (req, res) => {
    try {
      const {
        deviceId,
        credentialHash,
      } = credentials(req);

      const userRef = db.collection("users").doc(deviceId);
      const daily = dailyRef();

      await db.runTransaction(async (transaction) => {
        const userSnapshot = await transaction.get(userRef);
        const user = userSnapshot.data() || {};

        if (
          user.jarvisCredentialHash &&
          user.jarvisCredentialHash !== credentialHash
        ) {
          throw fail(
            403,
            "JARVIS_DEVICE_ALREADY_LINKED",
          );
        }

        if (user.jarvisCredentialHash) {
          return;
        }

        const dailySnapshot = await transaction.get(daily);

        incrementDaily(
          transaction,
          daily,
          dailySnapshot.data(),
          "registrations",
          settings.dailyRegistrations,
        );

        const initial = userSnapshot.exists
          ? {}
          : {
              freeVideosRemaining: 1,
              credits: 0,
              createdAt: FieldValue.serverTimestamp(),
            };

        transaction.set(
          userRef,
          {
            ...initial,
            jarvisCredentialHash: credentialHash,
            jarvisFreeChatsRemaining: settings.freeChats,
            jarvisFreeLiveMinutesRemaining:
              settings.freeLiveMinutes,
            jarvisRegisteredAt:
              FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      });

      res.json({
        success: true,
        chatCreditCost: settings.chatCost,
        liveMinuteCreditCost: settings.liveCost,
      });
    } catch (error) {
      sendError(res, error);
    }
  });

  async function authorize(req) {
    const identity = credentials(req);

    const snapshot = await db
      .collection("users")
      .doc(identity.deviceId)
      .get();

    if (
      !snapshot.exists ||
      snapshot.data()?.jarvisCredentialHash !==
        identity.credentialHash
    ) {
      throw fail(401, "JARVIS_AUTH_REQUIRED");
    }

    req.jarvisIdentity = identity;

    return identity;
  }

  function sendError(res, error) {
    const status = Number.isInteger(error?.status)
      ? error.status
      : 503;

    const code =
      typeof error?.code === "string" &&
      error.code.startsWith("JARVIS_")
        ? error.code
        : "JARVIS_SERVICE_UNAVAILABLE";

    if (!res.headersSent) {
      res.status(status).json({
        success: false,
        code,
      });
    }
  }

  async function middleware(req, res, next) {
    try {
      await authorize(req);
      next();
    } catch (error) {
      sendError(res, error);
    }
  }

  async function reserveChat(req) {
    const requestId = req.body?.requestId;

    if (
      typeof requestId !== "string" ||
      !hex64.test(requestId)
    ) {
      throw fail(400, "JARVIS_INVALID_REQUEST");
    }

    const identity = req.jarvisIdentity;

    const ref = db
      .collection("jarvisRequests")
      .doc(`${identity.credentialHash}-${requestId}`);

    const userRef = db
      .collection("users")
      .doc(identity.deviceId);

    const daily = dailyRef();

    const fingerprint = digest(
      JSON.stringify([
        req.body.message,
        req.body.history || [],
      ]),
    );

    return db.runTransaction(async (transaction) => {
      const existing = await transaction.get(ref);

      if (existing.exists) {
        const saved = existing.data();

        if (saved.fingerprint !== fingerprint) {
          throw fail(409, "JARVIS_REQUEST_CONFLICT");
        }

        if (saved.status === "completed") {
          return {
            cached: saved.result,
          };
        }

        // A refunded provider failure can be retried with the same ID.
        // Pending requests remain locked; completed requests return the cache.
        if (saved.status !== "failed") {
          throw fail(409, "JARVIS_REQUEST_ALREADY_USED");
        }
      }

      const userSnapshot = await transaction.get(userRef);
      const dailySnapshot = await transaction.get(daily);
      const user = userSnapshot.data();

      if (
        user?.jarvisCredentialHash !==
        identity.credentialHash
      ) {
        throw fail(401, "JARVIS_AUTH_REQUIRED");
      }

      const free =
        number(user, "jarvisFreeChatsRemaining") > 0;

      if (
        !free &&
        number(user, "credits") < settings.chatCost
      ) {
        throw fail(402, "JARVIS_CREDITS_REQUIRED");
      }

      incrementDaily(
        transaction,
        daily,
        dailySnapshot.data(),
        "chats",
        settings.dailyChats,
      );

      const field = free
        ? "jarvisFreeChatsRemaining"
        : "credits";

      const amount = free ? 1 : settings.chatCost;

      transaction.update(userRef, {
        [field]: FieldValue.increment(-amount),
      });

      transaction.set(ref, {
        status: "pending",
        fingerprint,
        deviceId: identity.deviceId,
        credentialHash: identity.credentialHash,
        refundField: field,
        refundAmount: amount,
        createdAt: FieldValue.serverTimestamp(),
      });

      return { ref };
    });
  }

  async function completeChat(
    reservation,
    reply,
    extra = {},
  ) {
    const speechToken = crypto
      .randomBytes(32)
      .toString("hex");

    const result = {
      success: true,
      reply,
      speechToken,
      ...extra,
    };

    await reservation.ref.update({
      status: "completed",
      result,
      speechHash: digest(speechToken),
      completedAt: FieldValue.serverTimestamp(),
    });

    return result;
  }

  async function refundChat(reservation) {
    if (!reservation?.ref) return;

    await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(
        reservation.ref,
      );

      const saved = snapshot.data();

      if (saved?.status !== "pending") {
        return;
      }

      transaction.update(
        db.collection("users").doc(saved.deviceId),
        {
          [saved.refundField]: FieldValue.increment(
            saved.refundAmount,
          ),
        },
      );

      transaction.update(reservation.ref, {
        status: "failed",
        refundedAt: FieldValue.serverTimestamp(),
      });
    });
  }

  async function admitTranscription(req) {
    const identity = req.jarvisIdentity;
    const daily = dailyRef();

    const userRef = db
      .collection("users")
      .doc(identity.deviceId);

    await db.runTransaction(async (transaction) => {
      const userSnapshot = await transaction.get(userRef);
      const dailySnapshot = await transaction.get(daily);
      const user = userSnapshot.data();

      if (
        user?.jarvisCredentialHash !==
        identity.credentialHash
      ) {
        throw fail(401, "JARVIS_AUTH_REQUIRED");
      }

      if (
        number(user, "jarvisFreeChatsRemaining") === 0 &&
        number(user, "credits") < settings.chatCost
      ) {
        throw fail(402, "JARVIS_CREDITS_REQUIRED");
      }

      const day = daily.id;

      const used =
        user.jarvisTranscriptionDay === day
          ? number(user, "jarvisTranscriptionsToday")
          : 0;

      if (used >= 10) {
        throw fail(429, "JARVIS_DAILY_LIMIT");
      }

      incrementDaily(
        transaction,
        daily,
        dailySnapshot.data(),
        "transcriptions",
        settings.dailyTranscriptions,
      );

      transaction.update(userRef, {
        jarvisTranscriptionDay: day,
        jarvisTranscriptionsToday: used + 1,
      });
    });
  }

  async function admitSpeech(req) {
    const requestId = req.body?.requestId;
    const speechToken = req.body?.speechToken;

    if (
      typeof requestId !== "string" ||
      !hex64.test(requestId) ||
      typeof speechToken !== "string" ||
      !hex64.test(speechToken)
    ) {
      throw fail(400, "JARVIS_INVALID_REQUEST");
    }

    const identity = req.jarvisIdentity;

    const ref = db
      .collection("jarvisRequests")
      .doc(`${identity.credentialHash}-${requestId}`);

    const daily = dailyRef();

    await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(ref);
      const dailySnapshot = await transaction.get(daily);
      const saved = snapshot.data();

      if (
        saved?.status !== "completed" ||
        saved.speechHash !== digest(speechToken) ||
        saved.result?.reply !== req.body.text ||
        saved.speechAttempted
      ) {
        throw fail(403, "JARVIS_SPEECH_NOT_AVAILABLE");
      }

      incrementDaily(
        transaction,
        daily,
        dailySnapshot.data(),
        "speech",
        settings.dailySpeech,
      );

      transaction.update(ref, {
        speechAttempted: true,
      });
    });
  }

  async function reserveLiveMinute(
    req,
    sessionId,
    minute,
  ) {
    const identity = req.jarvisIdentity;

    const userRef = db
      .collection("users")
      .doc(identity.deviceId);

    const ref = db
      .collection("jarvisLiveCharges")
      .doc(`${sessionId}-${minute}`);

    const daily = dailyRef();

    return db.runTransaction(async (transaction) => {
      const existing = await transaction.get(ref);

      if (existing.exists) {
        throw fail(409, "JARVIS_REQUEST_ALREADY_USED");
      }

      const userSnapshot = await transaction.get(userRef);
      const dailySnapshot = await transaction.get(daily);
      const user = userSnapshot.data();

      if (
        user?.jarvisCredentialHash !==
        identity.credentialHash
      ) {
        throw fail(401, "JARVIS_AUTH_REQUIRED");
      }

      const lease = user.jarvisLiveLeaseUntil;

      const leaseMs =
        lease?.toMillis?.() ??
        (lease instanceof Date ? lease.getTime() : 0);

      if (
        minute === 1 &&
        leaseMs > Date.now() &&
        user.jarvisLiveSessionId !== sessionId
      ) {
        throw fail(409, "JARVIS_LIVE_ALREADY_ACTIVE");
      }

      if (
        minute > 1 &&
        user.jarvisLiveSessionId !== sessionId
      ) {
        throw fail(409, "JARVIS_LIVE_ALREADY_ACTIVE");
      }

      const free =
        number(user, "jarvisFreeLiveMinutesRemaining") > 0;

      if (
        !free &&
        number(user, "credits") < settings.liveCost
      ) {
        throw fail(402, "JARVIS_CREDITS_REQUIRED");
      }

      transaction.set(
        daily,
        {
          liveMinutes: FieldValue.increment(1),
        },
        { merge: true },
      );

      const field = free
        ? "jarvisFreeLiveMinutesRemaining"
        : "credits";

      const amount = free ? 1 : settings.liveCost;

      transaction.update(userRef, {
        [field]: FieldValue.increment(-amount),
        jarvisLiveSessionId: sessionId,
        jarvisLiveLeaseUntil: new Date(
          Date.now() + 90000,
        ),
      });

      transaction.set(ref, {
        status: "reserved",
        deviceId: identity.deviceId,
        refundField: field,
        refundAmount: amount,
        createdAt: FieldValue.serverTimestamp(),
      });

      return { ref };
    });
  }

  async function markLiveMinute(reservation) {
    await db.runTransaction(async (transaction) => {
      const saved = (
        await transaction.get(reservation.ref)
      ).data();

      if (saved?.status !== "reserved") {
        throw fail(409, "JARVIS_REQUEST_ALREADY_USED");
      }

      const userRef = db
        .collection("users")
        .doc(saved.deviceId);

      const user = (
        await transaction.get(userRef)
      ).data();

      const sessionId = reservation.ref.id.split("-")[0];

      if (user?.jarvisLiveSessionId !== sessionId) {
        throw fail(409, "JARVIS_LIVE_ALREADY_ACTIVE");
      }

      transaction.update(reservation.ref, {
        status: "started",
      });

      transaction.update(userRef, {
        jarvisLiveLeaseUntil: new Date(
          Date.now() + 90000,
        ),
      });
    });
  }

  async function refundLiveMinute(reservation) {
    if (!reservation?.ref) return;

    await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(
        reservation.ref,
      );

      const saved = snapshot.data();

      if (saved?.status !== "reserved") {
        return;
      }

      transaction.update(
        db.collection("users").doc(saved.deviceId),
        {
          [saved.refundField]: FieldValue.increment(
            saved.refundAmount,
          ),
        },
      );

      transaction.update(reservation.ref, {
        status: "refunded",
      });
    });
  }

  async function endLive(req, sessionId) {
    const ref = db
      .collection("users")
      .doc(req.jarvisIdentity.deviceId);

    await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(ref);

      if (
        snapshot.data()?.jarvisLiveSessionId !== sessionId
      ) {
        return;
      }

      transaction.update(ref, {
        jarvisLiveSessionId: FieldValue.delete(),
        jarvisLiveLeaseUntil: FieldValue.delete(),
      });
    });
  }

  return {
    authorize,
    middleware,
    sendError,
    reserveChat,
    completeChat,
    refundChat,
    admitTranscription,
    admitSpeech,
    reserveLiveMinute,
    markLiveMinute,
    refundLiveMinute,
    endLive,
  };
}