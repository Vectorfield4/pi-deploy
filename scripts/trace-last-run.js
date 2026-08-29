// trace-last-run.js — extract metrics for the most recent user task in
// the active Pi session. Run inside pi-agent container.
//
// Usage: node /tmp/trace-last-run.js
// Output: writes /root/pi-deploy/trace-logs/<id>.json + .md
"use strict";
const fs = require("node:fs");
const path = require("node:path");

const SESS_ROOT = "/root/.pi/agent/sessions/--workspace--";
const SUB_ROOT = "/tmp/pi-subagents-uid-0";
const OUT_DIR = "/workspace/trace-logs";

function stat(p) { try { return fs.statSync(p); } catch { return null; } }
function readJson(p) { try { return JSON.parse(fs.readFileSync(p, "utf8")); } catch { return null; } }
function readText(p) { try { return fs.readFileSync(p, "utf8"); } catch { return ""; } }

function findActiveSession() {
  // Recursive: session.jsonl lives at <root>/<ISO-time>_<sessId>/<runId>/run-0/session.jsonl
  const out = [];
  function walk(d, depth) {
    if (depth > 5) return;
    let entries;
    try { entries = fs.readdirSync(d, { withFileTypes: true }); } catch { return; }
    for (const e of entries) {
      const p = path.join(d, e.name);
      if (e.isDirectory()) walk(p, depth + 1);
      else if (e.isFile() && e.name === "session.jsonl" && p.endsWith("/run-0/session.jsonl")) {
        const st = stat(p);
        if (st) out.push({ path: p, mtime: st.mtime, size: st.size });
      }
    }
  }
  walk(SESS_ROOT, 0);
  out.sort((a, b) => b.mtime - a.mtime);
  if (!out.length) return null;
  return { path: out[0].path, mtime: out[0].mtime, size: out[0].size };
}

function walkJsonl(file) {
  const out = [];
  for (const ln of readText(file).split("\n")) {
    if (!ln) continue;
    try { out.push(JSON.parse(ln)); } catch {}
  }
  return out;
}

function shapeSession(records) {
  // records: array of {type, ...}
  const r = {
    startedAt: null,
    model: null,
    thinkingLevel: null,
    sessionInfo: null,
    messages: [], // { role, ts, content (truncated), tool_calls (names), tool_results (names) }
    totals: {
      assistant_turns: 0,
      user_turns: 0,
      tool_calls: 0,
      tool_results: 0,
      in_tokens: 0,
      out_tokens: 0,
      cache_read_tokens: 0,
      cache_write_tokens: 0,
      cost_usd: 0,
    },
    last_turn: null,
  };
  for (const rec of records) {
    if (rec.type === "session") { r.startedAt = rec.timestamp; continue; }
    if (rec.type === "session_info") { r.sessionInfo = rec; continue; }
    if (rec.type === "model_change") { r.model = `${rec.provider}/${rec.modelId}`; continue; }
    if (rec.type === "thinking_level_change") { r.thinkingLevel = rec.thinkingLevel; continue; }
    if (rec.type === "message") {
      const m = rec.message;
      if (!m) continue;
      const ts = rec.timestamp;
      const role = m.role;
      const content = m.content;
      let toolCalls = 0; let toolResults = 0;
      let toolCallNames = []; let toolResultNames = [];
      let textSnippet = "";
      const sumUsage = (u) => {
        if (!u) return;
        const n = (a, v) => (typeof v === "number" ? a + v : a);
        r.totals.in_tokens = n(r.totals.in_tokens, u.input_tokens ?? u.input);
        r.totals.out_tokens = n(r.totals.out_tokens, u.output_tokens ?? u.output);
        r.totals.cache_read_tokens = n(r.totals.cache_read_tokens, u.cache_read_tokens ?? u.cacheRead ?? 0);
        r.totals.cache_write_tokens = n(r.totals.cache_write_tokens, u.cache_write_tokens ?? u.cacheWrite ?? 0);
        r.totals.cost_usd = n(r.totals.cost_usd, u.cost_usd ?? (u.cost && u.cost.total) ?? 0);
      };
      if (Array.isArray(content)) {
        for (const c of content) {
          if (!c) continue;
          if (c.type === "text" && !textSnippet) textSnippet = String(c.text || "").slice(0, 240);
          if (c.type === "toolCall") {
            toolCalls++;
            toolCallNames.push(c.name || c.toolName || "?");
          }
          if (c.type === "toolResult") {
            toolResults++;
            const n = c.toolName || (c.toolCall && c.toolCall.name) || "?";
            toolResultNames.push(n);
          }
        }
        if (m.usage) sumUsage(m.usage);
      } else if (typeof content === "string") {
        textSnippet = content.slice(0, 240);
      }
      if (role === "assistant") {
        r.totals.assistant_turns++;
        if (m.usage) sumUsage(m.usage);
        if (m.message?.usage) sumUsage(m.message.usage);
      } else if (role === "user") {
        r.totals.user_turns++;
      }
      r.totals.tool_calls += toolCalls;
      r.totals.tool_results += toolResults;
      r.messages.push({
        role, ts,
        text: textSnippet,
        tool_calls: toolCallNames,
        tool_results: toolResultNames,
        usage: m.usage || null,
      });
    }
  }
  for (let i = r.messages.length - 1; i >= 0; i--) {
    if (r.messages[i].role === "user") { r.last_user_idx = i; break; }
  }
  const start = r.last_user_idx ?? 0;
  r.last_run = {
    user_message: r.messages[start] || null,
    turns: r.messages.slice(start),
  };
  return r;
}

function aggregateChildUsage(eventsPath) {
  // Sum cacheRead/cacheWrite/input/output over all message_end events.
  // Pi 0.58.x emits message_start/message_end with .message.usage.
  let inTok = 0, outTok = 0, cr = 0, cw = 0, cost = 0;
  let assistantMessages = 0, toolMessages = 0;
  const toolCalls = []; // { name, args preview }
  const firstThinking = []; // earliest thinking blocks (truncated)
  for (const ln of readText(eventsPath).split("\n")) {
    if (!ln) continue;
    let o; try { o = JSON.parse(ln); } catch { continue; }
    if (o.type === "message_end" && o.message) {
      const m = o.message;
      const u = m.usage;
      if (u) {
        inTok += u.input ?? u.input_tokens ?? 0;
        outTok += u.output ?? u.output_tokens ?? 0;
        cr += u.cacheRead ?? u.cache_read_tokens ?? 0;
        cw += u.cacheWrite ?? u.cache_write_tokens ?? 0;
        if (u.cost && typeof u.cost.total === "number") cost += u.cost.total;
        else if (typeof u.cost_usd === "number") cost += u.cost_usd;
      }
      if (m.role === "assistant") assistantMessages++;
      if (m.role === "toolResult") toolMessages++;
      if (Array.isArray(m.content)) {
        for (const c of m.content) {
          if (c?.type === "thinking" && firstThinking.length < 3) {
            firstThinking.push(String(c.thinking || "").slice(0, 400));
          }
          if (c?.type === "toolCall") {
            toolCalls.push({ name: c.name || c.toolName || "?", args: JSON.stringify(c.arguments || c.args || {}).slice(0, 160) });
          }
        }
      }
    } else if (o.type === "tool_execution_start") {
      toolCalls.push({ name: o.toolName, args: JSON.stringify(o.args || {}).slice(0, 160) });
    }
  }
  return { in_tokens: inTok, out_tokens: outTok, cache_read: cr, cache_write: cw, cost, assistant_messages: assistantMessages, tool_messages: toolMessages, tool_calls: toolCalls, first_thinking: firstThinking };
}

function findChildRuns(sinceMs) {
  const root = path.join(SUB_ROOT, "async-subagent-runs");
  if (!stat(root)) return [];
  const out = [];
  for (const id of fs.readdirSync(root)) {
    const dir = path.join(root, id);
    const p = path.join(dir, "status.json");
    const st = stat(p);
    if (!st) continue;
    if (st.mtimeMs < sinceMs - 60_000) continue;
    const data = readJson(p);
    if (!data) continue;
    // Aggregate per-run usage from events.jsonl
    const evp = path.join(dir, "events.jsonl");
    const usage = stat(evp) ? aggregateChildUsage(evp) : { in_tokens: 0, out_tokens: 0, cache_read: 0, cache_write: 0, cost: 0, tool_calls: [], first_thinking: [] };
    // Prefer the explicit totalTokens from status.json if present
    const tot = data.totalTokens || {};
    out.push({
      run_id: id,
      mtime: st.mtime.toISOString(),
      started_at: data.startedAt,
      ended_at: data.endedAt,
      duration_ms: data.endedAt ? (data.endedAt - data.startedAt) : null,
      state: data.state || data.status || "?",
      success: data.success,
      exit_code: data.exit_code ?? data.exitCode,
      agent: data.steps?.[0]?.agent,
      turn_count: data.turnCount,
      tool_count: data.toolCount,
      total_tokens: tot,
      total_cost: data.totalCost,
      aggregated_usage: usage,
      summary: (data.outputs?.summary || data.summary || "").slice(0, 600),
    });
  }
  out.sort((a, b) => a.mtime.localeCompare(b.mtime));
  return out;
}

function mdSummary(s) {
  const t = s.totals;
  const lines = [];
  lines.push(`# Trace ${s.session_dir}`);
  lines.push("");
  lines.push(`- started: ${s.startedAt || "?"}`);
  lines.push(`- model: ${s.model || "?"}`);
  lines.push(`- thinking: ${s.thinkingLevel || "?"}`);
  lines.push(`- session_mtime: ${s.session_mtime || "?"}`);
  lines.push(`- session_info: \`${JSON.stringify(s.sessionInfo || {}).slice(0, 200)}\``);
  lines.push("");
  lines.push("## Totals (cumulative across session, parsed from session.jsonl)");
  lines.push(`- user_turns: ${t.user_turns}`);
  lines.push(`- assistant_turns: ${t.assistant_turns}`);
  lines.push(`- tool_calls: ${t.tool_calls}`);
  lines.push(`- tool_results: ${t.tool_results}`);
  lines.push(`- in_tokens: ${t.in_tokens}`);
  lines.push(`- out_tokens: ${t.out_tokens}`);
  lines.push(`- cache_read: ${t.cache_read_tokens}`);
  lines.push(`- cache_write: ${t.cache_write_tokens}`);
  lines.push(`- cost_usd: ${t.cost_usd}`);
  lines.push("");
  if (s.last_run?.user_message) {
    lines.push("## Last user prompt");
    lines.push(`- ts: ${s.last_run.user_message.ts}`);
    lines.push(`- text: \`${(s.last_run.user_message.text || "").replace(/`/g, "")}\``);
    lines.push("");
    lines.push(`## Turns since last user prompt (${s.last_run.turns.length} msgs)`);
    for (const m of s.last_run.turns) {
      const tools = (m.tool_calls || []).join(",");
      const results = (m.tool_results || []).join(",");
      const u = m.usage ? ` in=${m.usage.input_tokens ?? m.usage.input} out=${m.usage.output_tokens ?? m.usage.output} cache_read=${m.usage.cache_read_tokens ?? m.usage.cacheRead}` : "";
      lines.push(`- ${m.ts} ${m.role}${tools ? " calls=[" + tools + "]" : ""}${results ? " results=[" + results + "]" : ""}${u}`);
      if (m.text) lines.push(`  > ${m.text.replace(/\n/g, " ").slice(0, 200)}`);
    }
  }
  if (s.children?.length) {
    lines.push("");
    lines.push(`## Child subagent runs (${s.children.length})`);
    for (const c of s.children) {
      lines.push(`### ${c.run_id} — ${c.agent || "?"} — ${c.state} (exit ${c.exit_code})`);
      lines.push(`- mtime: ${c.mtime}`);
      lines.push(`- duration_ms: ${c.duration_ms}`);
      lines.push(`- turn_count: ${c.turn_count} / tool_count: ${c.tool_count}`);
      lines.push(`- total_tokens (status.json): ${JSON.stringify(c.total_tokens || {})}`);
      lines.push(`- total_cost (status.json): ${JSON.stringify(c.total_cost || {})}`);
      const u = c.aggregated_usage || {};
      lines.push(`- aggregated from events.jsonl: in=${u.in_tokens} out=${u.out_tokens} cache_read=${u.cache_read} cache_write=${u.cache_write} cost=${u.cost}`);
      lines.push(`- assistant_messages=${u.assistant_messages} tool_messages=${u.tool_messages}`);
      if (u.tool_calls?.length) {
        lines.push(`- tool calls (${u.tool_calls.length}):`);
        for (const t of u.tool_calls.slice(0, 30)) lines.push(`    - ${t.name} ${t.args}`);
        if (u.tool_calls.length > 30) lines.push(`    - ... and ${u.tool_calls.length - 30} more`);
      }
      if (u.first_thinking?.length) {
        lines.push(`- first thinking (${u.first_thinking.length}):`);
        for (const th of u.first_thinking) lines.push(`    > ${th.replace(/\n/g, " ")}`);
      }
      if (c.summary) lines.push(`- summary: ${c.summary.replace(/\n/g, " ").slice(0, 500)}`);
    }
  }
  return lines.join("\n");
}

function main() {
  fs.mkdirSync(OUT_DIR, { recursive: true });
  const s = findActiveSession();
  if (!s) { console.error("no session found"); process.exit(1); }
  const sjl = s.path;
  const records = walkJsonl(sjl);
  const shaped = shapeSession(records);
  shaped.session_path = sjl;
  // session_dir is the directory two levels up: <root>/<iso>_<sessId>/<runId>/run-0/session.jsonl
  const parts = sjl.split("/");
  shaped.session_dir = parts.slice(-4, -1).join("/"); // ["<iso>_<sessId>","<runId>","run-0"]
  shaped.session_mtime = s.mtime.toISOString();
  // Children: only those newer than the last user message (or fallback to last 30 min)
  const since = shaped.last_run?.user_message?.ts
    ? Date.parse(shaped.last_run.user_message.ts)
    : (Date.now() - 30 * 60_000);
  shaped.children = findChildRuns(since);
  // Write
  const id = `${new Date().toISOString().replace(/[:.]/g, "-")}-${parts[parts.length - 3].slice(0, 8)}`;
  const jsonPath = path.join(OUT_DIR, `${id}.json`);
  const mdPath = path.join(OUT_DIR, `${id}.md`);
  fs.writeFileSync(jsonPath, JSON.stringify(shaped, null, 2));
  fs.writeFileSync(mdPath, mdSummary(shaped));
  const t = shaped.totals;
  console.log(`session: ${shaped.session_dir}`);
  console.log(`model: ${shaped.model}`);
  console.log(`last user @ ${shaped.last_run?.user_message?.ts || "?"}: ${(shaped.last_run?.user_message?.text || "").slice(0, 200).replace(/\n/g, " ")}`);
  console.log(`turns since last user: ${shaped.last_run?.turns?.length || 0}`);
  console.log(`session.jsonl totals: in=${t.in_tokens} out=${t.out_tokens} cache_read=${t.cache_read_tokens} cache_write=${t.cache_write_tokens} cost_usd=${t.cost_usd}`);
  console.log(`children: ${shaped.children.length}`);
  for (const c of shaped.children) {
    const u = c.aggregated_usage || {};
    console.log(`  - ${c.run_id} agent=${c.agent} state=${c.state} exit=${c.exit_code} turns=${c.turn_count} tools=${c.tool_count} | in=${u.in_tokens} out=${u.out_tokens} cache_read=${u.cache_read} cache_write=${u.cache_write} cost=${u.cost}`);
  }
  console.log(`wrote: ${jsonPath}`);
  console.log(`wrote: ${mdPath}`);
}

main();
