package com.example.loop;

import android.app.Activity;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.InputType;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.View;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputMethodManager;
import android.content.Context;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import com.example.loop.agent.AgentEvent;
import com.example.loop.agent.ReActAgentRunner;
import com.example.loop.agent.ToolRegistry;
import com.example.loop.model.LlmProvider;
import com.example.loop.model.LocalModel;
import com.example.loop.model.OpenAiCompatibleModel;
import com.example.loop.model.ScriptedLocalModel;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class MainActivity extends Activity {
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final ExecutorService executor = Executors.newSingleThreadExecutor();

    private static final int MAX_STEPS = 4;

    private EditText messageInput;
    private TextView transcript;
    private ScrollView scrollView;
    private Button sendButton;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(createContentView());
    }

    @Override
    protected void onDestroy() {
        executor.shutdownNow();
        super.onDestroy();
    }

    private View createContentView() {
        int pagePadding = dp(14);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.rgb(250, 250, 248));
        root.setPadding(pagePadding, pagePadding, pagePadding, pagePadding);

        scrollView = new ScrollView(this);
        scrollView.setFillViewport(true);

        transcript = new TextView(this);
        transcript.setTextColor(Color.rgb(23, 33, 43));
        transcript.setTextSize(16);
        transcript.setLineSpacing(dp(3), 1f);
        transcript.setGravity(Gravity.BOTTOM | Gravity.START);
        transcript.setPadding(dp(4), dp(4), dp(4), dp(12));
        transcript.setText("Loop is ready.\n");
        scrollView.addView(transcript, matchWrap());

        root.addView(scrollView, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                0,
                1f
        ));

        LinearLayout composer = new LinearLayout(this);
        composer.setOrientation(LinearLayout.HORIZONTAL);
        composer.setGravity(Gravity.BOTTOM);
        composer.setPadding(0, dp(10), 0, 0);

        messageInput = new EditText(this);
        messageInput.setHint("Message Loop");
        messageInput.setMinLines(1);
        messageInput.setMaxLines(5);
        messageInput.setSingleLine(false);
        messageInput.setGravity(Gravity.CENTER_VERTICAL | Gravity.START);
        messageInput.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_MULTI_LINE);
        messageInput.setImeOptions(EditorInfo.IME_ACTION_SEND);
        messageInput.setBackground(makeInputBackground());
        messageInput.setPadding(dp(14), 0, dp(14), 0);
        messageInput.setOnEditorActionListener((view, actionId, event) -> {
            boolean sendAction = actionId == EditorInfo.IME_ACTION_SEND;
            boolean enterSend = event != null
                    && event.getKeyCode() == KeyEvent.KEYCODE_ENTER
                    && event.getAction() == KeyEvent.ACTION_UP
                    && !event.isShiftPressed();
            if (sendAction || enterSend) {
                runAgent();
                return true;
            }
            return false;
        });

        LinearLayout.LayoutParams inputParams = new LinearLayout.LayoutParams(
                0,
                dp(52),
                1f
        );
        composer.addView(messageInput, inputParams);

        sendButton = new Button(this);
        sendButton.setText("Send");
        sendButton.setTextColor(Color.WHITE);
        sendButton.setBackgroundColor(Color.rgb(23, 107, 135));
        sendButton.setOnClickListener(view -> runAgent());
        LinearLayout.LayoutParams sendParams = new LinearLayout.LayoutParams(dp(86), dp(52));
        sendParams.setMargins(dp(8), 0, 0, 0);
        composer.addView(sendButton, sendParams);

        root.addView(composer, matchWrap());
        return root;
    }

    private void runAgent() {
        String task = messageInput.getText().toString().trim();
        if (task.isEmpty()) {
            return;
        }

        appendUserMessage(task);
        messageInput.setText("");
        hideKeyboard();
        setSending(true);

        executor.execute(() -> {
            ReActAgentRunner runner = new ReActAgentRunner(
                    createModel(),
                    new ToolRegistry(),
                    MAX_STEPS
            );
            runner.run(task, event -> mainHandler.post(() -> addEvent(event)));
            mainHandler.post(() -> {
                setSending(false);
            });
        });
    }

    private LocalModel createModel() {
        LlmProvider provider = LlmProvider.fromResources(this);
        if (provider.isConfigured()) {
            return new OpenAiCompatibleModel(provider);
        }
        return new ScriptedLocalModel();
    }

    private void addEvent(AgentEvent event) {
        switch (event.getKind()) {
            case THOUGHT:
                appendLine("Loop", event.getText());
                break;
            case ACTION:
                appendLine("Tool", event.getText());
                break;
            case OBSERVATION:
                appendLine("Observation", event.getText());
                break;
            case FINAL:
                appendLine("Loop", event.getText());
                break;
            case ERROR:
            default:
                appendLine("Error", event.getText());
                break;
        }
    }

    private void appendUserMessage(String message) {
        appendLine("You", message);
    }

    private void appendLine(String speaker, String text) {
        String current = transcript.getText().toString();
        String prefix = current.trim().isEmpty() ? "" : "\n\n";
        transcript.append(prefix + speaker + "\n" + text);
        scrollView.post(() -> scrollView.fullScroll(View.FOCUS_DOWN));
    }

    private void setSending(boolean sending) {
        sendButton.setEnabled(!sending);
        sendButton.setText(sending ? "..." : "Send");
        messageInput.setEnabled(!sending);
    }

    private void hideKeyboard() {
        InputMethodManager manager = (InputMethodManager) getSystemService(Context.INPUT_METHOD_SERVICE);
        if (manager != null) {
            manager.hideSoftInputFromWindow(messageInput.getWindowToken(), 0);
        }
    }

    private GradientDrawable makeInputBackground() {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(Color.WHITE);
        drawable.setCornerRadius(dp(20));
        drawable.setStroke(dp(1), Color.rgb(220, 224, 226));
        return drawable;
    }

    private LinearLayout.LayoutParams matchWrap() {
        return new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
        );
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }
}
