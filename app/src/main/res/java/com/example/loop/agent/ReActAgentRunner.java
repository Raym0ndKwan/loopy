package com.example.loop.agent;

import com.example.loop.model.LocalModel;

import java.util.ArrayList;
import java.util.List;

public final class
ReActAgentRunner {
    public interface Listener {
        void onEvent(AgentEvent event);
    }

    private final LocalModel model;
    private final ToolRegistry tools;
    private final int maxSteps;

    public ReActAgentRunner(LocalModel model, ToolRegistry tools, int maxSteps) {
        this.model = model;
        this.tools = tools;
        this.maxSteps = maxSteps;
    }

    public void run(String task, Listener listener) {
        List<String> scratchpad = new ArrayList<>();

        for (int step = 0; step < maxSteps; step++) {
            String response;
            try {
                response = model.complete(buildPrompt(task, scratchpad));
            } catch (RuntimeException exception) {
                listener.onEvent(new AgentEvent(AgentEvent.Kind.ERROR, exception.getMessage()));
                return;
            }
            emitResponse(response, listener);

            String finalAnswer = readLineValue(response, "Final:");
            if (finalAnswer != null) {
                listener.onEvent(new AgentEvent(AgentEvent.Kind.FINAL, finalAnswer));
                return;
            }

            ToolCall call = parseAction(response);
            if (call == null) {
                listener.onEvent(new AgentEvent(AgentEvent.Kind.ERROR, "Model did not return an Action or Final answer."));
                return;
            }

            listener.onEvent(new AgentEvent(AgentEvent.Kind.ACTION, call.name + "(" + call.input + ")"));
            String observation = tools.run(call.name, call.input);
            scratchpad.add(response);
            scratchpad.add("Observation: " + observation);
            listener.onEvent(new AgentEvent(AgentEvent.Kind.OBSERVATION, observation));
        }

        listener.onEvent(new AgentEvent(AgentEvent.Kind.ERROR, "Stopped after " + maxSteps + " steps without a final answer."));
    }

    private String buildPrompt(String task, List<String> scratchpad) {
        StringBuilder builder = new StringBuilder();
        builder.append("You are a local Android ReAct agent.\n")
                .append("Use Thought, Action, Observation, and Final.\n\n")
                .append("Tools:\n")
                .append(tools.describeTools())
                .append("\nUser task:\n")
                .append(task)
                .append("\n\n");

        for (String item : scratchpad) {
            builder.append(item).append("\n");
        }
        return builder.toString();
    }

    private void emitResponse(String response, Listener listener) {
        String thought = readLineValue(response, "Thought:");
        if (thought != null) {
            listener.onEvent(new AgentEvent(AgentEvent.Kind.THOUGHT, thought));
        }
    }

    private String readLineValue(String text, String prefix) {
        String[] lines = text.split("\\R");
        for (String line : lines) {
            if (line.startsWith(prefix)) {
                return line.substring(prefix.length()).trim();
            }
        }
        return null;
    }

    private ToolCall parseAction(String response) {
        String action = readLineValue(response, "Action:");
        if (action == null) {
            return null;
        }

        int open = action.indexOf('[');
        int close = action.lastIndexOf(']');
        if (open <= 0 || close < open) {
            return null;
        }

        String name = action.substring(0, open).trim();
        String input = action.substring(open + 1, close).trim();
        return new ToolCall(name, input);
    }

    private static final class ToolCall {
        private final String name;
        private final String input;

        private ToolCall(String name, String input) {
            this.name = name;
            this.input = input;
        }
    }
}
