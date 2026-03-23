import type { OpenClawPluginApi } from "openclaw/plugin-sdk/core";

interface LLMCallRecord {
  timestamp: number;
  sessionId: string;
  systemPrompt: string;
  prompt?: string;
  historyMessages: any[];
  messages?: any[];
  inputTokens?: number;
  outputTokens?: number;
  model?: string;
  provider?: string;
}

function getStoreDir(): string {
  return process.env.OPENCLAW_WORKSPACE
    ? `${process.env.OPENCLAW_WORKSPACE}/model_intercept`
    : '/home/bob/.openclaw/workspace/model_intercept';
}

async function ensureDir(path: string): Promise<void> {
  const fs = require('fs').promises;
  await fs.mkdir(path, { recursive: true });
}

async function saveCallRecord(record: LLMCallRecord): Promise<void> {
  const fs = require('fs').promises;
  const storeDir = getStoreDir();
  await ensureDir(storeDir);
  
  const date = new Date(record.timestamp).toISOString().split('T')[0];
  const logFile = `${storeDir}/${record.sessionId}_${date}.jsonl`;
  
  const line = JSON.stringify(record) + '\n';
  await fs.appendFile(logFile, line);
}

const plugin = {
  id: "model-intercept",
  name: "Model Intercept",
  description: "Intercept and log LLM API calls including complete system prompts",
  configSchema: {
    type: "object",
    properties: {},
    additionalProperties: false
  },
  register(api: OpenClawPluginApi) {
    console.log('[model-intercept] Registering model intercept plugin');
    
    api.on("llm_input", (event: any, ctx: any) => {
      try {
        const sessionId = ctx.sessionId || ctx.sessionKey || 'unknown';
        
        console.log(`[model-intercept] llm_input: session=${sessionId}, model=${event.model}`);
        
        const messages: any[] = [];
        
        if (event.systemPrompt) {
          messages.push({ role: 'system', content: event.systemPrompt });
        }
        
        if (Array.isArray(event.historyMessages)) {
          for (const m of event.historyMessages) {
            messages.push({
              role: m.role,
              content: typeof m.content === 'string' ? m.content : JSON.stringify(m.content),
              toolCalls: m.toolCalls,
              toolCallId: m.toolCallId,
              name: m.name,
            });
          }
        }
        
        if (event.prompt) {
          messages.push({ role: 'user', content: event.prompt });
        }
        
        const record: LLMCallRecord = {
          timestamp: Date.now(),
          sessionId,
          systemPrompt: event.systemPrompt || '',
          prompt: event.prompt || '',
          historyMessages: event.historyMessages || [],
          messages,
          model: event.model,
          provider: event.provider,
        };
        
        console.log(`[model-intercept] Captured: session=${sessionId}, systemPrompt length=${record.systemPrompt.length}, messages=${messages.length}`);
        
        setImmediate(() => {
          saveCallRecord(record).catch(err => {
            console.error('[model-intercept] Save error:', err);
          });
        });
      } catch (err) {
        console.error('[model-intercept] Error:', err);
      }
    });
    
    console.log('[model-intercept] Plugin registered successfully');
  },
};

export default plugin;
