# Loop — HarmonyOS NEXT

HarmonyOS NEXT port of the Loop ReAct agent starter. Matches the Android app:

- Chat UI with message input, send control, and event transcript
- `ReActAgentRunner` with Thought / Action / Observation / Final
- `ToolRegistry` with `time`, `note`, and **`ui`** (A2UI / AGenUI when the agent decides visual output helps)
- On-screen UI panel appears automatically when the agent calls the `ui` tool
- OpenAI-compatible HTTP adapter (DashScope / Qwen) plus scripted fallback

## Open in DevEco Studio

1. Install [DevEco Studio](https://developer.huawei.com/consumer/en/deveco-studio/) with HarmonyOS NEXT SDK **5.0.5 (API 17)+** (required by AGenUI).
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

entry/                        # App UI module
  src/main/ets/
    pages/Index.ets           # Unified Loop chat + on-screen UI panel
    agenui/A2uiFallbackView.ets
    entryability/EntryAbility.ets

libs/
  agenui.har                  # AGenUI SDK (fetch via scripts/fetch-agenui.sh)
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

## AGenUI (generative UI)

Loop integrates [AGenUI](https://github.com/AGenUI/AGenUI) A2UI protocol via a **`ui` ReAct tool**. The agent chooses it when you ask to show, display, or visualize something — no separate GenUI mode.

### Example prompts

- `What time is it?` → text answer (time tool)
- `Show a welcome card for Raymond` → **ui tool** → card in the panel above chat
- `Display a weather summary card: Sunny 72°F` → on-screen UI

### Setup (optional native AGenUI HAR)

The unified app renders UI with a built-in ArkUI fallback (works in Preview). For the full AGenUI native SDK, fetch the HAR:

```bash
chmod +x scripts/fetch-agenui.sh
./scripts/fetch-agenui.sh
```

Sync in DevEco Studio. Requires HarmonyOS NEXT **API 17+** for the HAR dependency.

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
