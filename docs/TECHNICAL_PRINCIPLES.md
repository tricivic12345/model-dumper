# model-dumper 技术原理

> OpenClaw 模型交互数据导出与分析工具
> 
> **版本**: v0.8 | **日期**: 2026-03-19

---

## 目录

1. [数据源架构](#1-数据源架构)
2. [核心数据结构](#2-核心数据结构)
3. [Token 统计原理](#3-token-统计原理)
4. [Timing 指标统计](#4-timing-指标统计)
5. [数据合并算法](#5-数据合并算法)
6. [System Prompt 分析](#6-system-prompt-分析)
7. [导出格式详解](#7-导出格式详解)
8. [关键技术实现](#8-关键技术实现)

---

## 1. 数据源架构

model-dumper 依赖两个主要数据源：

### 1.1 Session 数据 (`sessions/*.jsonl`)

**路径**: `~/.openclaw/agents/main/sessions/*.jsonl`

**特点**:
- 包含完整的会话事件流
- 有精确的 token counts (`usage.input/output`)
- 但内容可能被截断（tool results 不完整）

**事件类型**:
```json
{"type": "session", ...}
{"type": "model_change", ...}
{"type": "message", "message": {...}}
{"type": "custom", "customType": "model-snapshot", ...}
```

### 1.2 Intercept 数据 (`model_intercept/*.jsonl`)

**路径**: `~/.openclaw/workspace/model_intercept/*_YYYY-MM-DD.jsonl`

**特点**:
- 包含完整发送给 LLM 的输入（system + history + prompt）
- 包含 `requestStartTime`（请求发送时间）
- 通过 OpenClaw 的 `llm_input` hook 捕获

**数据结构**:
```json
{
  "timestamp": 1773886622889,
  "sessionId": "main",
  "systemPrompt": "...(完整系统提示)...",
  "prompt": "...(当前用户输入)...",
  "historyMessages": [...],
  "messages": [...],
  "model": "stepfun/step-3.5-flash:free",
  "provider": "openrouter"
}
```

---

## 2. 核心数据结构

### 2.1 Message 结构

```typescript
interface Message {
  role: "user" | "assistant" | "tool";
  content: ContentBlock[];
  usage?: {
    input: number;
    output: number;
    cacheRead: number;
    cacheWrite: number;
    totalTokens: number;
  };
  stopReason?: "stop" | "toolUse" | "error";
}

type ContentBlock = 
  | { type: "text"; text: string }
  | { type: "thinking"; thinking: string }
  | { type: "toolCall"; id: string; name: string; arguments: object }
  | { type: "toolResult"; toolCallId: string; content: string };
```

### 2.2 Turn 结构

一次用户交互（Turn）可能包含多个 API 调用：

```
Turn N
├── API Call 1: user prompt → assistant (toolUse)
├── API Call 2: tool result → assistant (toolUse)
├── API Call 3: tool result → assistant (stop)
```

---

## 3. Token 统计原理

### 3.1 精确 Token（来自 API）

```python
# 从 session 消息直接读取
usage = message.get('usage', {})
input_tokens = usage.get('input', 0)      # API 返回的精确值
output_tokens = usage.get('output', 0)
cache_read = usage.get('cacheRead', 0)    # Cache 命中
cache_write = usage.get('cacheWrite', 0)  # Cache 写入
```

### 3.2 估算 Token（用于分解）

```python
# 当 API 不返回精确值时使用
def estimate_tokens(text: str) -> int:
    return round(len(text) / 2.6)  # 约 2.6 字符 ≈ 1 token
```

### 3.3 Cache 命中率

```python
if total_input > 0:
    cache_hit_rate = total_cache_read / total_input * 100
```

### 3.4 Duration 计算

```python
def calculate_duration(start_ts: str, end_ts: str) -> float:
    start = datetime.fromisoformat(start_ts.replace('Z', '+00:00'))
    end = datetime.fromisoformat(end_ts.replace('Z', '+00:00'))
    return (end - start).total_seconds()
```

---

## 4. Timing 指标统计

### 4.1 指标定义

| 指标 | 全称 | 说明 |
|------|------|------|
| **TTFT** | Time To First Token | 请求发出到收到第一个 token 的时间 |
| **TPOT** | Time Per Output Token | 每个输出 token 的平均时间 |
| **Total Time** | 总响应时间 | 请求发出到响应完成的时间 |
| **Prefill** | Prefill 时间 | 处理输入 prompt 的时间 |
| **Decode** | Decode 时间 | 生成输出 token 的时间 |

### 4.2 OpenRouter API 限制

**OpenRouter API 不暴露以下时间指标**:

| 指标 | 可用性 | 原因 |
|------|--------|------|
| TTFT | ❌ 不可用 | OpenRouter 未在响应中暴露 |
| TPOT | ✅ 可计算 | `totalTime / outputTokens` |
| Total Time | ✅ 可计算 | `messageTimestamp - requestStartTime` |
| Prefill | ❌ 不可用 | OpenRouter 未暴露 |
| Decode | ❌ 不可用 | OpenRouter 未暴露 |

### 4.3 计算方法

```python
# 从 intercept 获取请求开始时间
request_start_time = intercept_rec.get('requestStartTime', 0)

# 从 session 获取响应时间戳
message_timestamp = session_msg.get('timestamp', 0)

# 计算总时间 (ms)
total_time = message_timestamp - request_start_time

# 计算 TPOT (ms/token)
tpot = total_time / output_tokens if output_tokens > 0 else 0
```

### 4.4 数据来源

**JSONL 导出字段** (`timing`):

```json
{
  "timing": {
    "total_time_ms": 15234,
    "tpot_ms": 31.74,
    "ttft_ms": null,
    "prefill_ms": null,
    "decode_ms": null
  },
  "_timing_note": "Calculated from requestStartTime and message timestamp"
}
```

**CSV 导出新增列**:

| 列名 | 说明 |
|------|------|
| `Call Duration (s)` | 消息间隔时间（近似值） |
| `TPOT (ms/token)` | Time Per Output Token |
| `TTFT (ms)` | 标记为 "-"（不可用） |
| `Prefill (ms)` | 标记为 "-"（不可用） |
| `Decode (ms)` | 标记为 "-"（不可用） |
| `Note` | 说明文本 |

### 4.5 精度说明

⚠️ **重要说明**:

1. **Call Duration** 是**消息间隔时间**，不是真正的 API 响应时间
   - 包含：网络延迟 + API 处理时间 + OpenClaw 处理时间
   - 不是：纯 API 响应时间

2. **TPOT** 是基于 Call Duration 的**估算值**
   - 公式：`TPOT = Call Duration / Output Tokens`
   - 精度较低，仅供参考

3. **TTFT/Prefill/Decode** 不可用
   - 需要 OpenRouter 支持或客户端拦截测量

---

## 5. 数据合并算法

### 5.1 问题

| 数据源 | Input 完整性 | Token Counts |
|--------|-------------|--------------|
| Intercept | 100% | ❌ 无 |
| Session | ~70-80% | ✅ 精确 |

### 5.2 解决方案：内容相似度匹配

使用 `difflib.SequenceMatcher` 比较用户消息内容：

```python
def match_intercept_to_session(intercept_entries, session_messages, threshold=0.7):
    """
    匹配算法：
    1. 提取 Intercept 中的用户 prompt
    2. 提取 Session 中的用户消息
    3. 计算相似度分数
    4. 相似度 >= 0.7 时建立匹配
    """
    matches = {}
    
    for i, intercept_rec in enumerate(intercept_entries):
        intercept_prompt = intercept_rec.get('prompt', '')
        
        best_ratio = 0
        best_match_idx = -1
        
        for j, msg in enumerate(session_messages):
            if msg.get('role') != 'user':
                continue
            
            session_content = extract_text_content(msg.get('content', []))
            
            # 计算相似度
            ratio = difflib.SequenceMatcher(
                None,
                normalize_text(intercept_prompt),
                normalize_text(session_content)
            ).ratio()
            
            if ratio > best_ratio and ratio >= threshold:
                best_ratio = ratio
                best_match_idx = j
        
        # 找到匹配的用户消息后，定位下一个 assistant
        if best_match_idx >= 0:
            for k in range(best_match_idx + 1, len(session_messages)):
                if session_messages[k].get('role') == 'assistant':
                    matches[i] = k
                    break
    
    return matches
```

### 5.3 合并策略

```python
for i, intercept_rec in enumerate(intercept_entries):
    if i in matches:
        # Input: 从 Intercept 获取（完整）
        complete_input = build_input_from_intercept(intercept_rec)
        
        # Tokens: 从 Session 获取（精确）
        session_msg = session_messages[matches[i]]
        input_tokens = session_msg['usage']['input']
        output_tokens = session_msg['usage']['output']
    else:
        # Fallback: 使用 Intercept 数据
        ...
```

---

## 6. System Prompt 分析

### 6.1 分类规则

按 Markdown 标题进行分类：

```python
CATEGORY_PATTERNS = {
    'Core': r'^# ',                    # 一级标题
    'Skills': r'^## Skills',
    'Tooling': r'^## Tool',
    'Memory': r'^## Memory',
    'Heartbeats': r'^## Heartbeats',
    'Group Chats': r'^## Group',
    'Workflow': r'^## Workflow',
    'Task Tracing': r'^## Task',
    'Search': r'^## Search',
    'Meta': r'^## Meta',
    'Workspace': r'^## Workspace',
    'Other': r'^## '                    # 其他二级标题
}
```

### 6.2 分解算法

```python
def analyze_system_prompt(system_prompt: str):
    sections = []
    
    # 按标题分割
    pattern = r'(^#{1,6}\s+.+$)'
    parts = re.split(pattern, system_prompt, flags=re.MULTILINE)
    
    current_section = {'name': 'Preamble', 'category': 'Other', 'chars': 0, 'tokens': 0}
    
    for part in parts:
        if re.match(pattern, part):
            # 保存上一个 section
            if current_section['chars'] > 0:
                sections.append(current_section)
            # 开始新 section
            header = part.strip('#').strip()
            current_section = {
                'name': header,
                'category': categorize(header),
                'chars': 0,
                'tokens': 0
            }
        else:
            # 累加字符
            current_section['chars'] += len(part)
            current_section['tokens'] = round(current_section['chars'] / 2.6)
    
    if current_section['chars'] > 0:
        sections.append(current_section)
    
    return sections
```

### 6.3 Category 统计输出

```
📋 SYSTEM PROMPT BREAKDOWN (by Category)
--------------------------------------------------------------------------------
  15,571 tokens (100.0%) |   40,485 chars | Core
   2,100 tokens ( 13.5%) |    5,460 chars | Skills
   1,800 tokens ( 11.6%) |    4,680 chars | Tooling
     500 tokens (  3.2%) |    1,300 chars | Memory
     ...
```

---

## 7. 导出格式详解

### 7.1 JSONL 格式 (`export-simple`)

```jsonl
{"timestamp":1773886622889,"ts_human":"2026-03-19T02:17:02.889Z","input":"[SYSTEM]\n...","output":"[THINKING]\n...","input_tokens":15571,"output_tokens":480,"stop_reason":"stop","model":"stepfun/step-3.5-flash:free","timing":{"total_time_ms":15234,"tpot_ms":31.74,"ttft_ms":null,"prefill_ms":null,"decode_ms":null}}
```

**字段说明**:

| 字段 | 来源 | 说明 |
|------|------|------|
| `timestamp` | Intercept | 毫秒级时间戳 |
| `ts_human` | Intercept | ISO 格式时间 |
| `input` | Intercept | 完整输入文本 |
| `output` | Session | 模型输出（含 thinking/toolCalls/text） |
| `input_tokens` | Session | API 返回的精确值 |
| `output_tokens` | Session | API 返回的精确值 |
| `stop_reason` | Session | stop/toolUse/error |
| `model` | Intercept | 模型 ID |
| `timing.total_time_ms` | 计算 | 总响应时间 (ms) |
| `timing.tpot_ms` | 计算 | Time Per Output Token (ms/token) |
| `timing.ttft_ms` | N/A | OpenRouter 不暴露 |
| `timing.prefill_ms` | N/A | OpenRouter 不暴露 |
| `timing.decode_ms` | N/A | OpenRouter 不暴露 |

### 7.2 CSV 格式 (`token-export`)

**文件 1: `*_token_stats_calls.csv`**

| 列名 | 说明 |
|------|------|
| Call# | API 调用序号 |
| Turn | 用户轮次 |
| Input Tokens | 输入 token 数 |
| Output Tokens | 输出 token 数 |
| Cache Read | Cache 命中 token |
| Tool Calls | 工具调用次数 |
| Stop Reason | 停止原因 |
| Call Duration (s) | 调用间隔 |
| User Prompt | 用户输入（截断） |

**文件 2: `*_token_stats.csv`**

| 列名 | 说明 |
|------|------|
| Turn | 用户轮次 |
| API Calls | 该轮 API 调用数 |
| Total Input | 该轮总输入 token |
| Total Output | 该轮总输出 token |
| First Input | 首次输入 token |
| Last Input | 最后输入 token |
| Context Growth | 上下文增长 |
| Duration (s) | 该轮耗时 |
| Avg TPOT (ms/token) | 平均 Time Per Output Token |

**文件 3: `*_system_breakdown.csv`**

| 列名 | 说明 |
|------|------|
| Section | Section 名称 |
| Category | 分类 |
| Tokens | 估算 token 数 |
| Chars | 字符数 |
| Percentage | 占比 |

---

## 8. 关键技术实现

### 8.1 内容提取

```python
def extract_text_content(content):
    """从多种格式提取文本"""
    if isinstance(content, list):
        texts = []
        for item in content:
            if item.get('type') == 'text':
                texts.append(item.get('text', ''))
            elif item.get('type') == 'toolResult':
                texts.append(str(item.get('content', '')))
        return '\n'.join(texts)
    return str(content) if content else ''

def extract_thinking(content):
    """提取思考内容"""
    if isinstance(content, list):
        for item in content:
            if item.get('type') == 'thinking':
                return item.get('thinking', '')
    return ''

def extract_tool_calls(msg):
    """提取工具调用"""
    tool_calls = msg.get('toolCalls', [])
    if not tool_calls and isinstance(msg.get('content'), list):
        for item in msg.get('content', []):
            if item.get('type') == 'toolCall':
                tool_calls.append(item)
    return tool_calls
```

### 8.2 完整输入构建

```python
def build_input_from_intercept(intercept_rec):
    """从 Intercept 构建完整输入"""
    parts = []
    
    # 1. System Prompt
    system_prompt = intercept_rec.get('systemPrompt', '')
    if system_prompt:
        parts.append(f"[SYSTEM]\n{system_prompt}")
    
    # 2. History Messages
    for hmsg in intercept_rec.get('historyMessages', []):
        role = hmsg.get('role', '')
        content = hmsg.get('content', '')
        text = extract_text_content(content)
        
        if role == 'user':
            parts.append(f"[USER]\n{text}")
        elif role == 'assistant':
            assistant_parts = []
            thinking = extract_thinking(content)
            tool_calls = extract_tool_calls(hmsg)
            
            if thinking:
                assistant_parts.append(f"[THINKING]\n{thinking}")
            if tool_calls:
                names = [tc.get('name', 'unknown') for tc in tool_calls]
                assistant_parts.append(f"[TOOL_CALLS]\n{', '.join(names)}")
            if text:
                assistant_parts.append(f"[TEXT]\n{text}")
            
            if assistant_parts:
                parts.append(f"[ASSISTANT]\n" + "\n".join(assistant_parts))
        elif role == 'tool':
            tool_name = hmsg.get('name', 'unknown')
            parts.append(f"[TOOL_RESULT: {tool_name}]\n{text}")
    
    # 3. Current Prompt
    current_prompt = intercept_rec.get('prompt', '')
    if current_prompt:
        parts.append(f"[USER]\n{current_prompt}")
    
    return "\n\n".join(parts)
```

### 8.3 Turn 聚合

```python
def aggregate_turns(messages):
    """
    将消息聚合为用户轮次
    """
    turns = {}
    
    for msg in messages:
        user_turn = msg.get('user_turn', 0)
        
        if user_turn not in turns:
            turns[user_turn] = {
                'user_prompt': msg.get('user_prompt', ''),
                'input_tokens': 0,
                'output_tokens': 0,
                'api_calls': 0,
                'tool_calls': 0,
                'calls': []
            }
        
        turns[user_turn]['input_tokens'] += msg.get('input_tokens', 0)
        turns[user_turn]['output_tokens'] += msg.get('output_tokens', 0)
        turns[user_turn]['api_calls'] += 1
        turns[user_turn]['tool_calls'] += msg.get('tool_calls', 0)
        turns[user_turn]['calls'].append(msg)
    
    return turns
```

---

## 附录：文件位置

```
~/.openclaw/
├── agents/main/
│   └── sessions/
│       └── main.jsonl          # Session 数据
├── workspace/
│   ├── model_intercept/
│   │   └── main_2026-03-19.jsonl  # Intercept 数据
│   └── model_dumps/            # 导出目录
└── skills/model-dumper/
    ├── scripts/model-dumper    # 主脚本
    ├── versions/               # 版本备份
    └── CHANGELOG.md            # 版本历史
```

---

**文档版本**: v0.1  
**更新日期**: 2026-03-19  
**维护者**: OpenClaw User
