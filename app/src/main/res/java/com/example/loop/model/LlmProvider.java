package com.example.loop.model;

import android.content.Context;

import com.example.loop.R;

public final class LlmProvider {
    private final String name;
    private final String apiKey;
    private final String baseUrl;
    private final String model;

    private LlmProvider(String name, String apiKey, String baseUrl, String model) {
        this.name = name;
        this.apiKey = apiKey;
        this.baseUrl = trimTrailingSlash(baseUrl);
        this.model = model;
    }

    public static LlmProvider fromResources(Context context) {
        return new LlmProvider(
                context.getString(R.string.llm_provider_name),
                context.getString(R.string.llm_api_key),
                context.getString(R.string.llm_base_url),
                context.getString(R.string.llm_model)
        );
    }

    public String getName() {
        return name;
    }

    public String getApiKey() {
        return apiKey;
    }

    public String getBaseUrl() {
        return baseUrl;
    }

    public String getModel() {
        return model;
    }

    public boolean isConfigured() {
        return apiKey != null
                && !apiKey.trim().isEmpty()
                && baseUrl != null
                && !baseUrl.trim().isEmpty()
                && model != null
                && !model.trim().isEmpty();
    }

    public String chatCompletionsUrl() {
        return baseUrl + "/chat/completions";
    }

    private static String trimTrailingSlash(String value) {
        if (value == null) {
            return "";
        }

        String trimmed = value.trim();
        while (trimmed.endsWith("/")) {
            trimmed = trimmed.substring(0, trimmed.length() - 1);
        }
        return trimmed;
    }
}
