# model-dumper 版本历史

## V0.9 (2026-03-23)

### Bug 修复

**`export-simple` 导出数据不完整的问题**

问题描述：
1. 部分轮没有按照每轮分别导出所有输入输出数据
2. 将一个 turn 的多个 calls 数据合并在一起
3. 只有 assistant/thinking/text 数据，缺少 system 数据
4. 个别轮显示 "Session-based entry - full input not captured"

原因分析：
- V0.7 版本的 `export_simple_jsonl` 只导出 intercept 文件中的条目
- Intercept 只捕获了部分 LLM 调用（如 16 条）
- Session 文件中有更多 assistant 消息（如 78 条）
- 导致大部分数据丢失

解决方案：
1. **以 session 消息为基础**：每条 assistant 消息 = 一次 LLM 调用 = 一条导出记录
2. **从 session 重建完整 input**：对每条 assistant 消息，重建其完整的输入（system + 所有历史消息）
3. **使用 intercept 获取 system prompt**：从 intercept 文件读取 system prompt

### 验证结果

```
修复前（V0.7）：
- Intercept entries: 16
- Session assistant messages: 78
- Exported entries: 15（只有 intercept 中的条目）

修复后（V0.9）：
- Session assistant messages: 78
- Exported entries: 78（每条 assistant 消息对应一条）
- All entries have complete input (system + user content)
- Input length grows with conversation: 42,666 → 550,053 chars
```

### 导出格式

每条记录包含：
```json
{
  "timestamp": 1774230021757,
  "ts_human": "2026-03-23T01:40:21.757+00:00",
  "input": "[SYSTEM]\n<system prompt>\n\n[USER]\n<user message>\n\n[TOOL_RESULT]\n<tool result>...",
  "output": "[THINKING]\n<thinking>\n\n[TOOL_CALLS]\n<tool names>\n\n[TEXT]\n<response>",
  "input_tokens": 16007,
  "output_tokens": 576,
  "stop_reason": "toolUse",
  "model": "..."
}
```

## V0.8 (2026-03-19)

### 新增功能

**Timing 指标统计（TTFT、TPOT、Total Time）**

添加了 LLM 响应时间的统计功能，包括：

1. **model-intercept 插件升级** (v1.1.0)
   - 新增 `requestStartTime` 字段：记录请求发送时间
   - 新增 `timing` 对象：包含 ttft、tpot、totalTime 等字段
   - 新增 `timingSource` 字段：标识数据来源

2. **model-dumper 增强**
   - `export-simple` JSONL 新增 `timing` 对象
   - `token-export` CSV 新增 TPOT 列

### Timing 指标

| 指标 | 可用性 | 计算方法 |
|------|--------|----------|
| **TTFT** | ❌ N/A | OpenRouter 不暴露 |
| **TPOT** | ✅ 可计算 | `call_duration / output_tokens` |
| **Total Time** | ✅ 可计算 | `messageTimestamp - requestStartTime` |
| **Prefill** | ❌ N/A | OpenRouter 不暴露 |
| **Decode** | ❌ N/A | OpenRouter 不暴露 |

### JSONL 新增字段

```json
{
  "timing": {
    "total_time_ms": 15234,
    "tpot_ms": 31.74,
    "ttft_ms": null,
    "prefill_ms": null,
    "decode_ms": null
  }
}
```

### CSV 新增列

**per-call CSV**:
- `TPOT (ms/token)` - Time Per Output Token
- `TTFT (ms)` - 标记为 "-"（不可用）
- `Prefill (ms)` - 标记为 "-"（不可用）
- `Decode (ms)` - 标记为 "-"（不可用）
- `Note` - 说明文本

**per-turn CSV**:
- `Avg TPOT (ms/token)` - 该轮平均 TPOT

### 技术原理

由于 OpenRouter API 不暴露 TTFT、Prefill、Decode 时间：
- TTFT 需要在客户端拦截流式响应的第一个 chunk
- TPOT 通过消息间隔时间估算：`TPOT = Call Duration / Output Tokens`
- Total Time 通过时间戳差值计算

### 文档更新

- `docs/TECHNICAL_PRINCIPIES.md` 新增 **第 4 节：Timing 指标统计**
- 更新版本号至 v0.8

## V0.7 (2026-03-19)

### Bug 修复

**`export-simple` 导出的 input_tokens 全部为 0 的问题**

问题：运行 `export-simple` 导出的 JSONL 文件中，所有条目的 `input_tokens` 均为 0，无法准确统计 token 使用。

原因：
- Intercept 数据包含完整的 input 文本（systemPrompt + historyMessages + prompt），但**没有 token counts**
- Session 数据包含精确的 `usage.input/output`，但内容**不完整**（缺少约 20-30% 的 tool results）
- 原代码从 Intercept 读取 input，但没有获取到准确的 token counts

### 解决方案

使用**内容相似度匹配**合并两个数据源：

1. **Input 内容** → 从 Intercept 读取（完整）
2. **Token counts** → 从 Session 读取（精确）

### 新增功能

**`match_intercept_to_session()` 函数** (行 508-550)

```python
def match_intercept_to_session(intercept_entries, session_messages, threshold=0.7):
    """用内容相似度匹配 Intercept 和 Session 条目"""
    # 使用 difflib.SequenceMatcher 比较用户消息内容
    # 相似度 >= 0.7 时匹配
```

### 修改内容

**`export_simple_jsonl()` 函数重构** (行 691-755)

1. 先调用 `match_intercept_to_session()` 进行匹配
2. 对每个 Intercept 条目：
   - 从 Intercept 获取完整 input
   - 从匹配的 Session 获取精确的 `input_tokens` 和 `output_tokens`

### 验证结果

```
修复前:
Loaded 13 intercept entries
input_tokens: 0 (全部)

修复后:
Loaded 13 intercept entries from latest file
Loaded 752 session messages
Matching intercept entries to session messages...
Matched 13 intercept entries to session messages
Exported 13 entries to ...

input_tokens: 15571, 15718, 21155... (正确)
```

### 数据对比

| 数据源 | Input 完整性 | Token Counts | 可靠性 |
|--------|-------------|--------------|--------|
| Intercept | 100% (system + history + prompt) | ❌ 无 | 内容准确 |
| Session | ~70-80% (部分 tool results 缺失) | ✅ 精确 | tokens 准确 |
| 新导出 | 100% | ✅ 精确 | ✅ 两全其美 |

## V0.6 (2026-03-19)

### Bug 修复

**token-export 输出 0 API calls 的问题**

问题：运行 `bash scripts/model-dumper token-export <session>` 输出 "Exported 0 API calls"，但实际有 4 个 API calls。

原因：`parse_timestamp` 函数在 Python 代码中定义在调用之后。当 Python 从 heredoc (`<<'PYEOF'`) 读取时逐行执行，`except: pass` 静默捕获了 NameError。

修复：将 `parse_timestamp` 函数定义移到调用之前。

### 验证结果
```
# 修复前
Exported 0 API calls to: *_token_stats_calls.csv

# 修复后
Exported 4 API calls to: *_token_stats_calls.csv
```

### CSV 输出内容（验证通过）
- Call#: 1-4
- Input/Output Tokens: 正确
- Call Duration (s): 9.5s, 7.6s, 4.4s, 8.8s
- System Prompt Category 分解: Workspace_Files, Tool_List, Skills 等 13 个类别
- User Prompt 截断: 正常显示

## V0.5 (2026-03-19)

### `token-stats` 新增统计

1. **System Prompt 详细分解**
   - 按 Section 分解（100个section）
   - 按 Category 分解（Skills, Tooling, Heartbeats, Memory 等）
   - 显示每个 Section 的 Token 数和占比

2. **Duration 统计**
   - 每轮 Duration (秒)
   - 总 Duration
   - 每次 API 调用之间的时间间隔

### `token-export` CSV 新增

1. **per-turn CSV 新增列**:
   - `Duration (s)` - 每轮执行时间
   - System Prompt 按 Category 分解的 Token 数

2. **新增 CSV 文件**:
   - `*_system_breakdown.csv` - System Prompt 按 Section 分解

### CSV 列结构
```
Turn, API Calls, Total Input, Total Output, Total Tokens, Cache Read, Cache Write,
Tool Calls, First Input, Last Input, Context Growth, Duration (s), System Chars,
System Tokens (est), Core, Group Chats, Heartbeats, Memory, Meta, Other,
Search, Skills, Task Tracing, Tooling, Workflow, Workspace, User Prompt
```

## V0.4 (2026-03-19)

### 导出格式重大升级

#### JSONL 导出 (`export`)
新的 `input` 结构包含完整的消息历史：
```json
{
  "input": {
    "messages": [
      {"role": "system", "content": "..."},
      {"role": "user", "content": "..."},
      {"role": "assistant", "content": "...", "toolCalls": [...]},
      {"role": "tool", "toolName": "...", "content": "..."},
      {"role": "assistant", "content": "..."},
      ...
    ],
    "system_prompt": "...(完整system prompt)...",
    "system_tokens_est": 11705,
    "message_count": 13
  },
  "output": {...},
  "token_usage": {"input": 15571, "output": 480, ...},
  "stop_reason": "stop"
}
```

#### CSV 统计表新增列
- `System Chars` - System prompt 字符数
- `System Tokens (est)` - System prompt 估算 token 数
- 同时导出 `*_system_prompt.txt` 完整 system prompt 文本文件

### 修复
- `export` 现在包含完整的 system prompt
- 消息按 role 区分：system, user, assistant, tool
- CSV 统计表包含 system prompt 相关列

## V0.3 (2026-03-19)

### 重大改进
- **更新 model-intercept 插件** - 从 `before_prompt_build` 改为 `llm_input` hook
  - 现在能捕获完整的 system prompt（之前为空）
  - system prompt 现在包含完整的工具定义和上下文
  - `prompt-breakdown` 优先从 intercept 数据读取

### 修复
- `prompt-breakdown` 现在能正确读取完整的 system prompt（40969 chars）
- 之前只能从 sessions.json 读取部分 skillsSnapshot.prompt

### 技术细节
- OpenClaw `llm_input` hook 提供完整数据：
  - `systemPrompt` - 完整系统提示文本
  - `historyMessages` - 历史消息数组
  - `prompt` - 当前用户输入

## V0.2 (2026-03-19)

### 新增功能
- `prompt-breakdown` - System Prompt 分解分析
  - 从 sessions.json 读取 skillsSnapshot.prompt
  - 按 `# Project Context`, `## Tooling`, `## Silent Replies` 等分段
  - 显示每个部分的字符数和估算 Token 数
  - 显示 tool overlap 分析（system prompt vs body.tools）
  - 支持 `--json` 输出 JSON 格式

### 修复
- `export` 导出 JSONL 现在包含 `toolResults` 字段

## V0.1 (2026-03-18)

### 功能
- `analyze` - 会话统计分析
- `dump` - 完整会话导出
- `rounds` - 交互轮次统计
- `prompts` - 显示所有发送的 prompt
- `outputs` - 显示模型输出
- `latest` - 显示最新会话 ID
- `export` - 导出到 JSONL 文件
- `intercept` - 显示拦截的 LLM 调用
- `export-full` - 导出含系统提示的完整数据
- `system-prompt` - 显示重建的系统提示
- `token-stats` - 每轮 Token 统计（包含每次 API 调用）
- `token-stats-all` - 所有会话 Token 统计
- `token-export` - Token 统计导出为 CSV

### JSONL 导出格式 (export)
```json
{
  "timestamp": 1773839233748,
  "input": "[USER]\n...",
  "output": "<thinking>...\n...",
  "output_full": {
    "thinking": "...",
    "text": "...",
    "toolCalls": [
      {"name": "tool_name", "id": "...", "arguments": {...}}
    ],
    "toolResults": [
      {"text": "...", "raw_content": [...]}
    ],
    "raw_content": [...]
  },
  "token_usage": {
    "input": 15193,
    "output": 336,
    "total": 15529
  },
  "model": "stepfun/step-3.5-flash:free",
  "stop_reason": "toolUse"
}
```

### CSV 导出格式
- `*_token_stats_calls.csv` - 每次 API 调用详情
- `*_token_stats.csv` - 每轮汇总

### 已知限制
- Cache 命中率统计需要模型支持（当前 step-3.5-flash:free 不支持）
- Token 分解为估算值（4字符 ≈ 1 Token）
- System Prompt 为估算值

## 文件结构
```
model-dumper/
├── SKILL.md
├── manifest.json
├── scripts/
│   └── model-dumper          # 当前版本 (v0.7)
└── versions/
    ├── CHANGELOG.md          # 版本历史
    ├── model-dumper.v0.1.sh
    ├── model-dumper.v0.2.sh
    ├── model-dumper.v0.3.sh
    ├── model-dumper.v0.4.sh
    ├── model-dumper.v0.5.sh
    ├── model-dumper.v0.6.sh
    └── model-dumper.v0.7.sh  # 最新版本
```

---

## 版本更新规范

每次修改代码后，必须执行以下步骤：

### 1. 更新版本号
```bash
# 备份当前版本
cp scripts/model-dumper versions/model-dumper.v0.N.sh

# 更新 manifest.json 中的版本号
# 例如: "version": "0.7.0" → "version": "0.8.0"
```

### 2. 更新 CHANGELOG.md
在文件顶部添加新的版本块：

```markdown
## V0.N (YYYY-MM-DD)

### 新增功能 / Bug 修复 / 优化

**问题描述**（如适用）
- 问题：xxx
- 原因：xxx

**解决方案**
- xxx

### 修改内容
- xxx (具体修改)

### 验证结果
```
# 修复前
xxx

# 修复后
xxx
```
```

### 3. 版本号规则
- **PATCH** (0.7.0 → 0.7.1): 小修复、文档更新
- **MINOR** (0.7.0 → 0.8.0): 新增功能、重大改进
- **MAJOR** (0.7.0 → 1.0.0): 破坏性变更

### 4. 提交规范
```
[model-dumper] v0.N - 新增 xxx / 修复 xxx
```
