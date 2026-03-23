#!/bin/bash
# 分析 raw-stream.jsonl 来计算 TTFT 和 TPOT

RAW_STREAM_FILE="${1:-/home/bob/.openclaw/logs/raw-stream.jsonl}"

echo "=== Raw Stream Timing Analysis ==="
echo "File: $RAW_STREAM_FILE"
echo ""

# 统计每个 runId 的 timing
echo "最近 10 个 LLM 调用的 Timing 统计："
echo "-----------------------------------------------"
echo "RunId                          | TTFT (ms) | Total (ms) | Events | Text Chars"
echo "-------------------------------|-----------|-------------|--------|-----------"

cat "$RAW_STREAM_FILE" | jq -c '
  select(.event | contains("assistant_")) | 
  { runId: .runId, ts: .ts, event: .event, evtType: .evtType }
' 2>/dev/null | jq -s '
group_by(.runId) | 
map(
  {
    runId: .[0].runId,
    firstTs: (.[0].ts),
    lastTs: (.[-1].ts),
    totalMs: (.[-1].ts - .[0].ts),
    eventCount: length
  }
) | 
sort_by(-.firstTs) | 
.[0:10] |
.[] |
"\(.runId[0:8])... | \(.firstTs | tostring | .[0:0]) | \(.totalMs)ms | \(.eventCount) | \(.lastTs - .firstTs)"
' 2>/dev/null | while IFS='|' read -r id ttft total events; do
    printf "%s %11s %11s %7s\n" "$id" "$ttft" "$total" "$events"
done

echo ""
echo "=== Timing 指标说明 ==="
echo "TTFT (Time To First Token): 首次流式响应时间 (ms)"
echo "Total: 总生成时间 (ms)"
echo "TPOT (Time Per Output Token): 每输出 token 时间 = Total / token_count"
echo ""
echo "注意: TTFT 是客户端测量的首 token 时间，包含网络延迟"
echo "      纯 LLM TTFT 需要服务端埋点才能准确获取"
