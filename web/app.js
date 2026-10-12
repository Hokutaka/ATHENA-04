'use strict';

// ATHENA-04 v0.6.2 browser-side Linux/Windows observation and node registry.
// Probe text is parsed as a *temporary UI adapter*, not a stable wire schema.
const $ = (id) => document.getElementById(id);
const outputs = $('output');
const field = $('cmd');
const history = [];
let historyCursor = 0;
const NAME = /^[A-Za-z0-9._-]{1,80}$/;
const INTERVAL_MS = 60_000;
const STALE_MS = 120_000;
const registry = new Map();
const pending = new Map();
let autoEnabled = true;
let pollRunning = false;

function stamp(time = Date.now()) {
  return new Date(time).toLocaleTimeString('en-GB', { hour12: false });
}
function timeAgo(time) {
  if (!time) return 'never';
  const seconds = Math.max(0, Math.floor((Date.now() - time) / 1000));
  if (seconds < 5) return 'just now';
  if (seconds < 60) return `${seconds}s ago`;
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
  return `${Math.floor(seconds / 3600)}h ago`;
}
function append(command, content, kind = 'response') {
  const block = document.createElement('div');
  block.className = 'line';
  const prompt = document.createElement('div');
  prompt.className = 'prompt';
  const timestamp = document.createElement('span');
  timestamp.className = 'timestamp';
  timestamp.textContent = stamp();
  prompt.append(timestamp, document.createTextNode(`athena> ${command}`));
  const pre = document.createElement('pre');
  pre.className = kind;
  pre.textContent = content;
  block.append(prompt, pre);
  outputs.append(block);
  outputs.scrollTop = outputs.scrollHeight;
  return pre;
}
async function api(url) {
  // No credentials are sent to remote nodes by the browser. The local Hare
  // server invokes only its fixed, read-only SSH probe.
  const response = await fetch(url, { cache: 'no-store', credentials: 'same-origin' });
  const data = await response.json();
  return { ...data, ok: Boolean(data.ok) && response.ok };
}
// Guarded zero-body POSTs: never send a shell command or credential.
async function apiMutation(path) {
  const response = await fetch(path, {
    method: 'POST',
    headers: { 'X-Athena-Console': '1' },
    credentials: 'same-origin',
    cache: 'no-store'
  });
  const data = await response.json();
  return { ...data, ok: Boolean(data.ok) && response.ok };
}
function connection(ok) {
  $('led').className = `led ${ok ? 'online' : 'offline'}`;
  $('connection').textContent = ok ? 'CONSOLE CONNECTED' : 'CONSOLE DISCONNECTED';
}

// Preserve the exact distinction between CPU count and CPU load.
function parseTelemetry(output) {
  const read = (key) => {
    const match = output.match(new RegExp(`^\\s*${key}:\\s*(.*?)\\s*$`, 'm'));
    return match?.[1] ?? null;
  };
  const positiveInteger = (text) => {
    if (text == null || !/^\d+$/.test(text)) return null;
    const n = Number(text);
    return Number.isSafeInteger(n) ? n : null;
  };
  const getKiB = (key) => {
    const match = (read(key) || '').match(/^(\d+)\s+kB$/i);
    return match ? positiveInteger(match[1]) : null;
  };
  const uptimeMatch = (read('Uptime') || '').match(/^(\d+(?:\.\d+)?)/);
  const uptimeSeconds = uptimeMatch ? Number(uptimeMatch[1]) : null;
  const memoryTotalKiB = getKiB('MemTotal');
  const memoryAvailableKiB = getKiB('MemAvailable');
  const memoryUsedPercent = memoryTotalKiB && memoryAvailableKiB !== null && memoryAvailableKiB <= memoryTotalKiB
    ? Math.min(100, Math.max(0, 100 * (memoryTotalKiB - memoryAvailableKiB) / memoryTotalKiB)) : null;
  const result = {
    schema: 'athena-04.browser-telemetry.v0.6.2',
    os: read('OS'),
    hostname: read('Hostname'),
    kernel: read('Kernel'),
    architecture: read('Machine'),
    cpu_logical_count: positiveInteger(read('CPUs')),
    uptime_seconds: Number.isFinite(uptimeSeconds) ? uptimeSeconds : null,
    memory_total_kib: memoryTotalKiB,
    memory_available_kib: memoryAvailableKiB,
    memory_used_percent: memoryUsedPercent
  };
  return result.hostname || result.cpu_logical_count !== null || result.memory_total_kib !== null ? result : null;
}
function humanUptime(seconds) {
  if (seconds === null || !Number.isFinite(seconds) || seconds < 0) return 'UNAVAILABLE';
  const mins = Math.floor(seconds / 60);
  const d = Math.floor(mins / 1440);
  const h = Math.floor((mins % 1440) / 60);
  const m = mins % 60;
  return `${d ? `${d}d ` : ''}${h ? `${h}h ` : ''}${m}m`;
}
function humanMemory(kib) {
  return Number.isFinite(kib) ? `${(kib / (1024 * 1024)).toFixed(2)} GiB` : 'UNAVAILABLE';
}
function createTelemetryCard(metrics, label) {
  const card = document.createElement('section');
  card.className = 'telemetry-card';
  const heading = document.createElement('div');
  heading.className = 'telemetry-title';
  heading.textContent = `${label} / TELEMETRY`;
  card.append(heading);
  const grid = document.createElement('div');
  grid.className = 'telemetry-grid';
  for (const [title, value] of [
    ['HOST', metrics.hostname ?? 'UNAVAILABLE'],
    ['OS / KERNEL', metrics.kernel ?? 'UNAVAILABLE'],
    ['ARCH', metrics.architecture ?? 'UNAVAILABLE'],
    ['LOGICAL CPUs', metrics.cpu_logical_count ?? 'UNAVAILABLE'],
    ['UPTIME', humanUptime(metrics.uptime_seconds)],
    ['MEMORY AVAILABLE', humanMemory(metrics.memory_available_kib)]
  ]) {
    const item = document.createElement('div');
    const tag = document.createElement('span');
    tag.className = 'telemetry-key';
    tag.textContent = title;
    const valueElement = document.createElement('strong');
    valueElement.textContent = String(value);
    item.append(tag, valueElement);
    grid.append(item);
  }
  card.append(grid);
  if (metrics.memory_used_percent !== null) {
    const pct = Math.round(metrics.memory_used_percent);
    const line = document.createElement('div');
    line.className = 'memory-caption';
    line.textContent = `MEMORY USED  ${humanMemory(metrics.memory_total_kib - metrics.memory_available_kib)} / ${humanMemory(metrics.memory_total_kib)}  (${pct}%)`;
    const track = document.createElement('div');
    track.className = 'meter';
    track.setAttribute('role', 'progressbar');
    track.setAttribute('aria-label', 'Memory used');
    track.setAttribute('aria-valuemin', '0');
    track.setAttribute('aria-valuemax', '100');
    track.setAttribute('aria-valuenow', String(pct));
    const bar = document.createElement('div');
    bar.className = 'meter-fill';
    bar.style.width = `${pct}%`;
    track.append(bar);
    card.append(line, track);
  }
  return card;
}
function showResult(pre, output, ok, title) {
  pre.className = ok ? 'response' : 'response error';
  pre.textContent = output || (ok ? 'OK' : 'UNKNOWN ERROR');
  const metrics = ok ? parseTelemetry(output) : null;
  if (metrics) {
    pre.before(createTelemetryCard(metrics, title));
    const detail = document.createElement('details');
    detail.className = 'raw-details';
    const summary = document.createElement('summary');
    summary.textContent = 'RAW PROBE OUTPUT';
    pre.replaceWith(detail);
    detail.append(summary, pre);
  }
  outputs.scrollTop = outputs.scrollHeight;
  return metrics;
}
function nodeState(record) {
  if (record.state === 'ONLINE' && record.lastCheckedAt && Date.now() - record.lastCheckedAt > STALE_MS) return 'STALE';
  return record.state;
}
function updateNodes(output) {
  const rows = output.split(/\r?\n/);
  const next = new Map();
  for (const row of rows) {
    const match = row.match(/^\s{2,}([^\s]+)\s+([^\s]+)\s+([^\s]+)\s+\[NOT CHECKED\](?:\s+\[(linux|windows)\])?/);
    if (!match || !NAME.test(match[1])) continue;
    const [ , name, host, user, detectedPlatform] = match;
    const platform = detectedPlatform || 'linux';
    const saved = registry.get(name);
    if (saved && saved.host === host && saved.user === user && saved.platform === platform) next.set(name, saved);
    else next.set(name, { name, host, user, platform, state: 'NOT CHECKED', lastCheckedAt: null, lastSuccessAt: null, telemetry: null, error: null });
  }
  registry.clear();
  for (const [name, node] of next) registry.set(name, node);
  renderNodes();
}
function renderNodes() {
  const list = $('nodes');
  list.replaceChildren();
  for (const node of registry.values()) {
    const state = nodeState(node);
    const button = document.createElement('button');
    button.className = `node state-${state.toLowerCase().replaceAll(' ', '-')}`;
    button.type = 'button';
    const title = document.createElement('span');
    title.className = 'node-title';
    const indicator = document.createElement('span');
    indicator.className = 'indicator';
    indicator.textContent = state === 'ONLINE' ? '●' : state === 'CHECKING' ? '◌' : state === 'NOT CHECKED' ? '◇' : '◆';
    title.append(indicator, document.createTextNode(node.name));
    const stateLine = document.createElement('small');
    stateLine.className = 'node-state-line';
    stateLine.textContent = `${node.host} · ${node.platform.toUpperCase()} · ${state}`;
    const meta = document.createElement('small');
    meta.className = 'node-meta';
    const info = node.telemetry && state !== 'NOT CHECKED' ? node.telemetry : null;
    const pct = info?.memory_used_percent;
    const stats = info ? `${pct === null ? '' : `MEM ${Math.round(pct)}% · `}UP ${humanUptime(info.uptime_seconds)}` : '';
    meta.textContent = `Checked ${timeAgo(node.lastCheckedAt)}${stats ? ` · ${stats}` : ''}${state !== 'ONLINE' && node.lastSuccessAt ? ` · Last OK ${timeAgo(node.lastSuccessAt)}` : ''}`;
    button.append(title, stateLine, meta);
    if (node.error) button.title = node.error.slice(0, 300);
    button.addEventListener('click', () => execute(`inspect ${node.name}`));
    const wrap = document.createElement('div');
    wrap.className = 'node-wrap';
    const actions = document.createElement('div');
    actions.className = 'node-actions';
    const check = document.createElement('button');
    check.type = 'button';
    check.textContent = 'CHECK';
    check.addEventListener('click', () => execute(`inspect ${node.name}`));
    const remove = document.createElement('button');
    remove.type = 'button';
    remove.className = 'remove-node';
    remove.textContent = 'REMOVE';
    remove.addEventListener('click', () => removeNode(node.name));
    const changeOS = document.createElement('button');
    changeOS.type = 'button';
    changeOS.textContent = 'OS';
    changeOS.title = 'Change Linux / Windows probe';
    changeOS.addEventListener('click', () => changeNodeOS(node.name));
    actions.append(check, changeOS, remove);
    wrap.append(button, actions);
    list.append(wrap);
  }
  if (registry.size === 0) {
    const empty = document.createElement('div');
    empty.className = 'muted';
    empty.textContent = 'No nodes yet. Use + ADD to register one.';
    list.append(empty);
  }
  $('node-count').textContent = `${registry.size} REGISTERED`;
}
async function reloadNodes() {
  try {
    const data = await api('/api/nodes');
    if (!data.ok) throw new Error(data.output || 'Registry unavailable');
    updateNodes(data.output);
    connection(true);
    return true;
  } catch (error) {
    connection(false);
    $('nodes').textContent = `Unable to load nodes: ${error.message}`;
    return false;
  }
}

function checkSuccess(data) {
  return data.ok && /^\s*Connection:\s*ONLINE\s*\/\s*(?:LINUX|WINDOWS) PROBE OK\s*$/m.test(data.output || '');
}
async function probeNode(name, pre = null, format = 'inspect') {
  if (pending.has(name)) {
    const response = await pending.get(name);
    if (pre) renderProbeOutput(pre, response, name, format);
    return response;
  }
  const node = registry.get(name);
  if (node) {
    node.state = 'CHECKING';
    node.error = null;
    renderNodes();
  }
  const job = (async () => {
    try {
      const data = await api(`/api/check/${encodeURIComponent(name)}`);
      const checkedAt = Date.now();
      const success = checkSuccess(data);
      if (node && registry.get(name) === node) {
        node.state = success ? 'ONLINE' : 'UNREACHABLE';
        node.lastCheckedAt = checkedAt;
        node.error = success ? null : (data.output || 'SSH probe failed');
        if (success) {
          node.lastSuccessAt = checkedAt;
          node.telemetry = parseTelemetry(data.output);
        } else {
          node.telemetry = null; // no stale values shown as current readings
        }
        renderNodes();
      }
      connection(true); // HTTP server is reachable even when SSH fails
      return { ...data, success, checkedAt };
    } catch (error) {
      if (node && registry.get(name) === node) {
        node.state = 'UNREACHABLE';
        node.lastCheckedAt = Date.now();
        node.telemetry = null;
        node.error = `Console request failed: ${error.message}`;
        renderNodes();
      }
      connection(false);
      return { ok: false, success: false, output: `NETWORK ERROR: ${error.message}`, checkedAt: Date.now() };
    }
  })();
  pending.set(name, job);
  try {
    const data = await job;
    if (pre) renderProbeOutput(pre, data, name, format);
    return data;
  } finally {
    pending.delete(name);
  }
}
function renderProbeOutput(pre, data, name, format) {
  if (format === 'telemetry') {
    const telemetry = data.success ? parseTelemetry(data.output) : null;
    const result = {
      name,
      state: data.success ? 'ONLINE' : 'UNREACHABLE',
      checked_at: new Date(data.checkedAt).toISOString(),
      telemetry,
      error: data.success ? null : data.output
    };
    pre.className = data.success ? 'response' : 'response error';
    pre.textContent = JSON.stringify(result, null, 2);
  } else {
    showResult(pre, data.output, data.success, name.toUpperCase());
  }
}

async function pollRegistered(force = false) {
  if ((!autoEnabled && !force) || document.hidden || pollRunning) return;
  pollRunning = true;
  $('scan-state').textContent = 'SCANNING';
  try {
    // Re-read the registry each sweep. Do not add/drop hosts implicitly.
    if (!await reloadNodes()) return;
    for (const name of [...registry.keys()]) {
      if ((!autoEnabled && !force) || document.hidden) break;
      await probeNode(name); // serialized; each SSH probe has a 15s upper bound
    }
  } finally {
    pollRunning = false;
    $('scan-state').textContent = autoEnabled ? 'AUTO / 60s' : 'AUTO / OFF';
  }
}
async function execute(raw) {
  const command = raw.trim();
  if (!command) return;
  history.push(command);
  historyCursor = history.length;
  if (command === 'clear') { outputs.replaceChildren(); return; }
  if (command === 'help') {
    append(command, 'status              Observe local Linux telemetry\nnodes               List registered nodes\ninspect NAME        Probe Linux/Windows over SSH\ntelemetry NAME      Show browser-side JSON\nscan                Check all registered nodes\nadd                 Open node registration form\nremove NAME         Remove a registered node (confirmation required)\nclear               Clear console output\nhelp                Show this help');
    return;
  }
  if (command === 'add') { $('node-dialog').showModal(); return; }
  const removeMatch = command.match(/^remove\s+(\S+)$/);
  if (removeMatch && NAME.test(removeMatch[1])) { await removeNode(removeMatch[1]); return; }
  if (command === 'scan') { append(command, 'Probing registered nodes in the background.'); await pollRegistered(true); return; }
  if (command === 'nodes') {
    const pre = append(command, 'Loading registry...', 'response pending');
    const ok = await reloadNodes();
    pre.className = ok ? 'response' : 'response error';
    pre.textContent = ok ? [...registry.values()].map(n => `${n.name}  ${n.host}  ${n.platform}  ${nodeState(n)}`).join('\n') || 'No registered nodes.' : 'Failed to load node registry';
    return;
  }
  if (command === 'status') {
    const pre = append(command, 'Requesting telemetry...', 'response pending');
    try {
      const data = await api('/api/status');
      showResult(pre, data.output, data.ok, 'LOCAL');
      connection(true);
    } catch (e) {
      pre.className = 'response error';
      pre.textContent = `NETWORK ERROR: ${e.message}`;
      connection(false);
    }
    return;
  }
  const match = command.match(/^(inspect|telemetry)\s+(\S+)$/);
  if (match && NAME.test(match[2])) {
    const pre = append(command, 'Requesting telemetry...', 'response pending');
    await probeNode(match[2], pre, match[1]);
    return;
  }
  append(command, 'Invalid command or node name. Type help for supported operations.', 'response error');
}


// Mutations do not use an unrestricted CLI shell. All writes are mediated by
// the Hare HTTP server and validated again in the Hare CLI.
function validPart(value, limit) {
  return value.length >= 1 && value.length <= limit && /^[A-Za-z0-9._-]+$/.test(value) && !value.startsWith('-');
}
async function changeNodeOS(name) {
  const node = registry.get(name);
  if (!node) return;
  const newOS = node.platform === 'windows' ? 'linux' : 'windows';
  if (!window.confirm(`Change ${name} from ${node.platform} to ${newOS} probe?\n\nHost and SSH keys stay unchanged.`)) return;
  const pre = append(`os ${name} ${newOS}`, 'Updating node OS...', 'response pending');
  try {
    const data = await apiMutation(`/api/node/os/${encodeURIComponent(name)}/${newOS}`);
    pre.className = data.ok ? 'response' : 'response error';
    pre.textContent = data.output || 'No response';
    if (data.ok) await reloadNodes();
  } catch (err) {
    pre.className = 'response error';
    pre.textContent = `REGISTRY ERROR: ${err.message}`;
  }
}
async function removeNode(name) {
  if (!validPart(name, 80) || !registry.has(name)) return;
  if (!window.confirm(`Remove ${name} from ATHENA-04?\n\nSSH keys and known_hosts are not changed.`)) return;
  const pre = append(`remove ${name}`, 'Removing registry entry...', 'response pending');
  try {
    const data = await apiMutation(`/api/node/remove/${encodeURIComponent(name)}`);
    pre.className = data.ok ? 'response' : 'response error';
    pre.textContent = data.output || 'No response from registry';
    if (data.ok) {
      registry.delete(name);
      renderNodes();
      await reloadNodes();
    }
  } catch (err) {
    pre.className = 'response error';
    pre.textContent = `REGISTRY ERROR: ${err.message}`;
  }
}
const nodeDialog = $('node-dialog');
$('add-node').addEventListener('click', () => nodeDialog.showModal());
$('node-cancel').addEventListener('click', () => nodeDialog.close());
$('node-dismiss').addEventListener('click', () => nodeDialog.close());
$('node-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const name = $('node-name').value.trim();
  const host = $('node-host').value.trim();
  const user = $('node-user').value.trim();
  const platform = $('node-platform').value;
  const errorLine = $('node-error');
  errorLine.textContent = '';
  if (!validPart(name, 80) || !validPart(host, 253) || !validPart(user, 64) || !['linux', 'windows'].includes(platform)) {
    errorLine.textContent = 'Use ASCII letters, digits, . _ - (no leading hyphen).';
    return;
  }
  const doCheck = $('node-probe').checked;
  const saveButton = $('node-submit');
  saveButton.disabled = true;
  try {
    const path = `/api/node/add/${encodeURIComponent(name)}/${encodeURIComponent(host)}/${encodeURIComponent(user)}/${platform}`;
    const data = await apiMutation(path);
    if (!data.ok) {
      errorLine.textContent = (data.output || 'Registry write failed').slice(0, 350);
      return;
    }
    nodeDialog.close();
    $('node-form').reset();
    append(`add ${name}`, data.output || 'Node registered.');
    await reloadNodes();
    if (doCheck) {
      const pre = append(`inspect ${name}`, 'Testing SSH connection...', 'response pending');
      await probeNode(name, pre);
    }
  } catch (err) {
    errorLine.textContent = `NETWORK ERROR: ${err.message}`;
  } finally {
    saveButton.disabled = false;
  }
});

$('terminal').addEventListener('submit', (event) => {
  event.preventDefault();
  const command = field.value;
  field.value = '';
  execute(command);
  field.focus();
});
field.addEventListener('keydown', (event) => {
  if (event.key === 'ArrowUp' && historyCursor > 0) {
    event.preventDefault(); field.value = history[--historyCursor] || '';
  } else if (event.key === 'ArrowDown' && historyCursor < history.length) {
    event.preventDefault(); field.value = history[++historyCursor] || '';
  }
});
document.querySelectorAll('[data-cmd]').forEach(button => button.addEventListener('click', () => execute(button.dataset.cmd)));
$('reload').addEventListener('click', () => execute('nodes'));
$('scan-all').addEventListener('click', () => pollRegistered(true));
$('auto-toggle').addEventListener('click', () => {
  autoEnabled = !autoEnabled;
  $('auto-toggle').setAttribute('aria-pressed', String(autoEnabled));
  $('auto-toggle').textContent = autoEnabled ? 'AUTO ON' : 'AUTO OFF';
  $('scan-state').textContent = autoEnabled ? 'AUTO / 60s' : 'AUTO / OFF';
  if (autoEnabled) pollRegistered();
});
const clock = () => {
  const tz = -new Date().getTimezoneOffset() / 60;
  $('clock').textContent = `${stamp()} / UTC${tz >= 0 ? '+' : ''}${tz}`;
};
clock();
setInterval(clock, 1000);
setInterval(renderNodes, 10_000); // refresh relative timestamps and stale state
setInterval(pollRegistered, INTERVAL_MS);
document.addEventListener('visibilitychange', () => { if (!document.hidden) pollRegistered(); });
// Start on a visible page only. Keep console noise separate from background probes.
if (!document.hidden) pollRegistered();
else reloadNodes();
