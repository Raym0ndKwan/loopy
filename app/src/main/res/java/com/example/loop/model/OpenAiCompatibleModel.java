package com.example.loop.model;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;

public final class OpenAiCompatibleModel implements LocalModel {
    private final LlmProvider provider;

    public OpenAiCompatibleModel(LlmProvider provider) {
        this.provider = provider;
    }

    @Override
    public String complete(String prompt) {
        if (!provider.isConfigured()) {
            throw new IllegalStateException("LLM provider is not configured.");
        }

        HttpURLConnection connection = null;
        try {
            URL url = new URL(provider.chatCompletionsUrl());
            connection = (HttpURLConnection) url.openConnection();
            connection.setRequestMethod("POST");
            connection.setConnectTimeout(20_000);
            connection.setReadTimeout(60_000);
            connection.setDoOutput(true);
            connection.setRequestProperty("Authorization", "Bearer " + provider.getApiKey());
            connection.setRequestProperty("Content-Type", "application/json; charset=utf-8");
            connection.setRequestProperty("Accept", "application/json");

            try (BufferedWriter writer = new BufferedWriter(new OutputStreamWriter(
                    connection.getOutputStream(),
                    StandardCharsets.UTF_8
            ))) {
                writer.write(buildRequest(prompt).toString());
            }

            int statusCode = connection.getResponseCode();
            String body = readBody(statusCode >= 200 && statusCode < 300
                    ? connection.getInputStream()
                    : connection.getErrorStream());

            if (statusCode < 200 || statusCode >= 300) {
                throw new IOException("LLM request failed with HTTP " + statusCode + ": " + body);
            }

            return parseContent(body);
        } catch (IOException | JSONException exception) {
            throw new IllegalStateException("LLM request failed: " + exception.getMessage(), exception);
        } finally {
            if (connection != null) {
                connection.disconnect();
            }
        }
    }

    private JSONObject buildRequest(String prompt) throws JSONException {
        JSONArray messages = new JSONArray()
                .put(new JSONObject()
                        .put("role", "system")
                        .put("content", "You are Loop, a concise ReAct agent. Reply with Thought and either Action: tool[input] or Final: answer. Use only listed tools."))
                .put(new JSONObject()
                        .put("role", "user")
                        .put("content", prompt));

        return new JSONObject()
                .put("model", provider.getModel())
                .put("messages", messages)
                .put("temperature", 0.2);
    }

    private String parseContent(String body) throws JSONException {
        JSONObject json = new JSONObject(body);
        JSONArray choices = json.getJSONArray("choices");
        if (choices.length() == 0) {
            throw new JSONException("No choices returned.");
        }

        JSONObject message = choices.getJSONObject(0).getJSONObject("message");
        return message.getString("content").trim();
    }

    private String readBody(InputStream stream) throws IOException {
        if (stream == null) {
            return "";
        }

        StringBuilder builder = new StringBuilder();
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(
                stream,
                StandardCharsets.UTF_8
        ))) {
            String line;
            while ((line = reader.readLine()) != null) {
                builder.append(line);
            }
        }
        return builder.toString();
    }
}
