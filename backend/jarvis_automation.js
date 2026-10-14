import crypto from "crypto";
import { FieldValue } from "firebase-admin/firestore";
import {
  commandIntent,
  validDraft,
} from "./jarvis_commands.js";

const hash = (value) =>
  crypto
    .createHash("sha256")
    .update(value)
    .digest("hex");

const activeStates = [
  "queued",
  "starting",
  "generating",
  "generated",
  "preparing",
  "processing",
  "publishing",
];

const errorCode = (error) =>
  String(error?.code || "AUTOMATION_FAILED").slice(0, 100);

export function createJarvisAutomation(db, instagram, video) {
  const jobs = db.collection("jarvisAutomationJobs");
  const owners = db.collection("jarvisAutomationOwners");

  const workerId = crypto.randomBytes(16).toString("hex");

  let working = false;

  function publicJob(id, job) {
    return {
      id,
      state: job.state,
      title: job.title,
      prompt: job.prompt,
      caption: job.caption,
      mode: job.mode,
      username: job.username || null,
      videoUrl: job.videoUrl || null,
      error: job.error || null,
      mediaId: job.mediaId || null,
      createdAt: job.createdAt?.toMillis?.() || 0,
    };
  }

  async function submit(
    identity,
    requestId,
    command,
    draft,
    language,
  ) {
    const mode = commandIntent(command);

    if (
      !["create", "create_publish"].includes(mode) ||
      !validDraft(draft) ||
      !/^[a-f0-9]{64}$/.test(requestId)
    ) {
      throw Object.assign(
        new Error("EXPLICIT_VIDEO_COMMAND_REQUIRED"),
        {
          code: "EXPLICIT_VIDEO_COMMAND_REQUIRED",
        },
      );
    }

    const id = hash(
      `${identity.credentialHash}:${requestId}`,
    );

    const ref = jobs.doc(id);

    const fingerprint = hash(
      JSON.stringify([command, draft, mode]),
    );

    const previous = (await ref.get()).data();

    if (previous) {
      if (
        previous.ownerId !== identity.credentialHash ||
        previous.fingerprint !== fingerprint
      ) {
        throw Object.assign(
          new Error("COMMAND_CONFLICT"),
          { code: "COMMAND_CONFLICT" },
        );
      }

      return publicJob(id, previous);
    }

    let account;

    if (mode === "create_publish") {
      account = await instagram.account(
        identity.credentialHash,
      );

      if (!account.canPublish) {
        throw Object.assign(
          new Error("INSTAGRAM_PUBLISH_PERMISSION_REQUIRED"),
          {
            code: "INSTAGRAM_PUBLISH_PERMISSION_REQUIRED",
          },
        );
      }
    }

    const ownerRef = owners.doc(identity.credentialHash);
    const userRef = db.collection("users").doc(identity.deviceId);

    return db.runTransaction(async (tx) => {
      const [saved, owner, user] = await Promise.all([
        tx.get(ref),
        tx.get(ownerRef),
        tx.get(userRef),
      ]);

      if (saved.exists) {
        if (saved.data().fingerprint !== fingerprint) {
          throw Object.assign(
            new Error("COMMAND_CONFLICT"),
            { code: "COMMAND_CONFLICT" },
          );
        }

        return publicJob(id, saved.data());
      }

      const usage = user.data();

      if (
        usage?.jarvisCredentialHash !==
        identity.credentialHash
      ) {
        throw Object.assign(
          new Error("DEVICE_SESSION_MISMATCH"),
          { code: "DEVICE_SESSION_MISMATCH" },
        );
      }

      if (
        !(usage.freeVideosRemaining > 0) &&
        !(usage.credits >= 6)
      ) {
        throw Object.assign(
          new Error("FREE_LIMIT_REACHED"),
          { code: "FREE_LIMIT_REACHED" },
        );
      }

      if (owner.data()?.activeJob) {
        throw Object.assign(
          new Error("AUTOMATION_ALREADY_ACTIVE"),
          { code: "AUTOMATION_ALREADY_ACTIVE" },
        );
      }

      const day = new Date().toISOString().slice(0, 10);

      const count =
        owner.data()?.day === day
          ? owner.data().count || 0
          : 0;

      if (count >= 20) {
        throw Object.assign(
          new Error("AUTOMATION_DAILY_LIMIT"),
          { code: "AUTOMATION_DAILY_LIMIT" },
        );
      }

      const job = {
        ownerId: identity.credentialHash,
        deviceId: identity.deviceId,
        fingerprint,
        command: command.slice(0, 6000),
        language: language || "en",
        title: draft.title.trim(),
        prompt: draft.prompt.trim(),
        caption: draft.caption.trim(),
        mode,
        instagramUserId: account?.id || null,
        username: account?.username || null,
        state: "queued",
        createdAt: FieldValue.serverTimestamp(),
        nextRun: Date.now(),
        leaseUntil: 0,
      };

      tx.create(ref, job);

      tx.set(
        ownerRef,
        {
          activeJob: id,
          day,
          count: count + 1,
          recentJobs: [
            id,
            ...(owner.data()?.recentJobs || []).filter(
              (value) => value !== id,
            ),
          ].slice(0, 20),
        },
        { merge: true },
      );

      return publicJob(id, job);
    });
  }

  async function finish(ref, state, fields = {}) {
    await db.runTransaction(async (tx) => {
      const job = (await tx.get(ref)).data();

      if (!job) return;

      const ownerRef = owners.doc(job.ownerId);
      const owner = (await tx.get(ownerRef)).data();

      tx.update(ref, {
        state,
        ...fields,
        leaseUntil: 0,
        updatedAt: FieldValue.serverTimestamp(),
      });

      // An unknown result stays locked until it is checked.
      if (
        owner?.activeJob === ref.id &&
        !state.endsWith("needs_check")
      ) {
        tx.update(ownerRef, {
          activeJob: FieldValue.delete(),
        });
      }
    });
  }

  async function verifyAccount(job) {
    if (job.mode !== "create_publish") return;

    const account = await instagram.account(job.ownerId);

    if (account.id !== job.instagramUserId) {
      throw Object.assign(
        new Error("INSTAGRAM_ACCOUNT_CHANGED"),
        { code: "INSTAGRAM_ACCOUNT_CHANGED" },
      );
    }

    if (!account.canPublish) {
      throw Object.assign(
        new Error("INSTAGRAM_PUBLISH_PERMISSION_REQUIRED"),
        {
          code: "INSTAGRAM_PUBLISH_PERMISSION_REQUIRED",
        },
      );
    }
  }

  async function process(ref, job) {
    try {
      if (job.state === "starting") {
        // Do not repeat a generation request after an
        // interrupted start: the provider may have accepted it.
        return finish(ref, "generation_needs_check", {
          error: "GENERATION_RESULT_UNKNOWN",
        });
      }

      if (job.state === "publishing") {
        const result = await instagram.status(
          job.ownerId,
          job.reelId,
        );

        if (result.state === "published") {
          return finish(ref, "published", {
            mediaId: result.mediaId || null,
          });
        }

        return finish(ref, "publish_needs_check", {
          error: "PUBLISH_RESULT_UNKNOWN",
        });
      }

      if (job.state === "queued") {
        await verifyAccount(job);
        await video.reserve(job, ref.id);

        await ref.update({
          state: "starting",
          updatedAt: FieldValue.serverTimestamp(),
        });

        let operation;

        try {
          operation = await video.start(job);
        } catch (error) {
          if (error.definite) {
            await video.refund(ref.id);

            return finish(ref, "failed", {
              error: errorCode(error),
            });
          }

          return finish(ref, "generation_needs_check", {
            error: "GENERATION_RESULT_UNKNOWN",
          });
        }

        await ref.update({
          state: "generating",
          operation,
          nextRun: Date.now() + 10000,
          leaseUntil: 0,
          updatedAt: FieldValue.serverTimestamp(),
        });

        return;
      }

      if (job.state === "generating") {
        const result = await video.poll(job, ref.id);

        if (!result.done) {
          const startedAt =
            job.createdAt?.toMillis?.() || Date.now();

          if (Date.now() - startedAt > 30 * 60 * 1000) {
            return finish(ref, "generation_needs_check", {
              error: "GENERATION_TIMED_OUT",
            });
          }

          return ref.update({
            nextRun: Date.now() + 10000,
            leaseUntil: 0,
          });
        }

        if (result.error) {
          await video.refund(ref.id);

          return finish(ref, "failed", {
            error: result.error,
          });
        }

        await video.complete(ref.id, result.videoUrl);

        if (job.mode === "create") {
          return finish(ref, "ready", {
            videoUrl: result.videoUrl,
          });
        }

        return ref.update({
          state: "generated",
          videoUrl: result.videoUrl,
          nextRun: Date.now(),
          leaseUntil: 0,
        });
      }

      if (
        job.state === "generated" ||
        job.state === "preparing"
      ) {
        await verifyAccount(job);
        await video.ensureAvailable(job, ref.id);

        const requestId = hash(`reel:${ref.id}`);

        // Save the deterministic Reel ID before contacting Meta.
        const reelId = hash(
          `${job.ownerId}:${requestId}`,
        );

        await ref.update({
          state: "preparing",
          reelId,
        });

        const result = await instagram.prepare(
          job.ownerId,
          {
            requestId,
            videoUrl: job.videoUrl,
            caption: job.caption,
          },
        );

        if (result.state === "needs_check") {
          return finish(ref, "prepare_needs_check", {
            error: "PREPARATION_RESULT_UNKNOWN",
            reelId,
          });
        }

        return ref.update({
          state: "processing",
          reelId,
          nextRun: Date.now() + 60000,
          leaseUntil: 0,
        });
      }

      if (job.state === "processing") {
        await verifyAccount(job);

        const result = await instagram.status(
          job.ownerId,
          job.reelId,
        );

        if (result.state === "published") {
          return finish(ref, "published", {
            mediaId: result.mediaId || null,
          });
        }

        if (
          result.state === "publish_needs_check" ||
          result.containerStatus === "PUBLISHED"
        ) {
          return finish(ref, "publish_needs_check", {
            error: "PUBLISH_RESULT_UNKNOWN",
          });
        }

        if (result.state === "needs_check") {
          return finish(ref, "prepare_needs_check", {
            error: "PREPARATION_RESULT_UNKNOWN",
          });
        }

        if (
          ["ERROR", "EXPIRED"].includes(
            result.containerStatus,
          )
        ) {
          return finish(ref, "failed", {
            error: "INSTAGRAM_PREPARATION_FAILED",
          });
        }

        if (result.containerStatus !== "FINISHED") {
          return ref.update({
            nextRun: Date.now() + 60000,
            leaseUntil: 0,
          });
        }

        await ref.update({
          state: "publishing",
          updatedAt: FieldValue.serverTimestamp(),
        });

        const published = await instagram.publish(
          job.ownerId,
          job.reelId,
        );

        if (published.state !== "published") {
          return finish(ref, "publish_needs_check", {
            error: "PUBLISH_RESULT_UNKNOWN",
          });
        }

        return finish(ref, "published", {
          mediaId: published.mediaId || null,
        });
      }
    } catch (error) {
      const saved = (await ref.get()).data();

      if (saved?.state === "starting") {
        return finish(ref, "generation_needs_check", {
          error: "GENERATION_RESULT_UNKNOWN",
        });
      }

      if (saved?.state === "publishing") {
        return finish(ref, "publish_needs_check", {
          error: "PUBLISH_RESULT_UNKNOWN",
        });
      }

      if (saved?.state === "queued") {
        await video.refund(ref.id);

        return finish(ref, "failed", {
          error: errorCode(error),
        });
      }

      if (saved?.state === "preparing") {
        return finish(ref, "prepare_needs_check", {
          error: errorCode(error),
        });
      }

      if (
        /ACCOUNT_CHANGED|RECONNECT|PERMISSION/.test(
          errorCode(error),
        )
      ) {
        return finish(ref, "failed", {
          error: errorCode(error),
        });
      }

      await ref.update({
        nextRun: Date.now() + 60000,
        leaseUntil: 0,
        error: errorCode(error),
      });
    }
  }

  async function tick() {
    if (working) return;

    working = true;

    try {
      // This query does not need a custom composite index.
      const snapshot = await jobs
        .where("state", "in", activeStates)
        .limit(100)
        .get();

      for (const doc of snapshot.docs) {
        const claimed = await db.runTransaction(
          async (tx) => {
            const job = (await tx.get(doc.ref)).data();

            if (
              !job ||
              !activeStates.includes(job.state) ||
              job.nextRun > Date.now() ||
              job.leaseUntil > Date.now()
            ) {
              return null;
            }

            tx.update(doc.ref, {
              workerId,
              leaseUntil: Date.now() + 120000,
            });

            return job;
          },
        );

        if (claimed) {
          await process(doc.ref, claimed);
        }
      }
    } catch (error) {
      console.error(
        "Jarvis automation worker:",
        errorCode(error),
      );
    } finally {
      working = false;
    }
  }

  const timer = setInterval(() => {
    void tick();
  }, 5000);

  timer.unref();
  void tick();

  return {
    submit,

    business: (identity, command) => {
      const intent = commandIntent(command);

      if (
        !["business_on", "business_off"].includes(intent)
      ) {
        throw Object.assign(
          new Error("EXPLICIT_BUSINESS_COMMAND_REQUIRED"),
          {
            code: "EXPLICIT_BUSINESS_COMMAND_REQUIRED",
          },
        );
      }

      return instagram.business(
        identity.credentialHash,
        intent === "business_on",
      );
    },

    async list(identity) {
      const owner = (
        await owners.doc(identity.credentialHash).get()
      ).data();

      const ids = (owner?.recentJobs || []).filter(
        (id) => /^[a-f0-9]{64}$/.test(id),
      );

      if (!ids.length) return [];

      const snapshots = await db.getAll(
        ...ids.map((id) => jobs.doc(id)),
      );

      return snapshots
        .filter(
          (doc) =>
            doc.exists &&
            doc.data().ownerId === identity.credentialHash,
        )
        .map((doc) => publicJob(doc.id, doc.data()))
        .sort((a, b) => b.createdAt - a.createdAt);
    },

    async reconcile(identity, id) {
      if (!/^[a-f0-9]{64}$/.test(id)) {
        throw new Error("INVALID_TASK_ID");
      }

      const ref = jobs.doc(id);
      const job = (await ref.get()).data();

      if (
        !job ||
        job.ownerId !== identity.credentialHash
      ) {
        throw new Error("TASK_NOT_FOUND");
      }

      if (
        job.reelId &&
        [
          "publish_needs_check",
          "prepare_needs_check",
        ].includes(job.state)
      ) {
        const result = await instagram.status(
          job.ownerId,
          job.reelId,
        );

        if (result.state === "published") {
          await finish(ref, "published", {
            mediaId: result.mediaId || null,
          });
        }
      }

      return publicJob(id, (await ref.get()).data());
    },
  };
}