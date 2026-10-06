// SPDX-License-Identifier: GPL-3.0-only
package local.carplay.localentry;

import android.app.Activity;
import android.content.Intent;
import android.net.VpnService;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;

public final class MainActivity extends Activity {
    private final Handler handler = new Handler(Looper.getMainLooper());
    private TextView state;
    private final Runnable refresh = new Runnable() {
        @Override public void run() {
            if (state != null) state.setText(LocalEntryService.status);
            handler.postDelayed(this, 1000L);
        }
    };

    @Override public void onCreate(Bundle savedState) {
        super.onCreate(savedState);
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        int margin = (int) (20 * getResources().getDisplayMetrics().density);
        layout.setPadding(margin, margin, margin, margin);
        TextView explanation = new TextView(this);
        explanation.setTextSize(18);
        explanation.setText("CarPlay 本地入口\n\n" +
            "先让 WheelPlay 连接 iPhone，再启动这里的入口。\n" +
            "先开 Android 系统个人热点，显示设备加入同一热点。\n\n" +
            "浏览器地址：http://7.7.7.1:8080/\n" +
            "画面和触控通过局域网传输。\n\n" +
            "启动会占用系统 VPN 位置，其他 VPN 会停止。\n" +
            "入口持续运行至手动停止、VPN 撤销或系统终止应用。\n" +
            "手机重启后，先恢复 CarPlay，再启动入口。\n");
        layout.addView(explanation);
        state = new TextView(this);
        state.setTextSize(18);
        layout.addView(state);
        Button start = new Button(this);
        start.setText("启动本地入口");
        start.setOnClickListener(view -> {
            Intent consent = VpnService.prepare(this);
            if (consent == null) startTest();
            else startActivityForResult(consent, 1);
        });
        layout.addView(start);
        Button stop = new Button(this);
        stop.setText("停止并回滚");
        stop.setOnClickListener(view -> startService(new Intent(this, LocalEntryService.class).setAction("STOP")));
        layout.addView(stop);
        setContentView(layout);
        String diagnosticAction = getIntent().getAction();
        if ("VERIFY_TIMEOUT".equals(diagnosticAction)) {
            // Used by ADB diagnostics after the user has already granted VPN consent.
            // The service remains protected by BIND_VPN_SERVICE. No shell permission
            // grant or automatic acceptance of a system consent dialog is attempted.
            if (VpnService.prepare(this) == null) {
                Intent service = new Intent(this, LocalEntryService.class);
                service.setAction("VERIFY_TIMEOUT");
                startForegroundService(service);
            } else {
                LocalEntryService.status = "需要系统 VPN 授权，请手动点击启动入口";
            }
        }
    }

    private void startTest() {
        startForegroundService(new Intent(this, LocalEntryService.class));
    }

    @Override protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == 1 && resultCode == RESULT_OK) startTest();
    }

    @Override protected void onResume() { super.onResume(); handler.post(refresh); }
    @Override protected void onPause() { handler.removeCallbacks(refresh); super.onPause(); }
}
