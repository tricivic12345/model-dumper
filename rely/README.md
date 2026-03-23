# 依赖工具 (rely)

这个目录包含 model-dumper 的辅助工具和依赖文件。

## 📁 文件说明

### `analyze-raw-stream.sh`

**用途**: 分析 `raw-stream.jsonl` 日志，计算 TTFT 和 TPOT 等时间指标

**依赖**:
- `jq` - JSON 命令行处理器
- OpenClaw 的 raw-stream 日志文件（默认: `~/.openclaw/logs/raw-stream.jsonl`）

**使用方法**:
```bash
# 分析默认 raw-stream 文件
./analyze-raw-stream.sh

# 指定 raw-stream 文件路径
./analyze-raw-stream.sh /path/to/raw-stream.jsonl

# 查看最近 10 个 LLM 调用的 timing 统计
```

**输出示例**:
```
=== Raw Stream Timing Analysis ===
File: /home/bob/.openclaw/logs/raw-stream.jsonl

最近 10 个 LLM 调用的 Timing 统计：
----------------------------------------------------------------
RunId                          | TTFT (ms) | Total (ms) | Events | Text Chars
-------------------------------|-----------|-------------|--------|-----------
abc123...                      | 1250      | 3450        | 150    | 2500
def456...                      | 980       | 2890        | 120    | 2100
```

### `env.sh`

**用途**: 设置 model-dumper 的环境变量（目前只定义了 `SESSIONS_DIR`）

**使用方法**:
```bash
# 在运行 model-dumper 前 source 此文件（可选）
source ./rely/env.sh

# 它会设置：
# export SESSIONS_DIR="${OPENCLAW_AGENT_DIR:-$HOME/.openclaw/agents/main}/sessions"
```

**注意**: 主脚本 `model-dumper` 内部已经硬编码了这些路径，通常不需要单独 source 此文件。

## 📦 系统依赖

运行这些工具需要以下系统命令：

| 工具 | 用途 | 安装命令 |
|------|------|----------|
| `python3` | 运行主脚本的分析逻辑 | 通常预装 |
| `jq` | 分析 raw-stream JSON 日志 | `apt install jq` / `brew install jq` |

### 检查依赖

```bash
# 检查 python3
python3 --version

# 检查 jq
jq --version
```

### 安装 jq

**Ubuntu/Debian**:
```bash
sudo apt update && sudo apt install jq
```

**macOS**:
```bash
brew install jq
```

**CentOS/RHEL/Fedora**:
```bash
sudo yum install jq
# 或
sudo dnf install jq
```

## 🎯 与主脚本的关系

- **主脚本** `scripts/model-dumper` 是核心工具，不依赖 `rely/` 目录中的文件
- **rely/** 目录包含的是**可选辅助工具**，用于高级分析（如 raw-stream timing）
- 主脚本已经内嵌了所有核心功能，可以独立运行

## 📖 相关文档

- 主 README.md: 完整使用指南
- SKILL.md: OpenClaw 技能定义
- docs/TECHNICAL_PRINCIPLES.md: 技术原理

---

**版本**: 1.0.0
**更新**: 2026-03-23
