# model-dumper

Dump and analyze OpenClaw model interactions.

## Description

- Interaction rounds count
- Complete prompts and outputs
- Token usage per API call
- Export to JSONL with system prompt
- Intercept LLM API calls
- Detailed token statistics per turn
- Token breakdown (system/history/user/tools)
- Cache hit rate analysis

## System Prompt Capture

The system prompt is built dynamically at runtime. This skill reconstructs it from:

1. **Skills Snapshot** - from sessions.json
2. **SOUL.md** - AI identity/personality
3. **USER.md** - User information
4. **AGENTS.md** - Workspace context
5. **MEMORY.md** - Long-term memory (if exists)
6. **Recent memory files** - memory/YYYY-MM-DD.md

## Commands

- `analyze` - Show session statistics
- `export` - Export to JSONL (from session files)
- `rounds` - Show round count
- `prompts` - Show prompts sent to model
- `outputs` - Show model outputs
- `intercept` - Show intercepted LLM calls
- `export-full` - Export with system prompt
- `system-prompt` - Show reconstructed system prompt
- `latest` - Show latest session ID
- `token-stats [session] [file]` - Detailed token statistics per turn
- `token-stats-all [file]` - Token stats for all sessions
- `token-export [session] [file]` - Export token stats to CSV

## JSONL Format (export)

```json
{
  "timestamp": 1234567890000,
  "input": "...",
  "output": "...",
  "token_usage": {"input": 1000, "output": 500, "total": 1500},
  "model": "stepfun/step-3.5-flash:free",
  "stop_reason": "stop"
}
```

## JSONL Format (export-full)

```json
{
  "timestamp": 1234567890000,
  "input": "{\"systemPrompt\": {\"skills\": \"...\", \"SOUL\": \"...\", ...}, \"prompt\": \"...\", \"messages\": [...]}",
  "output": "...",
  "token_usage": {"input": 1000, "output": 500, "total": 1500},
  "model": "stepfun/step-3.5-flash:free",
  "provider": "openrouter",
  "source": "intercept"
}
```

## Usage Examples

```bash
# Analyze session
model-dumper analyze

# Export to JSONL
model-dumper export

# Show system prompt
model-dumper system-prompt

# Export with system prompt
model-dumper export-full main

# Show intercepted calls
model-dumper intercept main

# Token statistics for a session
model-dumper token-stats rest-api-dev

# Token statistics with output file
model-dumper token-stats rest-api-dev /tmp/stats.txt

# Token stats for all sessions
model-dumper token-stats-all

# Export token stats to CSV
model-dumper token-export rest-api-dev
```

## Token Statistics Output

The `token-stats` command provides:

- **Summary**: Total turns, API calls, input/output tokens, cache stats
- **Per-API-Call breakdown**: Each API call's input/output tokens, cache, tools, stop reason
- **Per-Turn summary**: Aggregated by user turn
- **Input breakdown**: System prompt estimate, context growth rate, max context

### Per-API-Call Columns

| Column | Description |
|--------|-------------|
| # | API call sequence number |
| Turn | User turn number |
| Input | Input tokens for this call |
| Output | Output tokens for this call |
| Cache | Cache read tokens |
| Tools | Number of tool calls |
| Stop Reason | Why the call stopped (toolUse, stop, etc.) |
| User Prompt | Truncated user prompt |

### Per-Turn Columns

| Column | Description |
|--------|-------------|
| Turn | User turn number |
| Calls | Number of API calls in this turn |
| Total Input | Sum of input tokens |
| Total Output | Sum of output tokens |
| First In | Input tokens on first call |
| Last In | Input tokens on last call |
| Growth | Token increase (Last In - First In) |

## Timing Statistics (v0.9)

The `token-export` command now includes timing data from `raw-stream.jsonl`:

### Timing Columns

| Column | Description |
|--------|-------------|
| LLM Time (s) | Session-based LLM execution time |
| Tool Time (s) | Tool execution time |
| Total Time (s) | LLM + Tool time |
| TPOT Session (ms/token) | Time per output token (session-based) |
| **Generation Time (ms)** | **LLM generation time from raw-stream** |
| **TPOT Raw (ms/token)** | **TPOT calculated from raw-stream timing** |
| **Events** | **Number of streaming events** |
| TTFT (ms) | **Time To First Token** (calculated from raw-stream + intercept) |
| Prefill (ms) | Prefill phase time (N/A) |
| Decode (ms) | Decode phase time (N/A) |

### Data Source

- **raw-stream.jsonl**: `~/.openclaw/logs/raw-stream.jsonl`
- Contains all streaming events with precise timestamps
- Matched to session messages by timestamp proximity (< 60s)
- **intercept data**: Request timestamps for TTFT calculation

### Timing Calculations (v0.10)

| Metric | Formula | Description |
|--------|---------|-------------|
| **TTFT** | `first_stream_ts - requestStartTime` | Time from API request sent to first streaming token |
| **Generation Time** | `current_ME_ts - previous_ME_ts` | Delta between consecutive message_end timestamps |
| **TPOT (Raw)** | `Generation Time / Output Tokens` | Time per output token (includes prefill) |

### Notes

- **TTFT**: Calculated from intercept `requestStartTime` and raw-stream first streaming event. Falls back to "-" if data unavailable.
- **Prefill/Decode**: Not available from OpenRouter non-streaming API (marked as "-")
- **Generation Time**: Includes prefill + decode time for the entire message generation.
- **TPOT (Raw)**: **Includes prefill phase** - this is total generation time per token, not pure decode time per token.
- **TPOT (Session)**: Derived from session-level timing data

## CSV Export

The `token-export` command generates CSV files:

1. **`*_token_stats_calls.csv`**: Per-API-call details with timing
2. **`*_token_stats.csv`**: Per-turn summary
3. **`*_token_stats_system_breakdown.csv`**: System prompt breakdown
4. **`*_system_prompt.txt`**: Full system prompt text
