// Node syntax/logic smoke tests without browsers or remote machines.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const src = fs.readFileSync(new URL('../web/app.js', import.meta.url), 'utf8');
function functionFrom(start, end) {
  const chunk = src.slice(src.indexOf(`function ${start}(`), src.indexOf(`function ${end}(`)).replace(/\s+async\s*$/, '');
  assert.ok(chunk.startsWith(`function ${start}(`), `missing ${start}`);
  return chunk;
}
const ctx = vm.createContext({ registry: new Map(), renderNodes() {}, NAME: /^[A-Za-z0-9._-]{1,80}$/, Date, Map, Number, Math, RegExp });
vm.runInContext(functionFrom('parseTelemetry', 'humanUptime'), ctx);
vm.runInContext(functionFrom('updateNodes', 'renderNodes'), ctx);
vm.runInContext(functionFrom('checkSuccess', 'probeNode'), ctx);
const win = [
  'ATHENA-04 / REMOTE CHECK: demo-windows','Destination: demo-user@192.0.2.10',
  'OS: Windows', 'Hostname: EXAMPLE-WIN', 'Kernel: Microsoft Windows 11 Pro', 'Machine: AMD64',
  'CPUs: 8', 'Uptime: 5550', 'MemTotal: 16384000 kB', 'MemAvailable: 8192000 kB',
  'Probe: ATHENA-WINDOWS-1', 'Connection: ONLINE / WINDOWS PROBE OK'].join('\n');
const linux = ['OS: Linux', 'Hostname: demo-other', 'Kernel: Linux 7.0', 'Machine: x86_64',
 'CPUs: 4', 'Uptime: 1234.5 800', 'MemTotal: 100000 kB', 'MemAvailable: 90000 kB',
 'Connection: ONLINE / LINUX PROBE OK'].join('\n');
assert.equal(ctx.checkSuccess({ok:true,output:win}),true);
assert.equal(ctx.checkSuccess({ok:true,output:linux}),true);
assert.equal(ctx.checkSuccess({ok:false,output:win}),false);
assert.equal(ctx.checkSuccess({ok:true,output:'Permission denied'}),false);
const metrics=ctx.parseTelemetry(win);
assert.equal(metrics.os, 'Windows');
assert.equal(metrics.cpu_logical_count,8);
assert.equal(metrics.uptime_seconds,5550);
assert.equal(metrics.memory_used_percent,50);
assert.equal(ctx.parseTelemetry(linux).os,'Linux');
ctx.updateNodes('ATHENA-04 / REGISTERED NODES\n  demo-linux  localhost  demo-user  [NOT CHECKED] [linux]\n  demo-windows  192.0.2.10  demo-win-user  [NOT CHECKED] [windows]\n  legacy  localhost  user  [NOT CHECKED]\nTotal: 3 node(s)');
assert.equal(ctx.registry.get('demo-windows').platform,'windows');
assert.equal(ctx.registry.get('demo-linux').platform,'linux');
assert.equal(ctx.registry.get('legacy').platform,'linux');
assert.equal(ctx.registry.size,3);
console.log('ATHENA v0.6 browser adapter smoke tests passed');
