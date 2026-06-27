package com.example.loop.agent;

public final class AgentEvent {
    public enum Kind {
        THOUGHT,
        ACTION,
        OBSERVATION,
        FINAL,
        ERROR
    }

    private final Kind kind;
    private final String text;

    public AgentEvent(Kind kind, String text) {
        this.kind = kind;
        this.text = text;
    }

    public Kind getKind() {
        return kind;
    }

    public String getText() {
        return text;
    }
}
