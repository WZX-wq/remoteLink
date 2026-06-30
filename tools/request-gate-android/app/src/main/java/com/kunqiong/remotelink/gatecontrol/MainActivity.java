package com.kunqiong.remotelink.gatecontrol;

import android.app.Activity;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import java.io.BufferedReader;
import java.io.OutputStream;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import org.json.JSONObject;

public class MainActivity extends Activity {
    private static final String PREFS = "request_gate_control";
    private static final String DEFAULT_API_BASE = "https://remotelink.kunqiongai.com/kq-api/api";
    private static final String DEFAULT_ADMIN_TOKEN = "qwertyuiopasdfghjklzxcvbnm";
    private static final String DEFAULT_MESSAGE = "服务维护中，请稍后再试";

    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    private EditText serverInput;
    private EditText tokenInput;
    private EditText messageInput;
    private TextView statusText;
    private TextView detailText;
    private Button refreshButton;
    private Button toggleButton;
    private boolean acceptingRequests = true;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        buildContentView();
        loadSettings();
        refreshGate();
    }

    @Override
    protected void onDestroy() {
        executor.shutdownNow();
        super.onDestroy();
    }

    private void buildContentView() {
        ScrollView scrollView = new ScrollView(this);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(20), dp(22), dp(20), dp(24));
        scrollView.addView(root);

        TextView title = new TextView(this);
        title.setText("中间服务开关");
        title.setTextSize(24);
        title.setTextColor(Color.rgb(17, 24, 39));
        title.setGravity(Gravity.START);
        title.setTypeface(null, 1);
        root.addView(title, matchWrap());

        TextView subtitle = new TextView(this);
        subtitle.setText("控制业务 API 是否接受请求，健康检查和下载入口会保持可用。");
        subtitle.setTextSize(14);
        subtitle.setTextColor(Color.rgb(75, 85, 99));
        subtitle.setPadding(0, dp(8), 0, dp(18));
        root.addView(subtitle, matchWrap());

        statusText = new TextView(this);
        statusText.setTextSize(20);
        statusText.setTypeface(null, 1);
        statusText.setPadding(dp(16), dp(14), dp(16), dp(14));
        root.addView(statusText, matchWrap());

        detailText = new TextView(this);
        detailText.setTextSize(13);
        detailText.setTextColor(Color.rgb(75, 85, 99));
        detailText.setPadding(0, dp(14), 0, dp(14));
        root.addView(detailText, matchWrap());

        serverInput = input("服务器 API 地址");
        serverInput.setSingleLine(true);
        root.addView(label("服务器"));
        root.addView(serverInput, matchWrap());

        tokenInput = input("管理密钥");
        tokenInput.setSingleLine(true);
        tokenInput.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
        root.addView(label("管理密钥"));
        root.addView(tokenInput, matchWrap());

        messageInput = input(DEFAULT_MESSAGE);
        messageInput.setMinLines(2);
        messageInput.setGravity(Gravity.TOP | Gravity.START);
        root.addView(label("维护提示"));
        root.addView(messageInput, matchWrap());

        LinearLayout buttons = new LinearLayout(this);
        buttons.setOrientation(LinearLayout.HORIZONTAL);
        buttons.setGravity(Gravity.CENTER_VERTICAL);
        buttons.setPadding(0, dp(18), 0, 0);
        root.addView(buttons, matchWrap());

        refreshButton = new Button(this);
        refreshButton.setText("刷新状态");
        refreshButton.setOnClickListener(v -> refreshGate());
        buttons.addView(refreshButton, new LinearLayout.LayoutParams(0, dp(48), 1));

        toggleButton = new Button(this);
        toggleButton.setText("切换");
        toggleButton.setOnClickListener(v -> toggleGate());
        LinearLayout.LayoutParams toggleParams = new LinearLayout.LayoutParams(0, dp(48), 1);
        toggleParams.setMargins(dp(12), 0, 0, 0);
        buttons.addView(toggleButton, toggleParams);

        setContentView(scrollView);
        renderStatus(true, "正在读取状态...");
    }

    private TextView label(String text) {
        TextView view = new TextView(this);
        view.setText(text);
        view.setTextSize(13);
        view.setTextColor(Color.rgb(55, 65, 81));
        view.setPadding(0, dp(12), 0, dp(6));
        return view;
    }

    private EditText input(String hint) {
        EditText editText = new EditText(this);
        editText.setTextSize(15);
        editText.setHint(hint);
        editText.setPadding(dp(12), 0, dp(12), 0);
        return editText;
    }

    private LinearLayout.LayoutParams matchWrap() {
        return new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        );
    }

    private void loadSettings() {
        SharedPreferences prefs = getSharedPreferences(PREFS, MODE_PRIVATE);
        serverInput.setText(prefs.getString("server", DEFAULT_API_BASE));
        String savedToken = prefs.getString("token", DEFAULT_ADMIN_TOKEN);
        tokenInput.setText(savedToken == null || savedToken.trim().isEmpty()
            ? DEFAULT_ADMIN_TOKEN
            : savedToken);
        messageInput.setText(prefs.getString("message", DEFAULT_MESSAGE));
    }

    private void saveSettings() {
        getSharedPreferences(PREFS, MODE_PRIVATE)
            .edit()
            .putString("server", serverInput.getText().toString().trim())
            .putString("token", tokenInput.getText().toString())
            .putString("message", messageInput.getText().toString().trim())
            .apply();
    }

    private void refreshGate() {
        saveSettings();
        setBusy(true, "正在读取状态...");
        executor.execute(() -> {
            try {
                JSONObject json = request("GET", null);
                JSONObject gate = json.getJSONObject("gate");
                acceptingRequests = gate.optBoolean("accepting_requests", true);
                String message = gate.optString("message", DEFAULT_MESSAGE);
                String updatedAt = gate.optString("updated_at", "");
                mainHandler.post(() -> {
                    setBusy(false, "");
                    renderStatus(acceptingRequests, message);
                    detailText.setText(updatedAt.isEmpty() ? "状态已同步" : "最后更新：" + updatedAt);
                });
            } catch (Exception error) {
                mainHandler.post(() -> showError(error));
            }
        });
    }

    private void toggleGate() {
        saveSettings();
        boolean nextAccepting = !acceptingRequests;
        String message = nextAccepting ? "服务正常" : cleanMessage();
        setBusy(true, nextAccepting ? "正在恢复服务..." : "正在进入维护模式...");
        executor.execute(() -> {
            try {
                JSONObject body = new JSONObject()
                    .put("accepting_requests", nextAccepting)
                    .put("message", message);
                JSONObject json = request("POST", body);
                JSONObject gate = json.getJSONObject("gate");
                acceptingRequests = gate.optBoolean("accepting_requests", true);
                String responseMessage = gate.optString("message", message);
                String updatedAt = gate.optString("updated_at", "");
                mainHandler.post(() -> {
                    setBusy(false, "");
                    renderStatus(acceptingRequests, responseMessage);
                    detailText.setText(updatedAt.isEmpty() ? "切换完成" : "最后更新：" + updatedAt);
                });
            } catch (Exception error) {
                mainHandler.post(() -> showError(error));
            }
        });
    }

    private String cleanMessage() {
        String text = messageInput.getText().toString().trim();
        return text.isEmpty() ? DEFAULT_MESSAGE : text;
    }

    private void setBusy(boolean busy, String text) {
        refreshButton.setEnabled(!busy);
        toggleButton.setEnabled(!busy);
        if (!text.isEmpty()) {
            detailText.setText(text);
        }
    }

    private void renderStatus(boolean accepting, String message) {
        int color = accepting ? Color.rgb(22, 163, 74) : Color.rgb(220, 38, 38);
        statusText.setText(accepting ? "正在接受请求" : "维护中，已暂停业务请求");
        statusText.setTextColor(color);
        statusText.setBackgroundColor(accepting ? Color.rgb(240, 253, 244) : Color.rgb(254, 242, 242));
        toggleButton.setText(accepting ? "暂停请求" : "恢复请求");
        if (!accepting && !message.isEmpty()) {
            messageInput.setText(message);
        }
    }

    private void showError(Exception error) {
        setBusy(false, "");
        detailText.setText("请求失败：" + error.getMessage());
        detailText.setTextColor(Color.rgb(185, 28, 28));
    }

    private JSONObject request(String method, JSONObject body) throws Exception {
        URL url = new URL(endpointUrl());
        HttpURLConnection connection = (HttpURLConnection) url.openConnection();
        connection.setRequestMethod(method);
        connection.setConnectTimeout(12000);
        connection.setReadTimeout(12000);
        connection.setRequestProperty("Accept", "application/json");
        connection.setRequestProperty("x-kq-admin-token", tokenInput.getText().toString());
        if (body != null) {
            byte[] bytes = body.toString().getBytes(StandardCharsets.UTF_8);
            connection.setDoOutput(true);
            connection.setRequestProperty("Content-Type", "application/json; charset=utf-8");
            connection.setFixedLengthStreamingMode(bytes.length);
            try (OutputStream out = connection.getOutputStream()) {
                out.write(bytes);
            }
        }
        int code = connection.getResponseCode();
        String text = readText(code >= 400 ? connection.getErrorStream() : connection.getInputStream());
        if (code < 200 || code >= 300) {
            String message = text;
            try {
                message = new JSONObject(text).optString("error", text);
            } catch (Exception ignored) {
            }
            throw new IllegalStateException(code + " " + message);
        }
        return new JSONObject(text);
    }

    private String endpointUrl() {
        String base = serverInput.getText().toString().trim();
        if (base.isEmpty()) {
            base = DEFAULT_API_BASE;
        }
        while (base.endsWith("/")) {
            base = base.substring(0, base.length() - 1);
        }
        if (base.endsWith("/admin/request-gate")) {
            return base;
        }
        return base + "/admin/request-gate";
    }

    private String readText(InputStream stream) throws Exception {
        if (stream == null) return "";
        StringBuilder builder = new StringBuilder();
        try (BufferedReader reader = new BufferedReader(
            new InputStreamReader(stream, StandardCharsets.UTF_8)
        )) {
            String line;
            while ((line = reader.readLine()) != null) {
                builder.append(line);
            }
        }
        return builder.toString();
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }
}
