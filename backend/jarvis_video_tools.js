export const videoDraftTool = {
  name: "prepare_video_draft",
  description:
    "Send one video idea, an 8-second video prompt, and caption " +
    "with hashtags to the app for user review. " +
    "Does not generate or publish a video.",
  parameters: {
    type: "OBJECT",
    properties: {
      title: {
        type: "STRING",
      },
      prompt: {
        type: "STRING",
      },
      caption: {
        type: "STRING",
      },
    },
    required: [
      "title",
      "prompt",
      "caption",
    ],
  },
};

export function createVideoDraftHandler(sendPhone) {
  const handled = new Map();

  return (calls) => {
    if (!Array.isArray(calls) || calls.length > 16) {
      throw new Error("INVALID_TOOL_CALLS");
    }

    return calls.map((call) => {
      if (
        !call ||
        typeof call.id !== "string" ||
        !call.id ||
        typeof call.name !== "string"
      ) {
        throw new Error("INVALID_TOOL_CALL");
      }

      if (handled.has(call.id)) {
        return handled.get(call.id);
      }

      if (handled.size >= 32) {
        throw new Error("TOOL_CALL_LIMIT");
      }

      const args = call.args;
      let response;

      if (call.name !== videoDraftTool.name) {
        response = {
          error: "UNKNOWN_TOOL",
        };
      } else if (
        !args ||
        typeof args.title !== "string" ||
        !args.title.trim() ||
        args.title.length > 160 ||
        typeof args.prompt !== "string" ||
        !args.prompt.trim() ||
        args.prompt.length > 2000 ||
        typeof args.caption !== "string" ||
        args.caption.length > 2200
      ) {
        response = {
          error: "INVALID_DRAFT",
        };
      } else {
        sendPhone({
          type: "videoDraft",
          id: call.id,
          title: args.title.trim(),
          prompt: args.prompt.trim(),
          caption: args.caption.trim(),
        });

        response = {
          status: "draft_sent_to_app",
          generated: false,
          published: false,
          instruction:
            "Tell the user to review the draft in the app. " +
            "Do not claim generation or publication.",
        };
      }

      const result = {
        id: call.id,
        name: call.name,
        response,
      };

      handled.set(call.id, result);

      return result;
    });
  };
}