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
    
    python3 - "$session_file" "$output_file" << 'PYEOF'
import json
import sys
from datetime import datetime

session_file = sys.argv[1]
output_file = sys.argv[2] if len(sys.argv) > 2 else None

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
    """Extract complete content structure including thinking, text, tool calls"""
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

def format_message(msg):
    role = msg.get('role', 'unknown')
    content = msg.get('content', '')
    text = extract_text_content(content)
    
    thinking = msg.get('thinking', '')
    
    result = f"[{role.upper()}]"
    if thinking:
        result += f"\n<thinking>{thinking}</thinking>"
    if text:
        result += f"\n{text}"
    
    tool_calls = msg.get('toolCalls', [])
    if tool_calls:
        for tc in tool_calls:
            tc_name = tc.get('name', 'unknown')
            result += f"\n<tool_call>{tc_name}</tool_call>"
    
    return result.strip()

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
current_input = []
current_tool_results = []  # Track tool results separately

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
        current_input.append(format_message(msg))
        current_tool_results = []  # Reset tool results on new user message
        
    elif role == 'toolResult':
        # Extract full tool result content
        content = msg.get('content', [])
        tool_result_text = extract_text_content(content)
        
        # Get tool result details
        tool_result_obj = {
            "text": tool_result_text,
            "raw_content": content
        }
        
        # Try to extract tool_use_id if available
        if isinstance(content, list):
            for item in content:
                if isinstance(item, dict) and item.get('type') == 'text':
                    # Parse the text to extract tool_use_id if present
                    text = item.get('text', '')
                    if 'tool_use_id' in text.lower():
                        tool_result_obj['has_tool_use_id'] = True
        
        current_tool_results.append(tool_result_obj)
        current_input.append(f"[TOOL_RESULT]\n{tool_result_text}")
        
    elif role == 'assistant':
        if current_input:
            # Get full content structure
            content = msg.get('content', [])
            full_content = extract_full_content(content)
            
            # Get thinking (may be at content level or separate field)
            thinking = msg.get('thinking', '')
            for item in full_content:
                if item.get('type') == 'thinking' and not thinking:
                    thinking = item.get('thinking', '')
                    break
            
            # Build text output
            output_text = extract_text_content(content)
            if thinking:
                output_text = f"<thinking>{thinking}</thinking>\n{output_text}"
            
            # Get tool calls - check both top-level and content array
            tool_calls = msg.get('toolCalls', [])
            if not tool_calls:
                # Extract tool calls from content array
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
                    output_text += f"\n<tool_call>{tc.get('name', 'unknown')}</tool_call>"
            
            usage = msg.get('usage', {})
            
            entry = {
                "timestamp": ts_epoch,
                "input": "\n\n".join(current_input),
                "output": output_text.strip(),
                "output_full": {
                    "thinking": thinking,
                    "text": extract_text_content(content),
                    "toolCalls": tool_calls_output,
                    "toolResults": current_tool_results,  # Include tool results
                    "raw_content": full_content
                },
                "token_usage": {
                    "input": usage.get('input', 0),
                    "output": usage.get('output', 0),
                    "total": usage.get('totalTokens', 0)
                } if usage else None,
                "model": msg.get('model', None),
                "stop_reason": msg.get('stopReason', None)
            }
            entries.append(entry)
            
            current_input.append(format_message(msg))

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
from datetime import datetime

session_id = sys.argv[1]
session_file = sys.argv[2]
output_file = sys.argv[3] if len(sys.argv) > 3 else None

# Read session data - track ALL API calls
api_calls = []
current_user = None
user_turn_count = 0

with open(session_file, 'r') as f:
    for line in f:
        try:
            data = json.loads(line.strip())
            if data.get('type') == 'message':
                msg = data.get('message', {})
                role = msg.get('role', '')
                
                if role == 'user':
                    user_turn_count += 1
                    content = msg.get('content', [])
                    if isinstance(content, list):
                        texts = [item.get('text', '') for item in content if item.get('type') == 'text']
                        current_user = '\n'.join(texts)
                    else:
                        current_user = str(content)
                    # Truncate for display
                    current_user = current_user[:80].replace('\n', ' ')
                        
                elif role == 'assistant':
                    usage = msg.get('usage', {})
                    input_tokens = usage.get('input', 0)
                    output_tokens = usage.get('output', 0)
                    
                    if input_tokens > 0:
                        api_calls.append({
                            'user_turn': user_turn_count,
                            'user_prompt': current_user,
                            'input_tokens': input_tokens,
                            'output_tokens': output_tokens,
                            'cache_read': usage.get('cacheRead', 0),
                            'cache_write': usage.get('cacheWrite', 0),
                            'timestamp': data.get('timestamp', ''),
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
            'calls': []
        }
    
    turns[turn]['input_tokens'] += call['input_tokens']
    turns[turn]['output_tokens'] += call['output_tokens']
    turns[turn]['cache_read'] += call['cache_read']
    turns[turn]['cache_write'] += call['cache_write']
    turns[turn]['api_calls'] += 1
    turns[turn]['tool_calls'] += call['tool_calls']
    turns[turn]['last_input'] = call['input_tokens']
    turns[turn]['calls'].append(call)

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
        'calls': r['calls']
    })

# Calculate totals
total_input = sum(r['input_tokens'] for r in rounds)
total_output = sum(r['output_tokens'] for r in rounds)
total_cache_read = sum(r['cache_read'] for r in rounds)
total_cache_write = sum(r['cache_write'] for r in rounds)

# Build output
output_lines = []
output_lines.append("=" * 130)
output_lines.append(f"TOKEN STATISTICS REPORT - Session: {session_id}")
output_lines.append(f"Generated: {datetime.now().isoformat()}")
output_lines.append("=" * 130)
output_lines.append("")

# Summary
output_lines.append("📊 SUMMARY")
output_lines.append("-" * 60)
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
output_lines.append("")

# Per-API-Call table
output_lines.append("📈 PER-API-CALL TOKEN BREAKDOWN")
output_lines.append("-" * 130)
header = f"{'#':<4} {'Turn':<5} {'Input':>10} {'Output':>10} {'Cache':>10} {'Tools':>6} {'Stop Reason':<12} {'User Prompt':<60}"
output_lines.append(header)
output_lines.append("-" * 130)

for i, call in enumerate(api_calls, 1):
    prompt = call['user_prompt'][:58] if call['user_prompt'] else '(startup)'
    stop = call.get('stop_reason', '')[:12]
    row = f"{i:<4} {call['user_turn']:<5} {call['input_tokens']:>10,} {call['output_tokens']:>10,} {call['cache_read']:>10,} {call['tool_calls']:>6} {stop:<12} {prompt}"
    output_lines.append(row)

output_lines.append("-" * 130)
summary_row = f"{'TOTAL':<4} {'':<5} {total_input:>10,} {total_output:>10,} {total_cache_read:>10,} {sum(c['tool_calls'] for c in api_calls):>6} {'':<12} {'':<60}"
output_lines.append(summary_row)
output_lines.append("")

# Per-turn summary table
output_lines.append("📊 PER-TURN SUMMARY")
output_lines.append("-" * 100)
header2 = f"{'Turn':<5} {'Calls':>6} {'Total Input':>12} {'Total Output':>12} {'First In':>10} {'Last In':>10} {'Growth':>10} {'User Prompt':<35}"
output_lines.append(header2)
output_lines.append("-" * 100)

for r in rounds:
    prompt = r['user_prompt'][:33] if r['user_prompt'] else '(startup)'
    growth = r['last_input'] - r['first_input']
    row = f"{r['turn']:<5} {r['api_calls']:>6} {r['input_tokens']:>12,} {r['output_tokens']:>12,} {r['first_input']:>10,} {r['last_input']:>10,} {growth:>10,} {prompt}"
    output_lines.append(row)

output_lines.append("-" * 100)
total_row = f"{'TOTAL':<5} {sum(r['api_calls'] for r in rounds):>6} {total_input:>12,} {total_output:>12,} {'':<10} {'':<10} {'':<10} {'':<35}"
output_lines.append(total_row)
output_lines.append("")

# Input breakdown summary
output_lines.append("📦 INPUT TOKEN BREAKDOWN (Approximation)")
output_lines.append("-" * 60)

first_input = rounds[0]['first_input'] if rounds else 0
system_estimate = min(first_input * 0.5, 12000) if first_input > 0 else 0

history_growth = []
for i, r in enumerate(rounds):
    if i > 0:
        history_growth.append(r['last_input'] - r['first_input'])

avg_growth = sum(history_growth) / len(history_growth) if history_growth else 0

output_lines.append(f"System Prompt (est.): ~{int(system_estimate):,} tokens (first call)")
output_lines.append(f"Avg Context Growth: ~{int(avg_growth):,} tokens/call")
output_lines.append(f"Max Context: {max(r['last_input'] for r in rounds) if rounds else 0:,} tokens")
output_lines.append("")

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
import csv

session_id = sys.argv[1]
session_file = sys.argv[2]
output_file = sys.argv[3] if len(sys.argv) > 3 else None

if not output_file:
    output_file = session_file.replace('.jsonl', '_tokens.csv')

# Track API calls by user turn
api_calls = []
current_user = None
user_turn_count = 0

with open(session_file, 'r') as f:
    for line in f:
        try:
            data = json.loads(line.strip())
            if data.get('type') == 'message':
                msg = data.get('message', {})
                role = msg.get('role', '')
                
                if role == 'user':
                    user_turn_count += 1
                    content = msg.get('content', [])
                    if isinstance(content, list):
                        texts = [item.get('text', '') for item in content if item.get('type') == 'text']
                        current_user = '\n'.join(texts)
                    else:
                        current_user = str(content)
                        
                elif role == 'assistant':
                    usage = msg.get('usage', {})
                    input_tokens = usage.get('input', 0)
                    
                    if input_tokens > 0:
                        api_calls.append({
                            'call_num': len(api_calls) + 1,
                            'user_turn': user_turn_count,
                            'user_prompt': current_user,
                            'input_tokens': input_tokens,
                            'output_tokens': usage.get('output', 0),
                            'cache_read': usage.get('cacheRead', 0),
                            'cache_write': usage.get('cacheWrite', 0),
                            'timestamp': data.get('timestamp', ''),
                            'tool_calls': len(msg.get('toolCalls', [])),
                            'stop_reason': msg.get('stopReason', '')
                        })
                            
        except:
            pass

# Aggregate by turn
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
            'last_input': call['input_tokens']
        }
    
    turns[turn]['input_tokens'] += call['input_tokens']
    turns[turn]['output_tokens'] += call['output_tokens']
    turns[turn]['cache_read'] += call['cache_read']
    turns[turn]['cache_write'] += call['cache_write']
    turns[turn]['api_calls'] += 1
    turns[turn]['tool_calls'] += call['tool_calls']
    turns[turn]['last_input'] = call['input_tokens']

# Write per-call CSV
call_csv_file = output_file.replace('.csv', '_calls.csv')
os.makedirs(os.path.dirname(call_csv_file), exist_ok=True)
with open(call_csv_file, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow([
        'Call#', 'Turn', 'Input Tokens', 'Output Tokens', 'Total Tokens', 
        'Cache Read', 'Cache Write', 'Tool Calls', 'Stop Reason',
        'User Prompt (truncated)'
    ])
    
    for call in api_calls:
        writer.writerow([
            call['call_num'],
            call['user_turn'],
            call['input_tokens'],
            call['output_tokens'],
            call['input_tokens'] + call['output_tokens'],
            call['cache_read'],
            call['cache_write'],
            call['tool_calls'],
            call['stop_reason'],
            call['user_prompt'][:80] + '...' if len(call['user_prompt']) > 80 else call['user_prompt']
        ])

print(f"Exported {len(api_calls)} API calls to: {call_csv_file}")

# Write per-turn summary CSV
os.makedirs(os.path.dirname(output_file), exist_ok=True)
with open(output_file, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow([
        'Turn', 'API Calls', 'Total Input', 'Total Output', 'Total Tokens',
        'Cache Read', 'Cache Write', 'Tool Calls',
        'First Input', 'Last Input', 'Context Growth',
        'User Prompt (truncated)'
    ])
    
    for turn_num in sorted(turns.keys()):
        r = turns[turn_num]
        growth = r['last_input'] - r['first_input']
        writer.writerow([
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
            r['user_prompt'][:80] + '...' if len(r['user_prompt']) > 80 else r['user_prompt']
        ])

print(f"Exported {len(turns)} turns to: {output_file}")

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
