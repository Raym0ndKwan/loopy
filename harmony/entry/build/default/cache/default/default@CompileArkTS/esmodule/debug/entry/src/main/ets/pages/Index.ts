if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface Index_Params {
    transcript?: string;
    message?: string;
    sending?: boolean;
    modelStatus?: string;
    scroller?: Scroller;
    conversation?: ConversationContext;
}
import type common from "@ohos:app.ability.common";
import { AgentEventKind, ConversationContext, createLoopModelInfo, ReActAgentRunner, ToolRegistry } from "@bundle:com.example.loop/entry@agent_core/Index";
import type { AgentEvent } from "@bundle:com.example.loop/entry@agent_core/Index";
const MAX_STEPS = 4;
class Index extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__transcript = new ObservedPropertySimplePU('Loop is ready.\n', this, "transcript");
        this.__message = new ObservedPropertySimplePU('', this, "message");
        this.__sending = new ObservedPropertySimplePU(false, this, "sending");
        this.__modelStatus = new ObservedPropertySimplePU('Checking model…', this, "modelStatus");
        this.scroller = new Scroller();
        this.conversation = new ConversationContext();
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: Index_Params) {
        if (params.transcript !== undefined) {
            this.transcript = params.transcript;
        }
        if (params.message !== undefined) {
            this.message = params.message;
        }
        if (params.sending !== undefined) {
            this.sending = params.sending;
        }
        if (params.modelStatus !== undefined) {
            this.modelStatus = params.modelStatus;
        }
        if (params.scroller !== undefined) {
            this.scroller = params.scroller;
        }
        if (params.conversation !== undefined) {
            this.conversation = params.conversation;
        }
    }
    updateStateVars(params: Index_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__transcript.purgeDependencyOnElmtId(rmElmtId);
        this.__message.purgeDependencyOnElmtId(rmElmtId);
        this.__sending.purgeDependencyOnElmtId(rmElmtId);
        this.__modelStatus.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__transcript.aboutToBeDeleted();
        this.__message.aboutToBeDeleted();
        this.__sending.aboutToBeDeleted();
        this.__modelStatus.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private __transcript: ObservedPropertySimplePU<string>;
    get transcript() {
        return this.__transcript.get();
    }
    set transcript(newValue: string) {
        this.__transcript.set(newValue);
    }
    private __message: ObservedPropertySimplePU<string>;
    get message() {
        return this.__message.get();
    }
    set message(newValue: string) {
        this.__message.set(newValue);
    }
    private __sending: ObservedPropertySimplePU<boolean>;
    get sending() {
        return this.__sending.get();
    }
    set sending(newValue: boolean) {
        this.__sending.set(newValue);
    }
    private __modelStatus: ObservedPropertySimplePU<string>;
    get modelStatus() {
        return this.__modelStatus.get();
    }
    set modelStatus(newValue: string) {
        this.__modelStatus.set(newValue);
    }
    private scroller: Scroller;
    private conversation: ConversationContext;
    private getAbilityContext(): common.UIAbilityContext {
        return this.getUIContext().getHostContext() as common.UIAbilityContext;
    }
    aboutToAppear(): void {
        createLoopModelInfo(this.getAbilityContext()).then((info) => {
            if (info.mode === 'llm') {
                this.modelStatus = `LLM: ${info.modelName}`;
            }
            else {
                this.modelStatus = 'Offline demo (no API key — add entry/.../rawfile/llm_config.json)';
            }
        });
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.width('100%');
            Column.height('100%');
            Column.padding(14);
            Column.backgroundColor({ "id": 16777223, "type": 10001, params: [], "bundleName": "com.example.loop", "moduleName": "entry" });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.width('100%');
            Row.margin({ bottom: 8 });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.modelStatus);
            Text.fontSize(12);
            Text.fontColor({ "id": 16777226, "type": 10001, params: [], "bundleName": "com.example.loop", "moduleName": "entry" });
            Text.opacity(0.7);
            Text.layoutWeight(1);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel('Clear');
            Button.fontSize(12);
            Button.height(28);
            Button.backgroundColor(Color.Transparent);
            Button.fontColor({ "id": 16777224, "type": 10001, params: [], "bundleName": "com.example.loop", "moduleName": "entry" });
            Button.enabled(!this.sending);
            Button.onClick(() => {
                this.clearConversation();
            });
        }, Button);
        Button.pop();
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Scroll.create(this.scroller);
            Scroll.layoutWeight(1);
            Scroll.width('100%');
            Scroll.align(Alignment.BottomStart);
            Scroll.padding({ left: 4, right: 4, top: 4, bottom: 12 });
        }, Scroll);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.transcript);
            Text.fontSize(16);
            Text.fontColor({ "id": 16777226, "type": 10001, params: [], "bundleName": "com.example.loop", "moduleName": "entry" });
            Text.lineHeight(24);
            Text.width('100%');
            Text.textAlign(TextAlign.Start);
        }, Text);
        Text.pop();
        Scroll.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.width('100%');
            Row.padding({ top: 10 });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            TextInput.create({ text: this.message, placeholder: 'Message Loop' });
            TextInput.layoutWeight(1);
            TextInput.height(52);
            TextInput.borderRadius(20);
            TextInput.backgroundColor(Color.White);
            TextInput.border({ width: 1, color: { "id": 16777222, "type": 10001, params: [], "bundleName": "com.example.loop", "moduleName": "entry" } });
            TextInput.padding({ left: 14, right: 14 });
            TextInput.enabled(!this.sending);
            TextInput.onChange((value: string) => {
                this.message = value;
            });
            TextInput.onSubmit(() => {
                this.runAgent();
            });
        }, TextInput);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel(this.sending ? '...' : 'Send');
            Button.width(86);
            Button.height(52);
            Button.margin({ left: 8 });
            Button.backgroundColor({ "id": 16777224, "type": 10001, params: [], "bundleName": "com.example.loop", "moduleName": "entry" });
            Button.fontColor(Color.White);
            Button.enabled(!this.sending);
            Button.onClick(() => {
                this.runAgent();
            });
        }, Button);
        Button.pop();
        Row.pop();
        Column.pop();
    }
    private async runAgent(): Promise<void> {
        const task = this.message.trim();
        if (task.length === 0 || this.sending) {
            return;
        }
        this.appendUserMessage(task);
        this.message = '';
        this.sending = true;
        let finalAnswer: string | null = null;
        try {
            const modelInfo = await createLoopModelInfo(this.getAbilityContext());
            if (modelInfo.mode === 'llm') {
                this.modelStatus = `LLM: ${modelInfo.modelName}`;
            }
            else {
                this.modelStatus = 'Offline demo (no API key — add entry/.../rawfile/llm_config.json)';
            }
            const runner = new ReActAgentRunner(modelInfo.model, new ToolRegistry(), MAX_STEPS);
            await runner.run(task, (event: AgentEvent) => {
                if (event.kind === AgentEventKind.FINAL) {
                    finalAnswer = event.text;
                }
                this.addEvent(event);
            }, this.conversation);
        }
        finally {
            if (finalAnswer !== null) {
                this.conversation.addUser(task);
                this.conversation.addAssistant(finalAnswer);
            }
            this.sending = false;
        }
    }
    private clearConversation(): void {
        this.conversation.clear();
        this.transcript = 'Loop is ready.\n';
    }
    private addEvent(event: AgentEvent): void {
        switch (event.kind) {
            case AgentEventKind.THOUGHT:
                this.appendLine('Loop', event.text);
                break;
            case AgentEventKind.ACTION:
                this.appendLine('Tool', event.text);
                break;
            case AgentEventKind.OBSERVATION:
                this.appendLine('Observation', event.text);
                break;
            case AgentEventKind.FINAL:
                this.appendLine('Loop', event.text);
                break;
            case AgentEventKind.ERROR:
            default:
                this.appendLine('Error', event.text);
                break;
        }
    }
    private appendUserMessage(message: string): void {
        this.appendLine('You', message);
    }
    private appendLine(speaker: string, text: string): void {
        const prefix = this.transcript.trim().length === 0 ? '' : '\n\n';
        this.transcript += `${prefix}${speaker}\n${text}`;
        this.scroller.scrollEdge(Edge.Bottom);
    }
    rerender() {
        this.updateDirtyElements();
    }
    static getEntryName(): string {
        return "Index";
    }
}
registerNamedRoute(() => new Index(undefined, {}), "", { bundleName: "com.example.loop", moduleName: "entry", pagePath: "pages/Index", pageFullPath: "entry/src/main/ets/pages/Index", integratedHsp: "false", moduleType: "followWithHap" });
