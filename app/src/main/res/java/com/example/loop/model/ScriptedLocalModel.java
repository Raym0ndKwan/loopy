package com.example.loop.model;

import java.util.Locale;

public final class ScriptedLocalModel implements LocalModel {
    @Override
    public String complete(String prompt) {
        String lower = prompt.toLowerCase(Locale.US);

        if (!lower.contains("observation:")) {
            if (lower.contains("time") || lower.contains("date")) {
                return "Thought: I should inspect the device clock.\nAction: time[]";
            }
            return "Thought: I should preserve the user's request as local context.\nAction: note[" + extractTask(prompt) + "]";
        }

        return "Thought: I have enough local context to answer.\nFinal: I ran the local ReAct loop and used the available device tool result.";
    }

    private String extractTask(String prompt) {
        String marker = "User task:";
        int start = prompt.indexOf(marker);
        if (start == -1) {
            return "No task found";
        }

        String task = prompt.substring(start + marker.length()).trim();
        int nextSection = task.indexOf("\n\n");
        if (nextSection >= 0) {
            task = task.substring(0, nextSection).trim();
        }
        return task.replace("[", "(").replace("]", ")");
    }
}
