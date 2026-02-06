import type { AgentEvent } from "@mariozechner/pi-agent-core";
import type { EmbeddedPiSubscribeContext } from "./pi-embedded-subscribe.handlers.types.js";
import { emitAgentEvent } from "../infra/agent-events.js";
import { createInlineCodeState } from "../markdown/code-spans.js";

/**
 * Emit one final assistant event from accumulated buffers when the run ends.
 * Covers providers that never emit message_end or where extractAssistantText returned empty,
 * so the gateway chat buffer gets the reply and the UI shows it.
 */
function emitAssistantFallbackFromState(ctx: EmbeddedPiSubscribeContext) {
  const fromDelta = ctx.state.deltaBuffer?.trim() ?? "";
  const fromBlock = ctx.state.blockBuffer?.trim() ?? "";
  const fromTexts =
    ctx.state.assistantTexts.length > 0 ? ctx.state.assistantTexts.join("\n\n").trim() : "";
  const raw = fromDelta || fromBlock || fromTexts;
  if (!raw) {
    return;
  }
  const text = ctx.stripBlockTags(raw, { thinking: false, final: false }).trim();
  if (!text) {
    return;
  }
  ctx.log.debug(
    `embedded run agent_end: emitting assistant fallback from state (runId=${ctx.params.runId} len=${text.length})`,
  );
  emitAgentEvent({
    runId: ctx.params.runId,
    stream: "assistant",
    data: { text },
  });
  void ctx.params.onAgentEvent?.({
    stream: "assistant",
    data: { text },
  });
}

export function handleAgentStart(ctx: EmbeddedPiSubscribeContext) {
  ctx.log.debug(`embedded run agent start: runId=${ctx.params.runId}`);
  emitAgentEvent({
    runId: ctx.params.runId,
    stream: "lifecycle",
    data: {
      phase: "start",
      startedAt: Date.now(),
    },
  });
  void ctx.params.onAgentEvent?.({
    stream: "lifecycle",
    data: { phase: "start" },
  });
}

export function handleAutoCompactionStart(ctx: EmbeddedPiSubscribeContext) {
  ctx.state.compactionInFlight = true;
  ctx.ensureCompactionPromise();
  ctx.log.debug(`embedded run compaction start: runId=${ctx.params.runId}`);
  emitAgentEvent({
    runId: ctx.params.runId,
    stream: "compaction",
    data: { phase: "start" },
  });
  void ctx.params.onAgentEvent?.({
    stream: "compaction",
    data: { phase: "start" },
  });
}

export function handleAutoCompactionEnd(
  ctx: EmbeddedPiSubscribeContext,
  evt: AgentEvent & { willRetry?: unknown },
) {
  ctx.state.compactionInFlight = false;
  const willRetry = Boolean(evt.willRetry);
  if (willRetry) {
    ctx.noteCompactionRetry();
    ctx.resetForCompactionRetry();
    ctx.log.debug(`embedded run compaction retry: runId=${ctx.params.runId}`);
  } else {
    ctx.maybeResolveCompactionWait();
  }
  emitAgentEvent({
    runId: ctx.params.runId,
    stream: "compaction",
    data: { phase: "end", willRetry },
  });
  void ctx.params.onAgentEvent?.({
    stream: "compaction",
    data: { phase: "end", willRetry },
  });
}

export function handleAgentEnd(ctx: EmbeddedPiSubscribeContext) {
  ctx.log.debug(`embedded run agent end: runId=${ctx.params.runId}`);
  // Emit assistant text from accumulated buffers if we have any (e.g. provider didn't emit message_end).
  emitAssistantFallbackFromState(ctx);
  // Lifecycle "end" is emitted by the attempt via emitLifecycleEnd(lastAssistant) so the chat
  // can get the final message from lastAssistant when the provider never streamed (e.g. sphere-llm).

  if (ctx.params.onBlockReply) {
    if (ctx.blockChunker?.hasBuffered()) {
      ctx.blockChunker.drain({ force: true, emit: ctx.emitBlockChunk });
      ctx.blockChunker.reset();
    } else if (ctx.state.blockBuffer.length > 0) {
      ctx.emitBlockChunk(ctx.state.blockBuffer);
      ctx.state.blockBuffer = "";
    }
  }

  ctx.state.blockState.thinking = false;
  ctx.state.blockState.final = false;
  ctx.state.blockState.inlineCode = createInlineCodeState();

  if (ctx.state.pendingCompactionRetry > 0) {
    ctx.resolveCompactionRetry();
  } else {
    ctx.maybeResolveCompactionWait();
  }
}
