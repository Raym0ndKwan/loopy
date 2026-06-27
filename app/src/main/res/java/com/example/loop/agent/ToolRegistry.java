package com.example.loop.agent;

import java.text.DateFormat;
import java.util.Date;
import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;

public final class ToolRegistry {
    private final Map<String, AgentTool> tools = new LinkedHashMap<>();

    public ToolRegistry() {
        register(new AgentTool() {
            @Override
            public String name() {
                return "note";
            }

            @Override
            public String description() {
                return "Echoes a note back into the loop.";
            }

            @Override
            public String run(String input) {
                return input.trim().isEmpty() ? "No note provided." : "Noted: " + input.trim();
            }
        });

        register(new AgentTool() {
            @Override
            public String name() {
                return "time";
            }

            @Override
            public String description() {
                return "Returns the device's local date and time.";
            }

            @Override
            public String run(String input) {
                DateFormat format = DateFormat.getDateTimeInstance(
                        DateFormat.MEDIUM,
                        DateFormat.MEDIUM,
                        Locale.getDefault()
                );
                return format.format(new Date());
            }
        });
    }

    public void register(AgentTool tool) {
        tools.put(tool.name(), tool);
    }

    public String describeTools() {
        StringBuilder builder = new StringBuilder();
        for (AgentTool tool : tools.values()) {
            builder.append("- ")
                    .append(tool.name())
                    .append(": ")
                    .append(tool.description())
                    .append('\n');
        }
        return builder.toString();
    }

    public String run(String name, String input) {
        AgentTool tool = tools.get(name);
        if (tool == null) {
            return "Unknown tool: " + name;
        }
        return tool.run(input == null ? "" : input);
    }
}
