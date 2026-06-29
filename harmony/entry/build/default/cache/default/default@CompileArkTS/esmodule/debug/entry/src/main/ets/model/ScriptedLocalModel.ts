import type { LocalModel } from './LocalModel';
export class ScriptedLocalModel implements LocalModel {
    async complete(prompt: string): Promise<string> {
        const lower = prompt.toLowerCase();
        if (!lower.includes('observation:')) {
            if (lower.includes('time') || lower.includes('date')) {
                return 'Thought: I should inspect the device clock.\nAction: time[]';
            }
            return `Thought: I should preserve the user's request as local context.\nAction: note[${this.extractTask(prompt)}]`;
        }
        return 'Thought: I have enough local context to answer.\nFinal: I ran the local ReAct loop and used the available device tool result.';
    }
    private extractTask(prompt: string): string {
        const marker = 'User task:';
        const start = prompt.indexOf(marker);
        if (start === -1) {
            return 'No task found';
        }
        let task = prompt.substring(start + marker.length).trim();
        const nextSection = task.indexOf('\n\n');
        if (nextSection >= 0) {
            task = task.substring(0, nextSection).trim();
        }
        return task.replace(/\[/g, '(').replace(/\]/g, ')');
    }
}
