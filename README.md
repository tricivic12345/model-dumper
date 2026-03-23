# model-dumper

> Dump and analyze OpenClaw model interactions - Export to JSONL, CSV, and detailed token statistics

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![OpenClaw](https://img.shields.io/badge/OpenClaw-skill-ff6b6b)](https://openclaw.ai)

## 📋 Overview

`model-dumper` 是一个 OpenClaw 技能，用于导出和分析模型交互数据。它能够：

- 📊 **统计交互轮次和 Token 使用**
- 📄 **导出完整对话历史到 JSONL**
- 💾 **导出 Token 统计到 CSV**（按调用和按轮次）
- 🔍 **捕获系统提示词**（自动重建）
- ⏱️ **分析时间指标**（TTFT, TPOT, 生成时间）
- 📈 **缓存命中率分析**

## 🚀 快速开始

### 安装

```bash
# 如果使用 clawhub
clawhub install model-dumper

# 或者手动复制到 ~/.openclaw/workspace/skills/
git clone https://github.com/tricivic12345/model-dumper ~/.openclaw/workspace/skills/model-dumper
```

### 基本用法

```bash
# 进入技能目录
cd ~/.openclaw/workspace/skills/model-dumper/scripts

# 分析当前会话（交互次数、Token 总数、缓存命中率等）
./model-dumper analyze

# 导出交互数据到 JSONL（默认输出到 ~/.openclaw/workspace/model_dumps/）
./model-dumper export

# 导出包含系统提示词的完整数据
./model-dumper export-full

# 导出简化的交互数据（适合快速处理）
./model-dumper export-simple

# 导出 Token 统计到 CSV（3个文件：调用详情、轮次摘要、系统分解）
./model-dumper token-export

# 查看最新会话 ID
./model-dumper latest

# 显示重建的系统提示词
./model-dumper system-prompt
```

## 📊 输出文件

运行 `export` 和 `token-export` 后，文件会保存在 `~/.openclaw/workspace/model_dumps/` 目录：

```
model_dumps/
├── {session_id}.jsonl                      # 完整交互数据（带结构）
├── {session_id}_simple.jsonl               # 简化交互数据（扁平格式）
├── {session_id}_token_stats_calls.csv      # 每次 API 调用的详细统计
├── {session_id}_token_stats.csv            # 按用户轮次聚合的统计
├── {session_id}_token_stats_system_breakdown.csv  # 系统提示词分解
└── {session_id}_system_prompt.txt          # 完整的系统提示词文本
```

### JSONL 格式说明

#### 完整格式 (`export` / `export-full`)

```json
{
  "timestamp": 1774230021757,
  "call_num": 1,
  "input": {
    "messages": [
      {"role": "system", "content": "..."},
      {"role": "user", "content": "..."}
    ]
  },
  "output": {
    "message": "...",
    "tool_calls": [...]
  },
  "token_usage": {
    "input": 16007,
    "output": 576,
    "total": 16583,
    "cacheRead": 0,
    "cacheWrite": 0
  },
  "model": "stepfun/step-3.5-flash:free",
  "provider": "openrouter",
  "stop_reason": "toolUse",
  "timing": {
    "total_time_ms": 5973,
    "tpot_ms": 10.37
  }
}
```

#### 简化格式 (`export-simple`)

```json
{
  "timestamp": 1774230015780,
  "ts_human": "2026-03-23T01:40:15.780000",
  "input": "[SYSTEM] ... [USER] ...",
  "output": "[THINKING] ... [TEXT] ...",
  "input_tokens": 16007,
  "output_tokens": 576,
  "stop_reason": "toolUse",
  "model": "stepfun/step-3.5-flash:free"
}
```

### CSV 格式说明

**`*_token_stats_calls.csv`** - 每次 API 调用详情

| 列名 | 说明 |
|------|------|
| Call# | 调用序列号 |
| Turn | 用户轮次 |
| Input Tokens | 输入 Token 数 |
| Output Tokens | 输出 Token 数 |
| Total Tokens | 总 Token 数 |
| Cache Read | 缓存读取 Token |
| Cache Write | 缓存写入 Token |
| Tool Calls | 工具调用数量 |
| Tool Names | 调用的工具列表 |
| Stop Reason | 停止原因（stop/toolUse/...） |
| LLM Time (s) | LLM 执行时间 |
| TPOT Session (ms/token) | 每输出 token 耗时 |
| Generation Time (ms) | 生成时间（来自 raw-stream） |
| TTFT (ms) | 首 token 到达时间 |
| User Prompt (truncated) | 用户提示词（截断） |

**`*_token_stats.csv`** - 按轮次聚合

| 列名 | 说明 |
|------|------|
| Turn | 轮次号 |
| Calls | 该轮次 API 调用次数 |
| Total Input | 输入 Token 总和 |
| Total Output | 输出 Token 总和 |
| Growth | 上下文增长（Last In - First In） |
| Duration (s) | 该轮次总时长 |

**`*_token_stats_system_breakdown.csv`** - 系统提示词分解

| 列名 | 说明 |
|------|------|
| Section | 组件名称（SOUL.md, USER.md, AGENTS.md, Skills等） |
| Category | 分类（Core_Identity, Memory_History, Tool_List等） |
| Chars | 字符数 |
| Tokens | Token 数 |
| First Input Pct | 占首次输入的百分比 |

## 🔧 高级用法

### 导出指定会话

```bash
# 先获取会话ID
./model-dumper latest

# 导出该会话
./model-dumper export rest-api-dev

# 导出 Token 统计到指定文件
./model-dumper token-stats rest-api-dev /tmp/stats.txt
```

### 分析所有会话

```bash
# 导出所有会话的 Token 统计
./model-dumper token-stats-all
```

### 查看拦截的 LLM 调用

```bash
# 显示拦截的原始 API 请求/响应
./model-dumper intercept
```

### 查看会话中的轮次数

```bash
./model-dumper rounds
```

## 📈 指标解读

### 性能指标

- **TTFT (Time To First Token)**: 从请求发送到收到第一个 token 的时间
  - 目标: < 2000ms
  - 高值可能表示网络延迟或模型加载慢

- **TPOT (Time Per Output Token)**: 每输出一个 token 的平均耗时
  - 目标: < 20ms/token (decode-only)
  - 实际包含 prefill 阶段，通常更高

- **Cache Hit Rate**: 缓存命中率
  - 高值（>95%）说明系统提示词稳定
  - 低值表示系统提示词频繁变化

### Token 分析

- **System Tokens / First Input %**: 系统提示词占首次输入的比例
  - 建议 < 20%
  - 过高可能表示系统提示词过长

- **Context Growth**: 每轮对话的 token 增长
  - 如果连续增长过快，需要优化记忆管理

## 📁 项目结构

```
model-dumper/
├── SKILL.md              # 技能定义（OpenClaw 使用）
├── README.md             # 本文档
├── manifest.json         # 技能清单
├── scripts/
│   ├── model-dumper      # 主程序（bash）
│   └── analyze-raw-stream.sh  # 分析原始流数据
├── versions/             # 版本历史
│   ├── CHANGELOG.md
│   ├── model-dumper.v*.sh  # 各版本实现
│   └── model-intercept.v*.ts
├── docs/
│   └── TECHNICAL_PRINCIPLES.md  # 技术原理
└── env.sh                # 环境变量配置
```

## 🔍 数据来源

该技能从以下位置读取数据：

- **会话文件**: `~/.openclaw/agents/main/sessions/*.jsonl`
- **流式日志**: `~/.openclaw/logs/raw-stream.jsonl`
- **拦截数据**: `~/.openclaw/workspace/model_intercept/*.jsonl`
- **工作空间**: `~/.openclaw/workspace/` (用于重建系统提示词)

系统提示词由以下文件动态重建：

1. `SOUL.md` - AI 身份/个性
2. `USER.md` - 用户信息
3. `AGENTS.md` - 工作空间上下文
4. `MEMORY.md` - 长期记忆
5. `memory/YYYY-MM-DD.md` - 近期记忆
6. `skills/` - 已安装技能的快照

## 🛠️ 开发与测试

### 运行测试

```bash
# 分析当前会话（示例）
./model-dumper analyze

# 导出数据并验证格式
./model-dumper export
head -n 1 ~/.openclaw/workspace/model_dumps/*.jsonl | python3 -m json.tool
```

### 贡献

欢迎提交 Issue 和 Pull Request！

1. Fork 本仓库
2. 创建特性分支
3. 提交更改
4. 推送到分支
5. 开启 Pull Request

## 📄 许可证

MIT License - 详见 [LICENSE](LICENSE) 文件

## 🙏 致谢

- [OpenClaw](https://openclaw.ai) - 强大的 AI 助手平台
- 所有贡献者

---

## 📚 版本历史与可获取性

### 当前版本

- **最新版本**: v0.9.0 (2026-03-23)
- **主分支**: `main`
- **推荐安装方式**: 克隆最新版本

### 历史版本

所有历史版本都已通过 Git tag 保存，你可以 checkout 任意历史版本：

```bash
# 克隆仓库
git clone https://github.com/tricivic12345/model-dumper
cd model-dumper

# 查看所有版本标签
git tag -l

# 切换到某个历史版本（例如 v0.8）
git checkout v0.8.0

# 使用该版本
./scripts/model-dumper analyze
```

**可用版本标签**:
- `v0.9.0` - 修复 export-simple 数据不完整问题（当前）
- `v0.8.0` - 添加时间指标统计（TTFT/TPOT）
- `v0.7.0` - 修复 export-simple token counts 为 0 的问题
- `v0.6.0` - 修复 token-export 输出 0 API calls 的问题
- `v0.5.0` - 增强 token-stats 系统提示词分解
- `v0.4.0` - JSONL 导出格式升级（完整消息历史）
- `v0.3.0` - 更新 model-intercept 插件（捕获完整 system prompt）
- `v0.2.0` - 新增 prompt-breakdown 功能
- `v0.1.0` - 初始版本

详细版本变更内容请参阅 [CHANGELOG.md](CHANGELOG.md)。

### 版本选择建议

| 版本 | 适用场景 | 推荐度 |
|------|---------|--------|
| v0.9.0+ | 需要完整的 export-simple 数据 | ✅ 最新 |
| v0.8.0+ | 需要时间指标统计（TPOT） | ✅ |
| v0.7.0+ | 修复了 export-simple token 统计 | ✅ |
| v0.6.0+ | 修复了 token-export 导出问题 | ✅ |
| v0.5.0+ | 需要系统提示词分解 | ✅ |
| < v0.5.0 | 旧版本（不建议） | ⚠️ |

### 版本管理

我们使用 **Git tag** 管理版本，每个 tag 对应一个发布版本：

```bash
# 查看版本差异
git log --oneline --graph --all

# 比较两个版本
git diff v0.8.0 v0.9.0

# 查看某个 tag 的详细信息
git show v0.9.0
```

---

**维护者**: [tricivic12345](https://github.com/tricivic12345)
**文档版本**: 1.0.0
**最后更新**: 2026-03-23
