import "server-only";
import { createHash } from "node:crypto";

export type AiTurn = { role: "user" | "assistant"; content: string };
export type AiUsage = { input_tokens: number; output_tokens: number; total_tokens: number };
export type AiUsageWithEstimate = AiUsage & { estimated_cost_usd: number | null };
export type AiTaskDraft = { title: string; description: string; priority: "low" | "medium" | "high" | "urgent"; suggested_due_date: string | null };

type ResponsePayload = {
  output?: Array<{ type?: string; content?: Array<{ type?: string; text?: string }> }>;
  usage?: { input_tokens?: number; output_tokens?: number; total_tokens?: number };
};

export function hasAiPricingConfigured(): boolean {
  const inputValue = process.env.OPENAI_INPUT_USD_PER_1M_TOKENS?.trim();
  const outputValue = process.env.OPENAI_OUTPUT_USD_PER_1M_TOKENS?.trim();
  if (!inputValue || !outputValue) return false;
  const inputRate = Number(inputValue);
  const outputRate = Number(outputValue);
  return Number.isFinite(inputRate) && Number.isFinite(outputRate) && inputRate >= 0 && outputRate >= 0;
}

function estimateCost(usage: AiUsage): number | null {
  const inputValue = process.env.OPENAI_INPUT_USD_PER_1M_TOKENS?.trim();
  const outputValue = process.env.OPENAI_OUTPUT_USD_PER_1M_TOKENS?.trim();
  if (!hasAiPricingConfigured() || !inputValue || !outputValue) return null;
  const inputRate = Number(inputValue);
  const outputRate = Number(outputValue);
  if (!Number.isFinite(inputRate) || !Number.isFinite(outputRate) || inputRate < 0 || outputRate < 0) return null;
  return Number(((usage.input_tokens * inputRate + usage.output_tokens * outputRate) / 1_000_000).toFixed(8));
}

export function estimateAiReservationCost(inputCharacters: number, maximumOutputTokens: number): number | null {
  const inputValue = process.env.OPENAI_INPUT_USD_PER_1M_TOKENS?.trim();
  const outputValue = process.env.OPENAI_OUTPUT_USD_PER_1M_TOKENS?.trim();
  if (!hasAiPricingConfigured() || !inputValue || !outputValue) return null;
  const inputRate = Number(inputValue);
  const outputRate = Number(outputValue);
  if (!Number.isFinite(inputRate) || !Number.isFinite(outputRate) || inputRate < 0 || outputRate < 0) return null;
  const conservativeInputTokens = Math.ceil(Math.max(0, inputCharacters) / 2);
  return Number(((conservativeInputTokens * inputRate + Math.max(0, maximumOutputTokens) * outputRate) / 1_000_000).toFixed(8));
}

export async function getWorkspaceAssistantReply(instructions: string, turns: AiTurn[], userId: string) {
  const apiKey = process.env.OPENAI_API_KEY;
  const model = process.env.OPENAI_MODEL;
  if (!apiKey || !model) throw new Error("AI is not configured.");

  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model,
      instructions,
      input: turns.map(({ role, content }) => ({ role, content })),
      max_output_tokens: 900,
      store: false,
      safety_identifier: createHash("sha256").update(userId).digest("hex"),
    }),
    cache: "no-store",
    signal: AbortSignal.timeout(45_000),
  });
  const payload = await response.json() as ResponsePayload;
  if (!response.ok) throw new Error("AI provider request failed.");

  const answer = (payload.output ?? [])
    .filter((item) => item.type === "message")
    .flatMap((item) => item.content ?? [])
    .filter((part) => part.type === "output_text")
    .map((part) => part.text ?? "")
    .join("\n")
    .trim();
  if (!answer) throw new Error("AI provider returned no text.");
  const input = Math.max(0, Number(payload.usage?.input_tokens ?? 0));
  const output = Math.max(0, Number(payload.usage?.output_tokens ?? 0));
  const tokenUsage: AiUsage = { input_tokens: input, output_tokens: output, total_tokens: Math.max(0, Number(payload.usage?.total_tokens ?? input + output)) };
  const usage: AiUsageWithEstimate = { ...tokenUsage, estimated_cost_usd: estimateCost(tokenUsage) };
  return { answer, usage, model };
}

export async function draftWorkspaceTask(prompt: string, userId: string) {
  const apiKey = process.env.OPENAI_API_KEY;
  const model = process.env.OPENAI_MODEL;
  if (!apiKey || !model) throw new Error("AI is not configured.");
  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model,
      instructions: "Draft one clear, actionable agency task from the request. Return only the required structured task fields. Do not claim the task was created. Do not invent an assignee, project, or due date. Set suggested_due_date to null unless the user gives an explicit calendar date. Keep the description concise, concrete, and faithful to the request.",
      input: prompt,
      max_output_tokens: 500,
      store: false,
      safety_identifier: createHash("sha256").update(userId).digest("hex"),
      text: {
        format: {
          type: "json_schema",
          name: "agency_task_draft",
          strict: true,
          schema: {
            type: "object",
            properties: {
              title: { type: "string" },
              description: { type: "string" },
              priority: { type: "string", enum: ["low", "medium", "high", "urgent"] },
              suggested_due_date: { type: ["string", "null"], format: "date" },
            },
            required: ["title", "description", "priority", "suggested_due_date"],
            additionalProperties: false,
          },
        },
      },
    }),
    cache: "no-store",
    signal: AbortSignal.timeout(45_000),
  });
  const payload = await response.json() as ResponsePayload;
  if (!response.ok) throw new Error("AI provider request failed.");
  const text = (payload.output ?? []).filter((item) => item.type === "message").flatMap((item) => item.content ?? []).filter((part) => part.type === "output_text").map((part) => part.text ?? "").join("").trim();
  if (!text) throw new Error("AI provider returned no task draft.");
  const draft = JSON.parse(text) as AiTaskDraft;
  if (typeof draft.title !== "string" || typeof draft.description !== "string" || !["low", "medium", "high", "urgent"].includes(draft.priority) || (draft.suggested_due_date !== null && !/^\d{4}-\d{2}-\d{2}$/.test(draft.suggested_due_date))) throw new Error("AI task draft was invalid.");
  const input = Math.max(0, Number(payload.usage?.input_tokens ?? 0));
  const output = Math.max(0, Number(payload.usage?.output_tokens ?? 0));
  const tokenUsage: AiUsage = { input_tokens: input, output_tokens: output, total_tokens: Math.max(0, Number(payload.usage?.total_tokens ?? input + output)) };
  return { draft, model, usage: { ...tokenUsage, estimated_cost_usd: estimateCost(tokenUsage) } satisfies AiUsageWithEstimate };
}
