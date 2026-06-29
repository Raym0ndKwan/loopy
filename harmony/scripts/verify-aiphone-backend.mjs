#!/usr/bin/env node
import { existsSync, readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const scriptDir = dirname(fileURLToPath(import.meta.url));
const harmonyRoot = resolve(scriptDir, '..');
const repoRoot = resolve(harmonyRoot, '..');
const hvigor = '/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/bin/hvigor.js';
const sdkHome = process.env.DEVECO_SDK_HOME || '/Applications/DevEco-Studio.app/Contents/sdk';

const checks = [];

function pass(name) {
  checks.push({ name, ok: true });
  console.log(`PASS ${name}`);
}

function fail(name, detail) {
  checks.push({ name, ok: false });
  console.error(`FAIL ${name}`);
  if (detail) {
    console.error(`     ${detail}`);
  }
}

function assert(condition, name, detail = '') {
  if (condition) {
    pass(name);
  } else {
    fail(name, detail);
  }
}

function read(relativePath) {
  return readFileSync(resolve(repoRoot, relativePath), 'utf8');
}

function assertContains(text, needle, name) {
  assert(text.includes(needle), name, `missing ${needle}`);
}

function runHarBuild() {
  assert(existsSync(hvigor), 'DevEco hvigor is installed', hvigor);
  assert(existsSync(sdkHome), 'DevEco SDK home exists', sdkHome);
  if (!existsSync(hvigor) || !existsSync(sdkHome)) {
    return;
  }

  const result = spawnSync(process.execPath, [
    hvigor,
    '--mode',
    'module',
    '-p',
    'module=agent_core@default',
    '-p',
    'product=default',
    'assembleHar',
    '--analyze=normal',
    '--parallel',
    '--incremental',
    '--daemon'
  ], {
    cwd: harmonyRoot,
    env: {
      ...process.env,
      DEVECO_SDK_HOME: sdkHome
    },
    encoding: 'utf8'
  });

  if (result.stdout.trim().length > 0) {
    console.log(result.stdout.trim());
  }
  if (result.stderr.trim().length > 0) {
    console.error(result.stderr.trim());
  }
  assert(result.status === 0, 'agent_core HAR builds', `exit status ${result.status}`);
}

function verifySourceContracts() {
  const protocol = read('harmony/agent_core/src/main/ets/a2ui/A2uiProtocol.ets');
  const definitions = read('harmony/agent_core/src/main/ets/aiphone/AiphoneToolDefinitions.ets');
  const executor = read('harmony/agent_core/src/main/ets/aiphone/AiphoneToolExecutor.ets');
  const backend = read('harmony/agent_core/src/main/ets/aiphone/LoopBackend.ets');
  const index = read('harmony/agent_core/Index.ets');

  assertContains(protocol, "export const A2UI_VERSION = 'v0.9.1';", 'AIPhone A2UI version is v0.9.1');

  const ids = [...definitions.matchAll(/toolId:\s*'([^']+)'/g)].map((match) => match[1]);
  const uniqueIds = new Set(ids);
  assert(ids.length === uniqueIds.size, 'AIPhone tool ids are unique');
  assert(ids.length >= 19, 'AIPhone tool registry has expected breadth', `found ${ids.length}`);
  for (const id of [
    'travel.search',
    'train.search',
    'flight.search',
    'food.search',
    'social.reply.send',
    'gmail.mail.search',
    'gmail.thread.read',
    'gmail.draft.create',
    'gmail.message.send',
    'youtube.video.search',
    'calendar.events.search',
    'calendar.event.create',
    'maps.place.search',
    'maps.place.details'
  ]) {
    assert(uniqueIds.has(id), `registered ${id}`);
  }
  assertContains(definitions, "toolId === 'dynamic.search'", 'dynamic.search is treated as registered');
  assertContains(definitions, 'return TOOL_DEFINITIONS.length;', 'tool definition count uses source list');

  assertContains(executor, 'isRegisteredAiphoneToolId(toolId)', 'executor rejects unknown tools');
  assertContains(executor, "toolId === 'gmail.message.send'", 'executor handles blocked Gmail send');
  assertContains(executor, 'UnsafeActionBlocked', 'Gmail send returns unsafe action block');
  assertContains(executor, '不会自动发送 Gmail', 'Gmail send does not auto-send');
  assertContains(executor, "toolId === 'social.reply.send'", 'executor handles social reply send');
  assertContains(executor, '不会假装发送成功', 'social send does not fake success');
  assertContains(executor, '尚未迁移', 'unsupported providers are explicit');
  assertContains(executor, '不会返回模拟数据', 'unsupported providers do not return mock data');
  assertContains(executor, 'dynamic.search 已注册', 'dynamic search unsupported path is explicit');

  assertContains(backend, 'allToolDefinitions()', 'LoopBackend registers AIPhone definitions');
  assertContains(backend, "registry.register(new AiphoneTool(\n      'dynamic.search'", 'LoopBackend registers dynamic.search');
  assertContains(backend, 'splitJsonl(jsonl)', 'LoopBackend splits AIPhone JSONL');
  assertContains(backend, 'this.callbacks.onA2uiJsonl?.(line)', 'LoopBackend emits AIPhone JSONL lines');
  assertContains(backend, 'runAiphoneTool(', 'LoopBackend delegates tool execution to AIPhone executor');

  assertContains(index, "export { LoopBackend }", 'public export includes LoopBackend');
  assertContains(index, "export { runAiphoneTool }", 'public export includes runAiphoneTool');
  assertContains(index, 'allToolDefinitions', 'public export includes tool definitions');
}

runHarBuild();
verifySourceContracts();

const failed = checks.filter((check) => !check.ok);
if (failed.length > 0) {
  console.error(`\n${failed.length} verification check(s) failed.`);
  process.exit(1);
}

console.log(`\nAIPhone Loopy backend smoke passed (${checks.length} checks).`);
