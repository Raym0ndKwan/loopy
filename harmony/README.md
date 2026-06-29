# Loop — HarmonyOS NEXT

HarmonyOS NEXT port of the Loop ReAct agent starter. Matches the Android app:

- Chat UI with message input, send control, and event transcript
- `ReActAgentRunner` with Thought / Action / Observation / Final
- `ToolRegistry` with local `time` and `note` tools
- OpenAI-compatible HTTP adapter (DashScope / Qwen) plus scripted fallback

## Open in DevEco Studio

1. Install [DevEco Studio](https://developer.huawei.com/consumer/en/deveco-studio/) with HarmonyOS NEXT SDK (5.0+).
2. Open the `harmony/` folder as a project (not the repo root).
3. Configure signing under **File → Project Structure → Signing Configs** for device or emulator runs.
4. Sync/build, then run the `entry` module on a phone emulator or device.

If `ohpm install` fails looking for `@ohos/hvigor`, that package ships with DevEco Studio and must **not** be listed in `oh-package.json5` `devDependencies`. Use **File → Sync and Refresh Project** instead.

## LLM provider config

Harmony reads provider settings from a raw resource file:

`entry/src/main/resources/rawfile/llm_config.json`

### Option A — sync from Android `local.properties`

If you already use the repo-root `local.properties` for Android:

```bash
chmod +x scripts/sync-harmony-llm-config.sh
./scripts/sync-harmony-llm-config.sh
```

That writes `llm_config.json` from:

```properties
llm.providerName=ali-bailian-openai
llm.apiKey=...
llm.baseUrl=https://dashscope.aliyuncs.com/compatible-mode/v1
llm.model=qwen-plus
```

### Option B — copy the example file

```bash
cp entry/src/main/resources/rawfile/llm_config.example.json \
   entry/src/main/resources/rawfile/llm_config.json
```

Edit `llm_config.json` and set `apiKey`.

If the provider is not configured, the app uses `ScriptedLocalModel` (same fallback as Android).

## Source layout

```text
agent_core/                   # HAR — shared ReAct agent library
  Index.ets                   # Public exports
  src/main/ets/
    agent/ReActAgentRunner.ets
    agent/ToolRegistry.ets
    model/OpenAiCompatibleModel.ets
    model/ScriptedLocalModel.ets
    model/LlmProvider.ets
    model/LoopModelFactory.ets

entry/                        # App UI module (depends on agent_core)
  src/main/ets/
    pages/Index.ets           # Chat UI (Android MainActivity equivalent)
    entryability/EntryAbility.ets
```

`entry/oh-package.json5` references the HAR:

```json5
"dependencies": {
  "@loop/agent-core": "file:../agent_core"
}
```

UI code imports from `@loop/agent-core`:

```typescript
import { ReActAgentRunner, ToolRegistry, createLoopModel } from '@loop/agent-core';
```

## Conversation memory

Loop keeps a simple in-session history of user messages and final assistant answers in `ConversationContext`. Each successful run appends one user/assistant pair; failed runs are not stored. Use **Clear** to reset the session.

## Android parity notes

| Android | Harmony |
|---------|---------|
| `MainActivity.java` | `pages/Index.ets` |
| `local.properties` → Gradle `resValue` | `rawfile/llm_config.json` |
| `HttpURLConnection` | `@ohos.net.http` |
| `ExecutorService` + `Handler` | `async/await` in event handler |
| `INTERNET` permission in manifest | `ohos.permission.INTERNET` in `module.json5` |

## Replace the model

Implement `LocalModel` in `agent_core/src/main/ets/model/LocalModel.ets` and wire it in `LoopModelFactory.ets`. Keep responses compatible with:

```text
Thought: ...
Action: tool_name[input]
Final: ...
```
