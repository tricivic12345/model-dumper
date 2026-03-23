#!/bin/bash
# model-dumper: Dump and analyze OpenClaw model interactions

SESSIONS_DIR="${OPENCLAW_AGENT_DIR:-$HOME/.openclaw/agents/main}/sessions"
EXPORT_DIR="${OPENCLAW_WORKSPACE:-$HOME/.openclaw/workspace}/model_dumps"
INTERCEPT_DIR="${OPENCLAW_WORKSPACE:-$HOME/.openclaw/workspace}/model_intercept"
SESSIONS_JSON="${SESSIONS_DIR}/sessions.json"

mkdir -p "$EXPORT_DIR"

get_latest_session() {
    local latest_file=$(ls -t "${SESSIONS_DIR}"/*.jsonl 2>/dev/null | grep -v ".reset." | grep -v ".deleted." | head -1)
    if [ -z "$latest_file" ]; then
        echo ""
    else
        basename "$latest_file" .jsonl
    fi
}

count_rounds() {
    local session_id="$1"
    local session_file="${SESSIONS_DIR}/${session_id}.jsonl"
    
    if [ ! -f "$session_file" ]; then
        echo "Session not found: $session_id"
        return 1
    fi
    
    python3 - "$session_file" << 'PYEOF'
import json
import sys

session_file = sys.argv[1]
user_msgs = 0
assistant_msgs = 0
tool_results = 0

with open(session_file, 'r') as f:
    for line in f:
        try:
            data = json.loads(line.strip())
            if data.get('type') == 'message':
                msg = data.get('message', {})
                role = msg.get('role', '')
                if role == 'user':
                    user_msgs += 1
                elif role == 'assistant':
                    assistant_msgs += 1
                elif role == 'toolResult':
                    tool_results += 1
        except:
            pass

print(f"User Messages: {user_msgs}")
print(f"Assistant Responses: {assistant_msgs}")
print(f"Tool Results: {tool_results}")
print(f"Total Interaction Rounds: {user_msgs}")
PYEOF
}

dump_prompts() {
    local session_id="$1"
    local session_file="${SESSIONS_DIR}/${session_id}.jsonl"
    
    if [ ! -f "$session_file" ]; then
        echo "Session not found: $session_id"
        return 1
    fi
    
    echo "===== PROMPTS SENT TO MODEL ====="
    echo ""
    
    python3 - "$session_file" << 'PYEOF'
import json
import sys

session_file = sys.argv[1]
count = 0

def extract_text_content(content):
    if isinstance(content, list):
        texts = []
        for item in content:
            if isinstance(item, dict) and item.get('type') == 'text':
                texts.append(item.get('text', ''))
        return '\n'.join(texts)
    return str(content) if content else ''

with open(session_file, 'r') as f:
    for line in f:
        try:
            data = json.loads(line.strip())
            if data.get('type') == 'message':
                msg = data.get('message', {})
                if msg.get('role') == 'user':
                    count += 1
                    content = msg.get('content', '')
                    text = extract_text_content(content)
                    print(f"--- Prompt #{count} ---")
                    print(text[:2000] if text else '(empty)')
                    print()
        except:
            pass

if count == 0:
    print("No user prompts found in this session.")
PYEOF
}

dump_outputs() {
    local session_id="$1"
    local session_file="${SESSIONS_DIR}/${session_id}.jsonl"
    
    if [ ! -f "$session_file" ]; then
        echo "Session not found: $session_id"
        return 1
    fi
    
    echo "===== MODEL OUTPUTS ====="
    echo ""
    
    python3 - "$session_file" << 'PYEOF'
import json
import sys

session_file = sys.argv[1]
count = 0

def extract_text_content(content):
    if isinstance(content, list):
        texts = []
        for item in content:
            if isinstance(item, dict) and item.get('type') == 'text':
                texts.append(item.get('text', ''))
        return '\n'.join(texts)
    return str(content) if content else ''

with open(session_file, 'r') as f:
    for line in f:
        try:
            data = json.loads(line.strip())
            if data.get('type') == 'message':
                msg = data.get('message', {})
                if msg.get('role') == 'assistant':
                    count += 1
                    
                    thinking = msg.get('thinking', '')
                    content = msg.get('content', '')
                    text = extract_text_content(content)
                    tool_calls = msg.get('toolCalls', [])
                    
                    print(f"--- Output #{count} ---")
                    
                    if thinking:
                        print("Thinking:")
                        print(thinking[:1000] if thinking else '(empty)')
                        print()
                    
                    if text:
                        print("Response:")
                        print(text[:2000] if text else '(empty)')
                        print()
                    
                    if tool_calls:
                        tool_names = [tc.get('name', 'unknown') for tc in tool_calls]
                        print(f"Tools Called: {', '.join(tool_names)}")
                        print()
                    
                    print()
        except Exception as e:
            pass

if count == 0:
    print("No model outputs found in this session.")
PYEOF
}

analyze_session() {
    local session_id="$1"
    local session_file="${SESSIONS_DIR}/${session_id}.jsonl"
    
    if [ ! -f "$session_file" ]; then
        echo "Session not found: $session_id"
        return 1
    fi
    
    python3 - "$session_id" "$session_file" << 'PYEOF'
import json
import sys
from datetime import datetime

session_id = sys.argv[1]
session_file = sys.argv[2]

user_msgs = 0
assistant_msgs = 0
tool_results = 0
first_ts = None
last_ts = None

total_input_tokens = 0
total_output_tokens = 0

with open(session_file, 'r') as f:
    for line in f:
        try:
            data = json.loads(line.strip())
            ts = data.get('timestamp', '')
            
            if data.get('type') == 'message':
                msg = data.get('message', {})
                role = msg.get('role', '')
                if role == 'user':
                    user_msgs += 1
                    if not first_ts: first_ts = ts
                    last_ts = ts
                elif role == 'assistant':
                    assistant_msgs += 1
                    usage = msg.get('usage', {})
                    if usage:
                        total_input_tokens += usage.get('input', 0)
                        total_output_tokens += usage.get('output', 0)
                    if not first_ts: first_ts = ts
                    last_ts = ts
                elif role == 'toolResult':
                    tool_results += 1
        except:
            pass

print(f"===== Session Analysis: {session_id} =====")
print()
print("Interaction Statistics:")
print(f"  User Messages (Prompts): {user_msgs}")
print(f"  Assistant Responses: {assistant_msgs}")
print(f"  Tool Results: {tool_results}")
print(f"  Total Interaction Rounds: {user_msgs}")
print()

if total_input_tokens > 0 or total_output_tokens > 0:
    print("Token Usage (from session data):")
    print(f"  Input Tokens: {total_input_tokens:,}")
    print(f"  Output Tokens: {total_output_tokens:,}")
    print(f"  Total Tokens: {total_input_tokens + total_output_tokens:,}")
    print()

if first_ts and last_ts:
    try:
        start_dt = datetime.fromisoformat(first_ts.replace('Z', '+00:00'))
        end_dt = datetime.fromisoformat(last_ts.replace('Z', '+00:00'))
        duration = (end_dt - start_dt).total_seconds()
        print("Session Duration:")
        print(f"  Start: {start_dt}")
        print(f"  End: {end_dt}")
        print(f"  Duration: {int(duration)}s")
        print()
    except:
        pass
PYEOF
}

export_jsonl() {
    local session_id="$1"
    local output_file="$2"
    local session_file="${SESSIONS_DIR}/${session_id}.jsonl"
    
    if [ ! -f "$session_file" ]; then
        echo "Session not found: $session_id"
        return 1
    fi
    
    python3 - "$session_id" "$session_file" "$output_file" << 'PYEOF'
import json
import sys
import os
import glob
from datetime import datetime

session_id = sys.argv[1]
session_file = sys.argv[2]
output_file = sys.argv[3] if len(sys.argv) > 3 else None

workspace = os.path.expanduser("~/.openclaw/workspace")
intercept_dir = os.path.join(workspace, "model_intercept")

# Try to read system prompt from intercept data
system_prompt = ""
intercept_messages = {}

if os.path.isdir(intercept_dir):
    pattern = os.path.join(intercept_dir, f"{session_id}_*.jsonl")
    intercept_files = sorted(glob.glob(pattern), reverse=True)
    for ifile in intercept_files:
        try:
            with open(ifile, 'r') as f:
                for line in f:
                    rec = json.loads(line.strip())
                    if rec.get('systemPrompt'):
                        system_prompt = rec['systemPrompt']
                        if rec.get('messages'):
                            intercept_messages = rec
                        break
            if system_prompt:
                break
        except:
            pass

def extract_text_content(content):
    if isinstance(content, list):
        texts = []
        for item in content:
            if isinstance(item, dict):
                if item.get('type') == 'text':
                    texts.append(item.get('text', ''))
                elif item.get('type') == 'tool_use':
                    texts.append(f"[Tool: {item.get('name', 'unknown')}]")
                elif item.get('type') == 'tool_result':
                    texts.append(f"[Tool Result: {item.get('tool_use_id', '')}]")
        return '\n'.join(texts)
    return str(content) if content else ''

def extract_full_content(content):
    if not isinstance(content, list):
        return [{"type": "text", "text": str(content) if content else ""}]
    
    result = []
    for item in content:
        if isinstance(item, dict):
            item_type = item.get('type', 'unknown')
            if item_type == 'text':
                result.append({"type": "text", "text": item.get('text', '')})
            elif item_type == 'thinking':
                result.append({"type": "thinking", "thinking": item.get('thinking', '')})
            elif item_type == 'toolCall':
                result.append({
                    "type": "toolCall",
                    "id": item.get('id', ''),
                    "name": item.get('name', ''),
                    "arguments": item.get('arguments', {})
                })
        elif isinstance(item, str):
            result.append({"type": "text", "text": item})
    return result

messages = []
with open(session_file, 'r') as f:
    for line in f:
        try:
            data = json.loads(line.strip())
            if data.get('type') == 'message':
                msg = data.get('message', {})
                msg['_raw_timestamp'] = data.get('timestamp', '')
                messages.append(msg)
        except:
            pass

entries = []
current_input_messages = []  # Structured input messages with roles
current_tool_results = []

for i, msg in enumerate(messages):
    role = msg.get('role', '')
    timestamp = msg.get('_raw_timestamp', '')
    
    ts_epoch = 0
    if timestamp:
        try:
            dt = datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
            ts_epoch = int(dt.timestamp() * 1000)
        except:
            pass
    
    if role == 'user':
        # New user message - add system prompt first if not already added
        if not current_input_messages and system_prompt:
            current_input_messages.append({
                "role": "system",
                "content": system_prompt
            })
        
        content = msg.get('content', [])
        text = extract_text_content(content)
        current_input_messages.append({
            "role": "user",
            "content": text,
            "raw_content": content
        })
        current_tool_results = []
        
    elif role == 'toolResult':
        content = msg.get('content', [])
        tool_result_text = extract_text_content(content)
        
        tool_result_obj = {
            "role": "tool",
            "toolCallId": msg.get('toolCallId', ''),
            "toolName": msg.get('toolName', ''),
            "content": tool_result_text,
            "raw_content": content
        }
        current_tool_results.append(tool_result_obj)
        current_input_messages.append(tool_result_obj)
        
    elif role == 'assistant':
        if current_input_messages:
            content = msg.get('content', [])
            full_content = extract_full_content(content)
            
            thinking = msg.get('thinking', '')
            for item in full_content:
                if item.get('type') == 'thinking' and not thinking:
                    thinking = item.get('thinking', '')
                    break
            
            output_text = extract_text_content(content)
            if thinking:
                output_text = f"<thinking>{thinking}</thinking>\n{output_text}"
            
            tool_calls = msg.get('toolCalls', [])
            if not tool_calls:
                for item in full_content:
                    if item.get('type') == 'toolCall':
                        tool_calls.append(item)
            
            tool_calls_output = []
            for tc in tool_calls:
                if isinstance(tc, dict):
                    tool_calls_output.append({
                        "name": tc.get('name', 'unknown'),
                        "id": tc.get('id', ''),
                        "arguments": tc.get('arguments', {})
                    })
            
            usage = msg.get('usage', {})
            
            # Calculate system prompt tokens (estimate)
            system_tokens_est = round(len(system_prompt) / 3.5) if system_prompt else 0
            input_tokens = usage.get('input', 0)
            
            entry = {
                "timestamp": ts_epoch,
                "call_num": len(entries) + 1,
                "input": {
                    "messages": current_input_messages,
                    "system_prompt": system_prompt if system_prompt else None,
                    "system_tokens_est": system_tokens_est,
                    "message_count": len(current_input_messages)
                },
                "output": {
                    "text": output_text.strip(),
                    "thinking": thinking,
                    "toolCalls": tool_calls_output,
                    "raw_content": full_content
                },
                "toolResults": current_tool_results,
                "token_usage": {
                    "input": input_tokens,
                    "output": usage.get('output', 0),
                    "total": usage.get('totalTokens', 0),
                    "cache_read": usage.get('cacheRead', 0),
                    "cache_write": usage.get('cacheWrite', 0)
                } if usage else None,
                "model": msg.get('model', None),
                "provider": msg.get('provider', None),
                "stop_reason": msg.get('stopReason', None)
            }
            entries.append(entry)
            
            # Add assistant message to input for next round
            current_input_messages.append({
                "role": "assistant",
                "content": extract_text_content(content),
                "thinking": thinking,
                "toolCalls": tool_calls_output
            })

if output_file:
    with open(output_file, 'w') as f:
        for entry in entries:
            f.write(json.dumps(entry, ensure_ascii=False) + '\n')
    print(f"Exported {len(entries)} entries to {output_file}")
else:
    for entry in entries:
        print(json.dumps(entry, ensure_ascii=False))
PYEOF
}

# Export simple JSONL format: {"timestamp": {...}, "input": "...", "output": "..."}
export_simple_jsonl() {
    local session_id="${1:-$(get_latest_session)}"
    local output_file="${2:-${EXPORT_DIR}/${session_id}_simple.jsonl}"
    local session_file="${SESSIONS_DIR}/${session_id}.jsonl"
    
    if [ ! -f "$session_file" ]; then
        echo "Session not found: $session_id"
        return 1
    fi
    
    python3 - "$session_id" "$session_file" "$output_file" << 'PYEOF'
import json
import sys
import os
import glob
import re
import difflib
from datetime import datetime

session_id = sys.argv[1]
session_file = sys.argv[2]
output_file = sys.argv[3] if len(sys.argv) > 3 else None

workspace = os.path.expanduser("~/.openclaw/workspace")
intercept_dir = os.path.join(workspace, "model_intercept")

def normalize_text(text):
    """Normalize text for comparison"""
    if not text:
        return ""
    # Remove extra whitespace, normalize newlines
    text = re.sub(r'\s+', ' ', text)
    return text.strip()

def get_content_signature(content):
    """Extract a signature from content for matching"""
    if isinstance(content, list):
        texts = []
        for item in content:
            if isinstance(item, dict):
                if item.get('type') == 'text':
                    texts.append(item.get('text', ''))
                elif item.get('type') == 'toolResult':
                    texts.append(str(item.get('content', '')))
        return normalize_text(' '.join(texts))
    return normalize_text(str(content) if content else '')

def match_intercept_to_session(intercept_entries, session_messages, threshold=0.8):
    """
    Match Intercept entries to Session messages using content similarity.
    Returns a dict: {intercept_index: session_assistant_index}
    """
    matches = {}
    
    for i, intercept_rec in enumerate(intercept_entries):
        # Get the current user prompt from intercept
        intercept_prompt = intercept_rec.get('prompt', '')
        intercept_prompt_sig = normalize_text(intercept_prompt)
        
        if not intercept_prompt_sig:
            continue
        
        best_match_idx = -1
        best_ratio = 0
        
        # Search for matching user message in session
        for j, msg in enumerate(session_messages):
            if msg.get('role') != 'user':
                continue
            
            session_content_sig = get_content_signature(msg.get('content', []))
            
            if not session_content_sig:
                continue
            
            # Calculate similarity
            ratio = difflib.SequenceMatcher(
                None, 
                intercept_prompt_sig, 
                session_content_sig
            ).ratio()
            
            if ratio > best_ratio and ratio >= threshold:
                best_ratio = ratio
                best_match_idx = j
        
        if best_match_idx >= 0:
            # Find the next assistant message after the matched user message
            for k in range(best_match_idx + 1, len(session_messages)):
                if session_messages[k].get('role') == 'assistant':
                    matches[i] = k
                    break
    
    return matches

def extract_text_content(content):
    """Extract text content from various formats"""
    if isinstance(content, list):
        texts = []
        for item in content:
            if isinstance(item, dict):
                if item.get('type') == 'text':
                    texts.append(item.get('text', ''))
                elif item.get('type') == 'toolResult':
                    texts.append(item.get('content', ''))
        return '\n'.join(texts)
    return str(content) if content else ''

def extract_thinking(content):
    """Extract thinking from content"""
    if isinstance(content, list):
        for item in content:
            if isinstance(item, dict) and item.get('type') == 'thinking':
                return item.get('thinking', '')
    return ''

def extract_tool_calls(msg):
    """Extract tool calls from message"""
    tool_calls = msg.get('toolCalls', [])
    if not tool_calls and isinstance(msg.get('content'), list):
        for item in msg.get('content', []):
            if isinstance(item, dict) and item.get('type') == 'toolCall':
                tool_calls.append(item)
    return tool_calls

def build_input_from_intercept(intercept_rec):
    """Build complete input from intercept record"""
    parts = []
    
    # Add system prompt
    system_prompt = intercept_rec.get('systemPrompt', '')
    if system_prompt:
        parts.append(f"[SYSTEM]\n{system_prompt}")
    
    # Add history messages (the COMPLETE conversation history)
    history = intercept_rec.get('historyMessages', [])
    for hmsg in history:
        role = hmsg.get('role', '')
        content = hmsg.get('content', '')
        text = extract_text_content(content)
        
        if role == 'user':
            parts.append(f"[USER]\n{text}")
        elif role == 'assistant':
            thinking = extract_thinking(content)
            tool_calls = extract_tool_calls(hmsg)
            
            assistant_parts = []
            if thinking:
                assistant_parts.append(f"[THINKING]\n{thinking}")
            if tool_calls:
                tc_names = [tc.get('name', 'unknown') for tc in tool_calls if isinstance(tc, dict)]
                assistant_parts.append(f"[TOOL_CALLS]\n{', '.join(tc_names)}")
            if text:
                assistant_parts.append(f"[TEXT]\n{text}")
            
            if assistant_parts:
                parts.append(f"[ASSISTANT]\n" + "\n".join(assistant_parts))
        elif role == 'tool':
            tool_name = hmsg.get('name', hmsg.get('toolName', 'unknown'))
            parts.append(f"[TOOL_RESULT: {tool_name}]\n{text}")
    
    # Add current prompt
    current_prompt = intercept_rec.get('prompt', '')
    if current_prompt:
        parts.append(f"[USER]\n{current_prompt}")
    
    return "\n\n".join(parts)

# Read session file for outputs and token counts
session_messages = []
with open(session_file, 'r') as f:
    for line in f:
        try:
            data = json.loads(line.strip())
            if data.get('type') == 'message':
                msg = data.get('message', {})
                msg['_raw_timestamp'] = data.get('timestamp', '')
                session_messages.append(msg)
        except:
            pass

# Read intercept data (has COMPLETE input sent to LLM)
# Only read the MOST RECENT intercept file (latest date)
intercept_entries = []
if os.path.isdir(intercept_dir):
    # Find intercept files matching session_id with date suffix
    pattern = os.path.join(intercept_dir, f"{session_id}_*.jsonl")
    intercept_files = sorted(glob.glob(pattern), reverse=True)
    
    if intercept_files:
        # Only read the most recent file
        latest_file = intercept_files[0]
        try:
            with open(latest_file, 'r') as f:
                for line in f:
                    rec = json.loads(line.strip())
                    # Only add entries with valid systemPrompt
                    if rec.get('systemPrompt'):
                        intercept_entries.append(rec)
        except Exception as e:
            print(f"Warning: Could not read intercept file: {e}")

print(f"Loaded {len(intercept_entries)} intercept entries from latest file")
print(f"Loaded {len(session_messages)} session messages")

# Match intercept entries to session messages using content similarity
print("Matching intercept entries to session messages...")
matches = match_intercept_to_session(intercept_entries, session_messages, threshold=0.7)
print(f"Matched {len(matches)} intercept entries to session messages")

# Build entries using INTERCEPT data for input, SESSION for output
entries = []

for i, intercept_rec in enumerate(intercept_entries):
    # Get timestamp
    timestamp = intercept_rec.get('timestamp', '')
    ts_epoch = 0
    ts_human = ""
    if timestamp:
        try:
            dt = datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
            ts_epoch = int(dt.timestamp() * 1000)
            ts_human = dt.isoformat()
        except:
            pass
    
    # Build COMPLETE input from intercept
    complete_input = build_input_from_intercept(intercept_rec)
    input_len = len(complete_input)
    
    # Get token counts from matched session message
    input_tokens = 0
    output_tokens = 0
    stop_reason = ""
    output_text = ""
    thinking = ""
    tool_calls = []
    
    if i in matches:
        # Use matched session assistant message for token counts and output
        session_idx = matches[i]
        session_msg = session_messages[session_idx]
        
        usage = session_msg.get('usage', {})
        input_tokens = usage.get('input', 0)
        output_tokens = usage.get('output', 0)
        stop_reason = session_msg.get('stopReason', '')
        
        # Get output content from session
        output_text = extract_text_content(session_msg.get('content', []))
        thinking = extract_thinking(session_msg.get('content', []))
        tool_calls = extract_tool_calls(session_msg)
    else:
        # Fallback: try intercept data
        messages = intercept_rec.get('messages', [])
        for msg in messages:
            if msg.get('role') == 'assistant':
                usage = msg.get('usage', {})
                input_tokens = usage.get('input', input_tokens)
                output_tokens = usage.get('output', output_tokens)
                stop_reason = msg.get('stopReason', '')
                output_text = extract_text_content(msg.get('content', []))
                thinking = extract_thinking(msg.get('content', []))
                tool_calls = extract_tool_calls(msg)
                break
    
    # Build output parts
    output_parts = []
    if thinking:
        output_parts.append(f"[THINKING]\n{thinking}")
    if tool_calls:
        tc_names = [tc.get('name', 'unknown') for tc in tool_calls if isinstance(tc, dict)]
        output_parts.append(f"[TOOL_CALLS]\n{', '.join(tc_names)}")
    if output_text:
        output_parts.append(f"[TEXT]\n{output_text}")
    
    entry = {
        "timestamp": ts_epoch,
        "ts_human": ts_human,
        "input": complete_input,
        "output": "\n\n".join(output_parts),
        "input_tokens": input_tokens,
        "output_tokens": output_tokens,
        "stop_reason": stop_reason,
        "model": intercept_rec.get('model', ''),
        "_input_chars": input_len,  # Debug info
        "_matched": i in matches,  # Debug info
    }
    entries.append(entry)

if output_file:
    with open(output_file, 'w') as f:
        for entry in entries:
            # Remove debug field before saving
            if '_input_chars' in entry:
                del entry['_input_chars']
            f.write(json.dumps(entry, ensure_ascii=False) + '\n')
    print(f"Exported {len(entries)} entries to {output_file}")
else:
    for entry in entries:
        if '_input_chars' in entry:
            del entry['_input_chars']
        print(json.dumps(entry, ensure_ascii=False))
PYEOF
}

dump_session() {
    local session_id="$1"
    local format="${2:-text}"
    local session_file="${SESSIONS_DIR}/${session_id}.jsonl"
    
    if [ ! -f "$session_file" ]; then
        echo "Session not found: $session_id"
        return 1
    fi
    
    if [ "$format" = "json" ]; then
        echo "["
        local first=true
        while IFS= read -r line; do
            if [ "$first" = true ]; then
                first=false
            else
                echo ","
            fi
            echo "$line" | sed 's/,$//'
        done < "$session_file"
        echo "]"
    else
        analyze_session "$session_id"
        echo ""
        dump_prompts "$session_id"
        echo ""
        dump_outputs "$session_id"
    fi
}

intercepted_calls() {
    local session_id="${1:-main}"
    local date="${2:-$(date +%Y-%m-%d)}"
    local intercept_file="${INTERCEPT_DIR}/${session_id}_${date}.jsonl"
    
    if [ ! -f "$intercept_file" ]; then
        echo "No intercepted data found for session: $session_id on $date"
        echo "Files available:"
        ls -la "$INTERCEPT_DIR" 2>/dev/null || echo "Directory doesn't exist"
        return 1
    fi
    
    echo "===== INTERCEPTED LLM CALLS ====="
    echo "Session: $session_id"
    echo "Date: $date"
    echo ""
    
    python3 - "$intercept_file" << 'PYEOF'
import json
import sys

intercept_file = sys.argv[1]
count = 0

with open(intercept_file, 'r') as f:
    for line in f:
        try:
            data = json.loads(line.strip())
            count += 1
            print(f"--- Call #{count} ---")
            print(f"Timestamp: {data.get('timestamp', 'unknown')}")
            print(f"Model: {data.get('model', 'unknown')}")
            print(f"Provider: {data.get('provider', 'unknown')}")
            print(f"Messages: {len(data.get('messages', []))}")
            
            messages = data.get('messages', [])
            for i, msg in enumerate(messages):
                role = msg.get('role', 'unknown')
                content = msg.get('content', '')
                if isinstance(content, list):
                    content = str(content)[:200]
                print(f"  [{i+1}] {role}: {content[:100]}...")
            print()
        except Exception as e:
            print(f"Error: {e}")

print(f"Total calls: {count}")
PYEOF
}

get_system_prompt() {
    local session_key="${1:-agent:main:main}"
    local workspace="${OPENCLAW_WORKSPACE:-$HOME/.openclaw/workspace}"
    
    if [ ! -f "$SESSIONS_JSON" ]; then
        echo "Sessions JSON not found: $SESSIONS_JSON"
        return 1
    fi
    
    python3 - "$SESSIONS_JSON" "$session_key" "$workspace" << 'PYEOF'
import json
import sys
import os

sessions_json = sys.argv[1]
session_key = sys.argv[2] if len(sys.argv) > 2 else "agent:main:main"
workspace = sys.argv[3] if len(sys.argv) > 3 else os.path.expanduser("~/.openclaw/workspace")

print("=" * 60)
print("RECONSTRUCTED SYSTEM PROMPT")
print("=" * 60)
print()

try:
    with open(sessions_json, 'r') as f:
        data = json.load(f)
    
    if session_key in data:
        session_data = data[session_key]
        
        print("=== 1. SKILLS SNAPSHOT ===")
        if 'skillsSnapshot' in session_data:
            prompt = session_data['skillsSnapshot'].get('prompt', '')
            print(prompt)
        print()
        
    print("=== 2. WORKSPACE CONTEXT FILES ===")
    print()
    
    context_files = ['SOUL.md', 'USER.md', 'AGENTS.md', 'MEMORY.md', 'TOOLS.md', 'HEARTBEAT.md']
    
    for filename in context_files:
        filepath = os.path.join(workspace, filename)
        if os.path.exists(filepath):
            print(f"--- {filename} ---")
            with open(filepath, 'r') as f:
                content = f.read()
                print(content[:2000] if len(content) > 2000 else content)
            print()
            
    print("=== 3. RECENT MEMORY ===")
    print()
    memory_dir = os.path.join(workspace, 'memory')
    if os.path.exists(memory_dir):
        import glob
        memory_files = sorted(glob.glob(os.path.join(memory_dir, '*.md')))[-3:]
        for mf in memory_files:
            print(f"--- {os.path.basename(mf)} ---")
            with open(mf, 'r') as f:
                content = f.read()
                print(content[:1000] if len(content) > 1000 else content)
            print()
            
except Exception as e:
    print(f"Error: {e}")
    import traceback
    traceback.print_exc()
PYEOF
}

export_full() {
    local session_id="${1:-main}"
    local output_file="${2:-${EXPORT_DIR}/${session_id}_full_$(date +%Y%m%d_%H%M%S).jsonl}"
    local workspace="${OPENCLAW_WORKSPACE:-$HOME/.openclaw/workspace}"
    
    mkdir -p "$(dirname "$output_file")"
    
    python3 - "$INTERCEPT_DIR" "$session_id" "$SESSIONS_JSON" "$workspace" "$output_file" << 'PYEOF'
import json
import sys
import os
from datetime import datetime

intercept_dir = sys.argv[1]
session_id = sys.argv[2]
sessions_json = sys.argv[3]
workspace = sys.argv[4]
output_file = sys.argv[5] if len(sys.argv) > 5 else None

system_prompt_parts = {}

try:
    with open(sessions_json, 'r') as f:
        data = json.load(f)
    
    for key in data.keys():
        if 'skillsSnapshot' in data[key]:
            system_prompt_parts['skills'] = data[key]['skillsSnapshot'].get('prompt', '')
            break
except:
    pass

context_files = ['SOUL.md', 'USER.md', 'AGENTS.md', 'MEMORY.md']
for fname in context_files:
    fpath = os.path.join(workspace, fname)
    if os.path.exists(fpath):
        with open(fpath, 'r') as f:
            system_prompt_parts[fname.replace('.md', '')] = f.read()[:5000]

entries = []
today = datetime.now().strftime('%Y-%m-%d')
intercept_file = os.path.join(intercept_dir, f"{session_id}_{today}.jsonl")

if os.path.exists(intercept_file):
    try:
        with open(intercept_file, 'r') as f:
            for line in f:
                try:
                    data = json.loads(line.strip())
                    entry = {
                        "timestamp": data.get('timestamp', 0),
                        "input": json.dumps({
                            "systemPrompt": system_prompt_parts,
                            "prompt": data.get('prompt', ''),
                            "messages": data.get('messages', [])
                        }, ensure_ascii=False),
                        "output": "",
                        "token_usage": {
                            "input": data.get('inputTokens', 0),
                            "output": data.get('outputTokens', 0),
                            "total": (data.get('inputTokens', 0) + data.get('outputTokens', 0))
                        } if data.get('inputTokens') or data.get('outputTokens') else None,
                        "model": data.get('model', ''),
                        "provider": data.get('provider', ''),
                        "source": "intercept"
                    }
                    entries.append(entry)
                except:
                    pass
    except FileNotFoundError:
        pass

with open(output_file, 'w') as f:
    for entry in entries:
        f.write(json.dumps(entry, ensure_ascii=False) + '\n')

print(f"Exported {len(entries)} entries to {output_file}")
print(f"System prompt parts included: {list(system_prompt_parts.keys())}")
PYEOF
}

# Enhanced token statistics with per-call and per-turn breakdown
token_stats() {
    local session_id="${1:-$(get_latest_session)}"
    local session_file="${SESSIONS_DIR}/${session_id}.jsonl"
    local output_file="${2:-${EXPORT_DIR}/${session_id}_token_stats.txt}"
    
    if [ ! -f "$session_file" ]; then
        echo "Session not found: $session_id"
        return 1
    fi
    
    python3 - "$session_id" "$session_file" "$output_file" << 'PYEOF'
import json
import sys
import os
import re
import glob
from datetime import datetime

session_id = sys.argv[1]
session_file = sys.argv[2]
output_file = sys.argv[3] if len(sys.argv) > 3 else None

workspace = os.path.expanduser("~/.openclaw/workspace")
intercept_dir = os.path.join(workspace, "model_intercept")

# Read system prompt from intercept data
system_prompt = ""
if os.path.isdir(intercept_dir):
    pattern = os.path.join(intercept_dir, f"{session_id}_*.jsonl")
    intercept_files = sorted(glob.glob(pattern), reverse=True)
    for ifile in intercept_files:
        try:
            with open(ifile, 'r') as f:
                for line in f:
                    rec = json.loads(line.strip())
                    if rec.get('systemPrompt'):
                        system_prompt = rec['systemPrompt']
                        break
            if system_prompt:
                break
        except:
            pass

# Parse system prompt sections
def parse_system_sections(text):
    if not text:
        return []
    sections = []
    pattern = re.compile(r'^##+ (.+)$', re.MULTILINE)
    matches = list(pattern.finditer(text))
    for i, m in enumerate(matches):
        name = m.group(1).strip()
        start = m.start()
        end = matches[i+1].start() if i + 1 < len(matches) else len(text)
        sections.append({'name': name, 'start': start, 'end': end, 'chars': end - start})
    return sections

# Categorize sections
def categorize_section(name):
    name_lower = name.lower()
    if 'skill' in name_lower or 'vetting' in name_lower or 'security' in name_lower:
        return 'Skills'
    if name.startswith('Tooling'):
        return 'Tooling'
    if 'tool' in name_lower and '###' in name:
        return 'Tool JSON'
    if 'heartbeat' in name_lower or 'cron' in name_lower:
        return 'Heartbeats'
    if 'memory' in name_lower or '记忆' in name_lower:
        return 'Memory'
    if 'group chat' in name_lower or 'speak' in name_lower:
        return 'Group Chats'
    if 'workflow' in name_lower or 'usage' in name_lower or 'output' in name_lower:
        return 'Workflow'
    if 'task tracing' in name_lower:
        return 'Task Tracing'
    if 'search' in name_lower or 'content' in name_lower:
        return 'Search'
    if 'core truth' in name_lower or 'boundaries' in name_lower or 'identity' in name_lower:
        return 'Core'
    if '.md' in name or 'workspace' in name_lower:
        return 'Workspace'
    if any(x in name_lower for x in ['runtime', 'silent', 'safety', 'startup', 'first run', 'red line', 'external', 'make it']):
        return 'Meta'
    return 'Other'

system_sections = parse_system_sections(system_prompt)
for s in system_sections:
    s['tokens'] = round(s['chars'] / 2.6)
    s['category'] = categorize_section(s['name'])

# Read session data - track ALL API calls with timestamps
api_calls = []
current_user = None
user_turn_count = 0
turn_start_time = None
turn_end_time = None

with open(session_file, 'r') as f:
    for line in f:
        try:
            data = json.loads(line.strip())
            if data.get('type') == 'message':
                msg = data.get('message', {})
                role = msg.get('role', '')
                timestamp = data.get('timestamp', '')
                
                if role == 'user':
                    # Start new turn
                    if user_turn_count > 0:
                        # Close previous turn
                        pass
                    user_turn_count += 1
                    turn_start_time = timestamp
                    content = msg.get('content', [])
                    if isinstance(content, list):
                        texts = [item.get('text', '') for item in content if item.get('type') == 'text']
                        current_user = '\n'.join(texts)
                    else:
                        current_user = str(content)
                    current_user = current_user[:80].replace('\n', ' ')
                    turn_end_time = timestamp
                        
                elif role == 'assistant':
                    usage = msg.get('usage', {})
                    input_tokens = usage.get('input', 0)
                    output_tokens = usage.get('output', 0)
                    
                    if input_tokens > 0:
                        turn_end_time = timestamp
                        api_calls.append({
                            'user_turn': user_turn_count,
                            'user_prompt': current_user,
                            'input_tokens': input_tokens,
                            'output_tokens': output_tokens,
                            'cache_read': usage.get('cacheRead', 0),
                            'cache_write': usage.get('cacheWrite', 0),
                            'timestamp': timestamp,
                            'tool_calls': len(msg.get('toolCalls', [])),
                            'stop_reason': msg.get('stopReason', '')
                        })
                            
        except Exception as e:
            pass

# Aggregate by user turn
turns = {}
for call in api_calls:
    turn = call['user_turn']
    if turn not in turns:
        turns[turn] = {
            'input_tokens': 0,
            'output_tokens': 0,
            'cache_read': 0,
            'cache_write': 0,
            'api_calls': 0,
            'tool_calls': 0,
            'user_prompt': call['user_prompt'],
            'first_input': call['input_tokens'],
            'last_input': call['input_tokens'],
            'first_timestamp': call['timestamp'],
            'last_timestamp': call['timestamp'],
            'calls': []
        }
    
    turns[turn]['input_tokens'] += call['input_tokens']
    turns[turn]['output_tokens'] += call['output_tokens']
    turns[turn]['cache_read'] += call['cache_read']
    turns[turn]['cache_write'] += call['cache_write']
    turns[turn]['api_calls'] += 1
    turns[turn]['tool_calls'] += call['tool_calls']
    turns[turn]['last_input'] = call['input_tokens']
    turns[turn]['last_timestamp'] = call['timestamp']
    turns[turn]['calls'].append(call)

# Calculate duration
def parse_timestamp(ts):
    try:
        return datetime.fromisoformat(ts.replace('Z', '+00:00'))
    except:
        return None

for turn in turns.values():
    start = parse_timestamp(turn['first_timestamp'])
    end = parse_timestamp(turn['last_timestamp'])
    if start and end:
        turn['duration_seconds'] = (end - start).total_seconds()
    else:
        turn['duration_seconds'] = 0

# Convert to list
rounds = []
for turn_num in sorted(turns.keys()):
    r = turns[turn_num]
    rounds.append({
        'turn': turn_num,
        'user_prompt': r['user_prompt'],
        'input_tokens': r['input_tokens'],
        'output_tokens': r['output_tokens'],
        'cache_read': r['cache_read'],
        'cache_write': r['cache_write'],
        'api_calls': r['api_calls'],
        'tool_calls': r['tool_calls'],
        'first_input': r['first_input'],
        'last_input': r['last_input'],
        'duration_seconds': r['duration_seconds'],
        'calls': r['calls']
    })

# Calculate totals
total_input = sum(r['input_tokens'] for r in rounds)
total_output = sum(r['output_tokens'] for r in rounds)
total_cache_read = sum(r['cache_read'] for r in rounds)
total_cache_write = sum(r['cache_write'] for r in rounds)
total_duration = sum(r['duration_seconds'] for r in rounds)

# Build output
output_lines = []
output_lines.append("=" * 140)
output_lines.append(f"TOKEN STATISTICS REPORT - Session: {session_id}")
output_lines.append(f"Generated: {datetime.now().isoformat()}")
output_lines.append("=" * 140)
output_lines.append("")

# Summary
output_lines.append("📊 SUMMARY")
output_lines.append("-" * 80)
output_lines.append(f"Total User Turns: {len(rounds)}")
output_lines.append(f"Total API Calls: {len(api_calls)}")
output_lines.append(f"Total Input Tokens: {total_input:,}")
output_lines.append(f"Total Output Tokens: {total_output:,}")
output_lines.append(f"Total Tokens: {total_input + total_output:,}")
output_lines.append(f"Cache Read Tokens: {total_cache_read:,}")
output_lines.append(f"Cache Write Tokens: {total_cache_write:,}")
if total_input > 0:
    output_lines.append(f"Cache Hit Rate: {(total_cache_read / total_input * 100):.1f}%")
else:
    output_lines.append(f"Cache Hit Rate: N/A")
if total_duration > 0:
    mins, secs = divmod(int(total_duration), 60)
    output_lines.append(f"Total Duration: {mins}m {secs}s ({total_duration:.1f}s)")
output_lines.append("")
if system_prompt:
    system_chars = len(system_prompt)
    system_tokens = round(system_chars / 2.6)
    output_lines.append("📋 SYSTEM PROMPT")
    output_lines.append("-" * 80)
    output_lines.append(f"System Prompt: {system_chars:,} chars, ~{system_tokens:,} tokens")
    output_lines.append(f"System Prompt Sections: {len(system_sections)}")
output_lines.append("")

# Per-API-Call table
output_lines.append("📈 PER-API-CALL TOKEN BREAKDOWN")
output_lines.append("-" * 140)
header = f"{'#':<4} {'Turn':<5} {'Input':>10} {'Output':>10} {'Cache':>10} {'Tools':>6} {'Stop Reason':<12} {'Duration':>8} {'User Prompt':<60}"
output_lines.append(header)
output_lines.append("-" * 140)

for i, call in enumerate(api_calls, 1):
    prompt = call['user_prompt'][:58] if call['user_prompt'] else '(startup)'
    stop = call.get('stop_reason', '')[:12]
    # Calculate call duration (approximate)
    call_dur = ""
    if i > 0 and i < len(api_calls):
        curr_ts = parse_timestamp(call['timestamp'])
        prev_ts = parse_timestamp(api_calls[i-2]['timestamp']) if i > 1 else None
        if curr_ts and prev_ts:
            dur = (curr_ts - prev_ts).total_seconds()
            call_dur = f"{dur:.1f}s"
    row = f"{i:<4} {call['user_turn']:<5} {call['input_tokens']:>10,} {call['output_tokens']:>10,} {call['cache_read']:>10,} {call['tool_calls']:>6} {stop:<12} {call_dur:<8} {prompt}"
    output_lines.append(row)

output_lines.append("-" * 140)
summary_row = f"{'TOTAL':<4} {'':<5} {total_input:>10,} {total_output:>10,} {total_cache_read:>10,} {sum(c['tool_calls'] for c in api_calls):>6} {'':<12} {'':<8} {'':<60}"
output_lines.append(summary_row)
output_lines.append("")

# Per-turn summary table with duration
output_lines.append("📊 PER-TURN SUMMARY")
output_lines.append("-" * 140)
header2 = f"{'Turn':<5} {'Calls':>6} {'Total In':>10} {'Total Out':>10} {'First In':>10} {'Last In':>10} {'Growth':>10} {'Duration':>10} {'User Prompt':<50}"
output_lines.append(header2)
output_lines.append("-" * 140)

for r in rounds:
    prompt = r['user_prompt'][:48] if r['user_prompt'] else '(startup)'
    growth = r['last_input'] - r['first_input']
    dur = f"{r['duration_seconds']:.0f}s" if r['duration_seconds'] > 0 else "-"
    row = f"{r['turn']:<5} {r['api_calls']:>6} {r['input_tokens']:>10,} {r['output_tokens']:>10,} {r['first_input']:>10,} {r['last_input']:>10,} {growth:>10,} {dur:>10} {prompt}"
    output_lines.append(row)

output_lines.append("-" * 140)
total_row = f"{'TOTAL':<5} {sum(r['api_calls'] for r in rounds):>6} {total_input:>10,} {total_output:>10,} {'':<10} {'':<10} {'':<10} {total_duration:>10.0f}s {'':<50}"
output_lines.append(total_row)
output_lines.append("")

# System prompt breakdown
if system_sections:
    output_lines.append("📋 SYSTEM PROMPT BREAKDOWN (by Section)")
    output_lines.append("-" * 140)
    header3 = f"{'Tokens':>8} {'Chars':>10} {'Category':<15} {'Section':<80}"
    output_lines.append(header3)
    output_lines.append("-" * 140)
    
    # Sort by tokens desc
    sorted_sections = sorted(system_sections, key=lambda x: x['tokens'], reverse=True)
    
    # Aggregate by category
    category_tokens = {}
    category_chars = {}
    for s in system_sections:
        cat = s['category']
        category_tokens[cat] = category_tokens.get(cat, 0) + s['tokens']
        category_chars[cat] = category_chars.get(cat, 0) + s['chars']
    
    # Show top 20 sections
    for s in sorted_sections[:25]:
        cat = s['category']
        name = s['name'][:78]
        row = f"{s['tokens']:>8,} {s['chars']:>10,} [{cat:<13}] {name}"
        output_lines.append(row)
    
    if len(sorted_sections) > 25:
        output_lines.append(f"... and {len(sorted_sections) - 25} more sections")
    
    output_lines.append("")
    output_lines.append("📋 SYSTEM PROMPT BREAKDOWN (by Category)")
    output_lines.append("-" * 80)
    
    sorted_cats = sorted(category_tokens.items(), key=lambda x: x[1], reverse=True)
    for cat, tokens in sorted_cats:
        chars = category_chars[cat]
        first_input = rounds[0]['first_input'] if rounds else 1
        pct = tokens / first_input * 100
        output_lines.append(f"{tokens:>8,} tokens ({pct:>5.1f}%) | {chars:>8,} chars | {cat}")
    
    if system_prompt:
        system_chars = len(system_prompt)
        system_tokens = round(system_chars / 2.6)
        first_input = rounds[0]['first_input'] if rounds else 1
        output_lines.append("-" * 80)
        output_lines.append(f"{system_tokens:>8,} tokens (100%) | {system_chars:>8,} chars | TOTAL")

# Print to console
for line in output_lines:
    print(line)

# Save to file if specified
if output_file:
    os.makedirs(os.path.dirname(output_file), exist_ok=True)
    with open(output_file, 'w') as f:
        for line in output_lines:
            f.write(line + '\n')
    print(f"\n✅ Report saved to: {output_file}")

PYEOF
}

# Token stats for all sessions
token_stats_all() {
    local output_file="${1:-${EXPORT_DIR}/all_sessions_token_stats.txt}"
    
    python3 - "$SESSIONS_DIR" "$output_file" << 'PYEOF'
import json
import sys
import os
from datetime import datetime

sessions_dir = sys.argv[1]
output_file = sys.argv[2] if len(sys.argv) > 2 else None

# Find all session files
session_files = []
for f in os.listdir(sessions_dir):
    if f.endswith('.jsonl') and '.reset.' not in f and '.deleted.' not in f:
        session_id = f.replace('.jsonl', '')
        session_files.append((session_id, os.path.join(sessions_dir, f)))

# Sort by modification time (newest first)
session_files.sort(key=lambda x: os.path.getmtime(x[1]), reverse=True)

output_lines = []
output_lines.append("=" * 120)
output_lines.append(f"ALL SESSIONS TOKEN STATISTICS REPORT")
output_lines.append(f"Generated: {datetime.now().isoformat()}")
output_lines.append("=" * 120)
output_lines.append("")

# Header
header = f"{'Session ID':<40} {'Rounds':>8} {'Input':>12} {'Output':>12} {'Total':>12} {'Cache':>12} {'Cache%':>8} {'Duration':>12}"
output_lines.append(header)
output_lines.append("-" * 120)

grand_total_input = 0
grand_total_output = 0
grand_total_cache = 0

for session_id, session_file in session_files[:20]:  # Limit to 20 sessions
    try:
        rounds = 0
        total_input = 0
        total_output = 0
        total_cache = 0
        first_ts = None
        last_ts = None
        
        with open(session_file, 'r') as f:
            for line in f:
                try:
                    data = json.loads(line.strip())
                    if data.get('type') == 'message':
                        msg = data.get('message', {})
                        role = msg.get('role', '')
                        
                        if role == 'user':
                            rounds += 1
                            ts = data.get('timestamp', '')
                            if not first_ts:
                                first_ts = ts
                            last_ts = ts
                            
                        elif role == 'assistant':
                            usage = msg.get('usage', {})
                            total_input += usage.get('input', 0)
                            total_output += usage.get('output', 0)
                            total_cache += usage.get('cacheRead', 0)
                except:
                    pass
        
        if total_input > 0 or total_output > 0:
            cache_pct = (total_cache / total_input * 100) if total_input > 0 else 0
            
            # Calculate duration
            duration = "N/A"
            if first_ts and last_ts:
                try:
                    start = datetime.fromisoformat(first_ts.replace('Z', '+00:00'))
                    end = datetime.fromisoformat(last_ts.replace('Z', '+00:00'))
                    secs = (end - start).total_seconds()
                    if secs > 0:
                        duration = f"{int(secs)}s"
                except:
                    pass
            
            row = f"{session_id[:40]:<40} {rounds:>8} {total_input:>12,} {total_output:>12,} {total_input+total_output:>12,} {total_cache:>12,} {cache_pct:>7.1f}% {duration:>12}"
            output_lines.append(row)
            
            grand_total_input += total_input
            grand_total_output += total_output
            grand_total_cache += total_cache
            
    except Exception as e:
        pass

# Summary
output_lines.append("-" * 120)
grand_total = grand_total_input + grand_total_output
cache_pct = (grand_total_cache / grand_total_input * 100) if grand_total_input > 0 else 0
summary = f"{'TOTAL':<40} {'':<8} {grand_total_input:>12,} {grand_total_output:>12,} {grand_total:>12,} {grand_total_cache:>12,} {cache_pct:>7.1f}% {'':<12}"
output_lines.append(summary)
output_lines.append("")

# Print
for line in output_lines:
    print(line)

# Save
if output_file:
    os.makedirs(os.path.dirname(output_file), exist_ok=True)
    with open(output_file, 'w') as f:
        for line in output_lines:
            f.write(line + '\n')
    print(f"\n✅ Report saved to: {output_file}")

PYEOF
}

# Export token stats to CSV (per-call detail)
token_export_csv() {
    local session_id="${1:-$(get_latest_session)}"
    local output_file="${2:-${EXPORT_DIR}/${session_id}_token_stats.csv}"
    local session_file="${SESSIONS_DIR}/${session_id}.jsonl"
    
    if [ ! -f "$session_file" ]; then
        echo "Session not found: $session_id"
        return 1
    fi
    
    python3 - "$session_id" "$session_file" "$output_file" << 'PYEOF'
import json
import sys
import os
import glob
import re
import csv
from datetime import datetime

session_id = sys.argv[1]
session_file = sys.argv[2]
output_file = sys.argv[3] if len(sys.argv) > 3 else None

if not output_file:
    output_file = session_file.replace('.jsonl', '_tokens.csv')

workspace = os.path.expanduser("~/.openclaw/workspace")
intercept_dir = os.path.join(workspace, "model_intercept")

# Read system prompt from intercept data
system_prompt = ""
if os.path.isdir(intercept_dir):
    pattern = os.path.join(intercept_dir, f"{session_id}_*.jsonl")
    intercept_files = sorted(glob.glob(pattern), reverse=True)
    for ifile in intercept_files:
        try:
            with open(ifile, 'r') as f:
                for line in f:
                    rec = json.loads(line.strip())
                    if rec.get('systemPrompt'):
                        system_prompt = rec['systemPrompt']
                        break
            if system_prompt:
                break
        except:
            pass

system_prompt_chars = len(system_prompt)
system_tokens_est = round(system_prompt_chars / 2.6) if system_prompt_chars > 0 else 0

# Parse system prompt sections
def parse_system_sections(text):
    if not text:
        return []
    sections = []
    pattern = re.compile(r'^##+ (.+)$', re.MULTILINE)
    matches = list(pattern.finditer(text))
    for i, m in enumerate(matches):
        name = m.group(1).strip()
        start = m.start()
        end = matches[i+1].start() if i + 1 < len(matches) else len(text)
        chars = end - start
        tokens = round(chars / 2.6)
        sections.append({'name': name, 'chars': chars, 'tokens': tokens})
    return sections

def categorize_section_detailed(name):
    name_lower = name.lower()
    # Workspace files (injected .md files)
    if '.md' in name and '/' in name:
        return 'Workspace_Files'
    if 'workspace files' in name_lower:
        return 'Workspace_Files'
    # Tool definitions
    if name.startswith('Tooling'):
        return 'Tool_List'
    if 'tool' in name_lower and '###' in name:
        return 'Tool_JSON'
    # Skills
    if 'skill' in name_lower or 'vetting' in name_lower or 'security' in name_lower:
        return 'Skills'
    # Memory/History
    if 'memory' in name_lower or '记忆' in name_lower or '对话' in name:
        return 'Memory_History'
    # Heartbeats
    if 'heartbeat' in name_lower or 'cron' in name_lower:
        return 'Heartbeats'
    # Group chats
    if 'group chat' in name_lower or 'speak' in name_lower:
        return 'Group_Chats'
    # Workflow
    if 'workflow' in name_lower or 'usage' in name_lower or 'output' in name_lower:
        return 'Workflow'
    # Task Tracing
    if 'task tracing' in name_lower:
        return 'Task_Tracing'
    # Search
    if 'search' in name_lower or 'content' in name_lower:
        return 'Search'
    # Core identity
    if 'core truth' in name_lower or 'boundaries' in name_lower or 'identity' in name_lower:
        return 'Core_Identity'
    # Meta
    if any(x in name_lower for x in ['runtime', 'silent', 'safety', 'startup', 'first run', 'red line', 'external', 'make it', 'model alias', 'quick reference', 'reply tag', 'messaging']):
        return 'Meta'
    return 'Other'

system_sections = parse_system_sections(system_prompt)
for s in system_sections:
    s['category'] = categorize_section_detailed(s['name'])

# Calculate detailed category totals
category_tokens = {}
for s in system_sections:
    cat = s['category']
    category_tokens[cat] = category_tokens.get(cat, 0) + s['tokens']

# Define ordered column headers for system prompt breakdown
system_columns = [
    'Workspace_Files',  # AGENTS.md, SOUL.md, etc.
    'Tool_List',        # Tooling section
    'Tool_JSON',        # JSON tool schemas
    'Skills',           # Skill definitions
    'Memory_History',   # Memory and conversation history
    'Heartbeats',       # Heartbeat configuration
    'Group_Chats',      # Group chat instructions
    'Workflow',         # Workflow instructions
    'Task_Tracing',     # Task tracing
    'Search',           # Search configuration
    'Core_Identity',    # Core identity docs
    'Meta',             # Meta instructions
    'Other',            # Other
]

# Parse timestamp helper (must be before main parsing loop)
def parse_timestamp(ts):
    try:
        return datetime.fromisoformat(ts.replace('Z', '+00:00'))
    except:
        return None

# Track API calls by user turn with timestamps
api_calls = []
current_user = None
user_turn_count = 0
prev_timestamp = None

with open(session_file, 'r') as f:
    for line in f:
        try:
            data = json.loads(line.strip())
            if data.get('type') == 'message':
                msg = data.get('message', {})
                role = msg.get('role', '')
                timestamp = data.get('timestamp', '')
                
                if role == 'user':
                    user_turn_count += 1
                    content = msg.get('content', [])
                    if isinstance(content, list):
                        texts = [item.get('text', '') for item in content if item.get('type') == 'text']
                        current_user = '\n'.join(texts)
                    else:
                        current_user = str(content)
                    turn_start_ts = timestamp
                    prev_timestamp = timestamp
                        
                elif role == 'assistant':
                    usage = msg.get('usage', {})
                    input_tokens = usage.get('input', 0)
                    
                    if input_tokens > 0:
                        # Calculate call duration from previous message
                        call_duration = 0
                        if prev_timestamp:
                            curr_ts = parse_timestamp(timestamp)
                            prev_ts = parse_timestamp(prev_timestamp)
                            if curr_ts and prev_ts:
                                call_duration = (curr_ts - prev_ts).total_seconds()
                        
                        api_calls.append({
                            'call_num': len(api_calls) + 1,
                            'user_turn': user_turn_count,
                            'user_prompt': current_user,
                            'input_tokens': input_tokens,
                            'output_tokens': usage.get('output', 0),
                            'cache_read': usage.get('cacheRead', 0),
                            'cache_write': usage.get('cacheWrite', 0),
                            'timestamp': timestamp,
                            'turn_start_ts': turn_start_ts,
                            'call_duration': call_duration,
                            'tool_calls': len(msg.get('toolCalls', [])),
                            'stop_reason': msg.get('stopReason', '')
                        })
                        prev_timestamp = timestamp
                            
        except:
            pass

# Aggregate by turn with duration

turns = {}
for call in api_calls:
    turn = call['user_turn']
    if turn not in turns:
        turns[turn] = {
            'input_tokens': 0,
            'output_tokens': 0,
            'cache_read': 0,
            'cache_write': 0,
            'api_calls': 0,
            'tool_calls': 0,
            'user_prompt': call['user_prompt'],
            'first_input': call['input_tokens'],
            'last_input': call['input_tokens'],
            'first_ts': call['turn_start_ts'],
            'last_ts': call['timestamp']
        }
    
    turns[turn]['input_tokens'] += call['input_tokens']
    turns[turn]['output_tokens'] += call['output_tokens']
    turns[turn]['cache_read'] += call['cache_read']
    turns[turn]['cache_write'] += call['cache_write']
    turns[turn]['api_calls'] += 1
    turns[turn]['tool_calls'] += call['tool_calls']
    turns[turn]['last_input'] = call['input_tokens']
    turns[turn]['last_ts'] = call['timestamp']

# Calculate duration for each turn
for turn_num, r in turns.items():
    start = parse_timestamp(r['first_ts'])
    end = parse_timestamp(r['last_ts'])
    if start and end:
        r['duration_seconds'] = (end - start).total_seconds()
    else:
        r['duration_seconds'] = 0

# Write per-call CSV with detailed system prompt breakdown and duration
call_csv_file = output_file.replace('.csv', '_calls.csv')
os.makedirs(os.path.dirname(call_csv_file), exist_ok=True)
with open(call_csv_file, 'w', newline='') as f:
    writer = csv.writer(f)
    
    # Header with system prompt breakdown columns
    header = [
        'Call#', 'Turn', 'Input Tokens', 'Output Tokens', 'Total Tokens', 
        'Cache Read', 'Cache Write', 'Tool Calls', 'Stop Reason',
        'Call Duration (s)',
        'System Chars', 'System Tokens (est)',
    ] + system_columns + ['User Prompt (truncated)']
    writer.writerow(header)
    
    for call in api_calls:
        row = [
            call['call_num'],
            call['user_turn'],
            call['input_tokens'],
            call['output_tokens'],
            call['input_tokens'] + call['output_tokens'],
            call['cache_read'],
            call['cache_write'],
            call['tool_calls'],
            call['stop_reason'],
            f"{call['call_duration']:.1f}" if call['call_duration'] > 0 else '-',
            system_prompt_chars,
            system_tokens_est,
        ] + [category_tokens.get(col, 0) for col in system_columns] + [
            call['user_prompt'][:60] + '...' if len(call['user_prompt']) > 60 else call['user_prompt']
        ]
        writer.writerow(row)

print(f"Exported {len(api_calls)} API calls to: {call_csv_file}")

# Write per-turn summary CSV with duration and system breakdown
os.makedirs(os.path.dirname(output_file), exist_ok=True)
with open(output_file, 'w', newline='') as f:
    writer = csv.writer(f)
    
    # Use same system_columns order as per-call CSV
    header = [
        'Turn', 'API Calls', 'Total Input', 'Total Output', 'Total Tokens',
        'Cache Read', 'Cache Write', 'Tool Calls',
        'First Input', 'Last Input', 'Context Growth',
        'Duration (s)',
        'System Chars', 'System Tokens (est)',
    ] + system_columns + ['User Prompt (truncated)']
    writer.writerow(header)
    
    for turn_num in sorted(turns.keys()):
        r = turns[turn_num]
        growth = r['last_input'] - r['first_input']
        row = [
            turn_num,
            r['api_calls'],
            r['input_tokens'],
            r['output_tokens'],
            r['input_tokens'] + r['output_tokens'],
            r['cache_read'],
            r['cache_write'],
            r['tool_calls'],
            r['first_input'],
            r['last_input'],
            growth,
            int(r['duration_seconds']),
            system_prompt_chars,
            system_tokens_est,
        ] + [category_tokens.get(col, 0) for col in system_columns] + [
            r['user_prompt'][:60] + '...' if len(r['user_prompt']) > 60 else r['user_prompt']
        ]
        writer.writerow(row)

print(f"Exported {len(turns)} turns to: {output_file}")

# Write system prompt breakdown CSV
if system_sections:
    system_breakdown_file = output_file.replace('.csv', '_system_breakdown.csv')
    with open(system_breakdown_file, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['Section', 'Category', 'Chars', 'Tokens', 'First Input Pct'])
        
        first_input = api_calls[0]['input_tokens'] if api_calls else 1
        for s in sorted(system_sections, key=lambda x: x['tokens'], reverse=True):
            pct = s['tokens'] / first_input * 100 if first_input > 0 else 0
            writer.writerow([
                s['name'],
                s['category'],
                s['chars'],
                s['tokens'],
                f"{pct:.1f}%"
            ])
    
    print(f"System prompt breakdown ({len(system_sections)} sections) saved to: {system_breakdown_file}")

# Write system prompt detail file
if system_prompt:
    system_file = os.path.join(os.path.dirname(call_csv_file), f"{session_id}_system_prompt.txt")
    with open(system_file, 'w') as f:
        f.write(system_prompt)
    print(f"System prompt ({system_prompt_chars} chars, ~{system_tokens_est} tokens) saved to: {system_file}")

PYEOF
}

# System Prompt Breakdown Analysis (inspired by modelbox analyze-log)
prompt_breakdown() {
    local session_id="${1:-$(get_latest_session)}"
    local index="${2:--1}"
    local output_json=""
    # Handle --json or -j flag in any position after index
    for arg in "$@"; do
        if [ "$arg" = "--json" ] || [ "$arg" = "-j" ]; then
            output_json="$arg"
        fi
    done
    local session_file="${SESSIONS_DIR}/${session_id}.jsonl"
    
    if [ ! -f "$session_file" ]; then
        echo "Session not found: $session_id"
        return 1
    fi
    
    # Build session key for sessions.json lookup
    session_key="agent:main:${session_id}"
    
    python3 - "$session_id" "$session_file" "$index" "$output_json" "$session_key" "$SESSIONS_JSON" << 'PYEOF'
import json
import sys
import re
import os

session_id = sys.argv[1]
session_file = sys.argv[2]
index_arg = sys.argv[3] if len(sys.argv) > 3 else "-1"
output_json = ""
session_key = ""
sessions_json = ""
for i, arg in enumerate(sys.argv[4:], 4):
    if arg in ("--json", "-j"):
        output_json = arg
    elif i == 5:
        session_key = arg
    elif i == 6:
        sessions_json = arg

index = int(index_arg) if index_arg.lstrip('-').isdigit() else -1

workspace = os.path.expanduser("~/.openclaw/workspace")

# Try to read system prompt from intercept data first (most complete)
intercept_dir = os.path.join(workspace, "model_intercept")
system_text = ""

# Check intercept files
if os.path.isdir(intercept_dir):
    import glob
    pattern = os.path.join(intercept_dir, f"{session_id}_*.jsonl")
    intercept_files = sorted(glob.glob(pattern), reverse=True)
    for ifile in intercept_files:
        try:
            with open(ifile, 'r') as f:
                for line in f:
                    rec = json.loads(line.strip())
                    if rec.get('systemPrompt'):
                        system_text = rec['systemPrompt']
                        break
            if system_text:
                break
        except:
            pass

# Fall back to sessions.json if intercept not found
if not system_text and sessions_json and os.path.exists(sessions_json):
    try:
        with open(sessions_json, 'r') as f:
            data = json.load(f)
        
        # Try exact session key
        if session_key in data and 'skillsSnapshot' in data[session_key]:
            system_text = data[session_key]['skillsSnapshot'].get('prompt', '')
        
        # Try partial match
        if not system_text:
            for key in data.keys():
                if session_id in key and 'skillsSnapshot' in data.get(key, {}):
                    system_text = data[key]['skillsSnapshot'].get('prompt', '')
                    break
    except Exception as e:
        pass

# Read workspace context files
context_files = ['SOUL.md', 'USER.md', 'AGENTS.md', 'MEMORY.md']
workspace_parts = {}
for fname in context_files:
    fpath = os.path.join(workspace, fname)
    if os.path.exists(fpath):
        try:
            with open(fpath, 'r') as f:
                content = f.read()
                if len(content) > 100:  # Only if meaningful content
                    workspace_parts[fname] = content
        except:
            pass

def token_estimate(chars):
    """Estimate tokens from chars: low=chars/4, high=chars/2.5"""
    low = round(chars / 4)
    high = round(chars / 2.5)
    mid = round((low + high) / 2)
    return {"low": low, "est": mid, "high": high}

def extract_tool_names_from_system(system_text):
    """Extract tool names from ## Tooling section"""
    names = []
    if not system_text:
        return names
    
    start = system_text.find("## Tooling")
    end = system_text.find("## Tool Call Style")
    if start < 0 or end < 0 or end <= start:
        return names
    
    block = system_text[start:end]
    for line in block.split('\n'):
        if not line.startswith('- '):
            continue
        try:
            colon_idx = line.index(':')
            if colon_idx < 0:
                continue
            name = line[2:colon_idx].strip()
            if name:
                names.append(name)
        except:
            pass
    return names

def build_sections(system_text):
    """Break down system prompt into sections"""
    sections = []
    
    if not system_text:
        return sections
    
    # Total system prompt
    sections.append({
        "key": "system_total",
        "label": "system.total",
        "source": "system_prompt",
        "text": system_text
    })
    
    # Head before # Project Context
    project_ctx_idx = system_text.find("# Project Context")
    if project_ctx_idx >= 0:
        head = system_text[:project_ctx_idx]
        sections.append({
            "key": "system_head",
            "label": "system.head_before_project_context",
            "source": "system_prompt",
            "text": head
        })
    
    # Project context files
    tail_titles = ["## Silent Replies", "## Heartbeats", "## Runtime", "## Tooling"]
    tail_starts = [system_text.find(t) for t in tail_titles if system_text.find(t) >= 0]
    tail_start = min(tail_starts) if tail_starts else -1
    
    if project_ctx_idx >= 0:
        project_end = tail_start if tail_start >= 0 else len(system_text)
        project_block = system_text[project_ctx_idx:project_end]
        
        heading_pattern = re.compile(r'^## (\/[^\n]+)$', re.MULTILINE)
        headings = []
        for match in heading_pattern.finditer(project_block):
            headings.append({
                "path": match.group(1),
                "offset": match.start(),
                "line_len": len(match.group(0))
            })
        
        for i, heading in enumerate(headings):
            next_offset = headings[i + 1]["offset"] if i + 1 < len(headings) else len(project_block)
            body_start = heading["offset"] + heading["line_len"] + 1
            body = project_block[body_start:next_offset]
            sections.append({
                "key": f"context_file:{heading['path']}",
                "label": f"project_context_file:{heading['path']}",
                "source": "dynamic_injected_file",
                "text": body.strip()
            })
    
    # Tail sections
    for title in tail_titles:
        start = system_text.find(title)
        if start < 0:
            continue
        title_end = system_text.find('\n', start)
        content_start = title_end + 1 if title_end >= 0 else start + len(title)
        
        next_starts = []
        for next_title in tail_titles:
            idx = system_text.find(next_title, start + 1)
            if idx >= 0:
                next_starts.append(idx)
        
        end = min(next_starts) if next_starts else len(system_text)
        body = system_text[content_start:end].strip()
        
        label_key = title.replace('## ', '').lower().replace(' ', '_')
        sections.append({
            "key": f"tail:{title}",
            "label": f"system_tail:{label_key}",
            "source": "system_prompt",
            "text": body
        })
    
    return sections

# Read session and extract messages
messages = []
with open(session_file, 'r') as f:
    for line in f:
        try:
            data = json.loads(line.strip())
            if data.get('type') == 'message':
                msg = data.get('message', {})
                messages.append(msg)
        except:
            pass

# Group messages by turns
assistant_requests = []
current_input = []
for msg in messages:
    role = msg.get('role', '')
    usage = msg.get('usage', {})
    
    if role == 'user':
        if current_input:
            assistant_requests.append(current_input.copy())
        current_input = []
    
    if usage and usage.get('input', 0) > 0:
        current_input.append(msg)

if current_input:
    assistant_requests.append(current_input)

# Find tools from messages
all_tools = []
for msg in messages:
    if msg.get('role') == 'assistant':
        tool_calls = msg.get('toolCalls', [])
        if not tool_calls and isinstance(msg.get('content'), list):
            for item in msg.get('content', []):
                if item.get('type') == 'toolCall':
                    all_tools.append(item.get('name', ''))
        else:
            for tc in tool_calls:
                if isinstance(tc, dict) and tc.get('name'):
                    all_tools.append(tc.get('name'))

# Resolve index
if index < 0:
    idx = len(assistant_requests) + index if index < 0 else index
else:
    idx = index

if idx < 0 or idx >= len(assistant_requests):
    idx = len(assistant_requests) - 1

# Analyze sections
sections = build_sections(system_text)
system_tool_names = set(extract_tool_names_from_system(system_text))
payload_tool_names = set([t for t in all_tools if t])

# Calculate stats
section_stats = []
for section in sections:
    chars = len(section['text'])
    tokens = token_estimate(chars)
    section_stats.append({
        "key": section['key'],
        "label": section['label'],
        "source": section['source'],
        "chars": chars,
        "tokens": tokens
    })

section_stats.sort(key=lambda x: x['tokens']['est'], reverse=True)

# Build report
report = {
    "session_id": session_id,
    "system_chars": len(system_text),
    "system_tokens": token_estimate(len(system_text)),
    "sections": section_stats,
    "tools": {
        "count": len(all_tools),
        "payload_tool_names": sorted(list(set(all_tools))),
        "system_tool_names": sorted(list(system_tool_names)),
        "overlap": {
            "intersection": len(system_tool_names & payload_tool_names),
            "only_in_system": sorted(list(system_tool_names - payload_tool_names)),
            "only_in_payload": sorted(list(payload_tool_names - system_tool_names))
        }
    }
}

# Output
if output_json == "--json" or output_json == "-j":
    print(json.dumps(report, indent=2, ensure_ascii=False))
else:
    print("=" * 80)
    print(f"System Prompt Breakdown - Session: {session_id}")
    print("=" * 80)
    print()
    print(f"System Prompt: chars={report['system_chars']}, tokens~{report['system_tokens']['low']}-{report['system_tokens']['high']} (est {report['system_tokens']['est']})")
    print()
    print(f"Tools: {report['tools']['count']} in payload, {len(system_tool_names)} in system prompt")
    print(f"Tool overlap: {report['tools']['overlap']['intersection']}/{len(payload_tool_names)}")
    if report['tools']['overlap']['only_in_system']:
        print(f"  Only in system: {', '.join(report['tools']['overlap']['only_in_system'])}")
    if report['tools']['overlap']['only_in_payload']:
        print(f"  Only in payload: {', '.join(report['tools']['overlap']['only_in_payload'])}")
    print()
    print("Sections (sorted by est tokens desc):")
    for section in report['sections']:
        print(f"  - {section['label']} [{section['source']}]: chars={section['chars']}, tokens~{section['tokens']['low']}-{section['tokens']['high']} (est {section['tokens']['est']})")
    print()
    print("=" * 80)

PYEOF
}

case "$1" in
    analyze)
        session_id="${2:-$(get_latest_session)}"
        if [ -z "$session_id" ]; then
            echo "No sessions found"
            exit 1
        fi
        analyze_session "$session_id"
        ;;
        
    dump)
        session_id="${2:-$(get_latest_session)}"
        format="text"
        if [ -n "$3" ] && [ "$3" = "--format" ] && [ -n "$4" ]; then
            format="$4"
        fi
        if [ -z "$session_id" ]; then
            echo "No sessions found"
            exit 1
        fi
        dump_session "$session_id" "$format"
        ;;
        
    rounds)
        session_id="${2:-$(get_latest_session)}"
        if [ -z "$session_id" ]; then
            echo "No sessions found"
            exit 1
        fi
        count_rounds "$session_id"
        ;;
        
    prompts)
        session_id="${2:-$(get_latest_session)}"
        if [ -z "$session_id" ]; then
            echo "No sessions found"
            exit 1
        fi
        dump_prompts "$session_id"
        ;;
        
    outputs)
        session_id="${2:-$(get_latest_session)}"
        if [ -z "$session_id" ]; then
            echo "No sessions found"
            exit 1
        fi
        dump_outputs "$session_id"
        ;;
        
    latest)
        latest=$(get_latest_session)
        if [ -z "$latest" ]; then
            echo "No sessions found"
            exit 1
        fi
        echo "Latest session: $latest"
        ;;
        
    export)
        session_id="${2:-$(get_latest_session)}"
        if [ -z "$session_id" ]; then
            echo "No sessions found"
            exit 1
        fi
        output_file="${3:-${EXPORT_DIR}/${session_id}.jsonl}"
        export_jsonl "$session_id" "$output_file"
        ;;
        
    intercept)
        session_id="${2:-main}"
        date="${3:-$(date +%Y-%m-%d)}"
        intercepted_calls "$session_id" "$date"
        ;;
        
    export-full)
        session_id="${2:-main}"
        output_file="${3:-}"
        export_full "$session_id" "$output_file"
        ;;
        
    system-prompt)
        session_key="${2:-agent:main:main}"
        get_system_prompt "$session_key"
        ;;
        
    token-stats)
        session_id="${2:-$(get_latest_session)}"
        output_file="${3:-}"
        if [ -z "$session_id" ]; then
            echo "No sessions found"
            exit 1
        fi
        if [ -n "$output_file" ]; then
            token_stats "$session_id" "$output_file"
        else
            token_stats "$session_id"
        fi
        ;;
        
    token-stats-all)
        output_file="${2:-}"
        if [ -n "$output_file" ]; then
            token_stats_all "$output_file"
        else
            token_stats_all
        fi
        ;;
        
    token-export)
        session_id="${2:-$(get_latest_session)}"
        output_file="${3:-}"
        if [ -z "$session_id" ]; then
            echo "No sessions found"
            exit 1
        fi
        if [ -n "$output_file" ]; then
            token_export_csv "$session_id" "$output_file"
        else
            token_export_csv "$session_id"
        fi
        ;;
        
    export-simple)
        session_id="${2:-$(get_latest_session)}"
        if [ -z "$session_id" ]; then
            echo "No sessions found"
            exit 1
        fi
        output_file="${3:-${EXPORT_DIR}/${session_id}_simple.jsonl}"
        export_simple_jsonl "$session_id" "$output_file"
        ;;
        
    prompt-breakdown)
        session_id="${2:-$(get_latest_session)}"
        index="${3:--1}"
        output_json="${4:-}"
        prompt_breakdown "$session_id" "$index" "$output_json"
        ;;
        
    *)
        echo "model-dumper: Dump and analyze OpenClaw model interactions"
        echo ""
        echo "Usage: model-dumper <command> [options]"
        echo ""
        echo "Commands:"
        echo "  analyze [session-id]      Analyze session and show statistics"
        echo "  dump [session-id]        Dump complete session details"
        echo "  rounds [session-id]     Show round count only"
        echo "  prompts [session-id]     Show all prompts sent to model"
        echo "  outputs [session-id]     Show all model outputs"
        echo "  latest                   Show latest session ID"
        echo "  export [session-id]       Export to JSONL file (from session)"
        echo "  intercept [session]      Show intercepted LLM calls"
        echo "  export-full [session]    Export full data including intercept"
        echo "  system-prompt [key]     Show system prompt from sessions.json"
        echo "  token-stats [id] [file]  Show detailed token statistics per round"
        echo "  token-stats-all [file]   Show token stats for all sessions"
        echo "  token-export [id] [file] Export token stats to CSV"
        echo "  export-simple [id]    Export simple JSONL (input/output text)"
        echo "  prompt-breakdown [id] [idx] [json]  Analyze system prompt breakdown"
        echo ""
        echo "Examples:"
        echo "  model-dumper analyze"
        echo "  model-dumper token-stats rest-api-dev"
        echo "  model-dumper token-stats rest-api-dev /tmp/stats.txt"
        echo "  model-dumper token-stats-all"
        echo "  model-dumper token-export rest-api-dev"
        echo "  model-dumper prompt-breakdown rest-api-dev"
        echo "  model-dumper prompt-breakdown rest-api-dev -1 --json"
        echo ""
        echo "Examples:"
        echo "  model-dumper analyze"
        echo "  model-dumper export"
        echo "  model-dumper export 0d49e16e-23ac-4935-b932-d2283b5d725e"
        echo "  model-dumper intercept"
        echo "  model-dumper export-full"
        echo "  model-dumper system-prompt"
        ;;
esac
