package com.del7a.nativelogs;
import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.util.LinkedList;

import org.apache.cordova.CallbackContext;
import org.apache.cordova.CordovaInterface;
import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.CordovaWebView;
import org.apache.cordova.LOG;
import org.apache.cordova.PluginResult;
import org.json.JSONArray;
import org.json.JSONException;

import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;

public class NativeLogs extends CordovaPlugin {

    private final String LOG_TAG = "CDVLOGCAT";
    private CallbackContext logCallbackContext;
    private Thread logMonitorThread;
    private Process logcatProcess;
    private volatile boolean isMonitoring = false;

    private void clearLog() {

        LOG.d(LOG_TAG, "clearLog");

        try {
            Runtime.getRuntime().exec("logcat -c");
        }
        catch (Exception ex) {
            ex.printStackTrace();
        }
    }

    @Override
    public void initialize(CordovaInterface cordova, CordovaWebView webView) {

        super.initialize(cordova, webView);
        this.clearLog();
    }

    @Override
    public void onDestroy() {
        stopLogMonitoring();
        super.onDestroy();
    }

    private void startLogMonitoring() {
        isMonitoring = true;

        // Get the app's process ID to filter logs
        final int pid = android.os.Process.myPid();

        logMonitorThread = new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    // Filter logcat to only show logs from this app's process
                    // --pid requires API 24+, so we use grep-style filtering via the pid in the output
                    String[] command = new String[] {
                        "logcat",
                        "-v", "brief",      // Use brief format for easier parsing
                        "--pid=" + pid      // Filter by process ID (API 24+)
                    };

                    // For older devices, fall back to unfiltered and filter manually
                    if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.N) {
                        command = new String[] { "logcat", "-v", "brief" };
                    }

                    logcatProcess = Runtime.getRuntime().exec(command);
                    BufferedReader reader = new BufferedReader(
                        new InputStreamReader(logcatProcess.getInputStream()));

                    // For older devices, we need to filter by PID manually
                    final String pidFilter = "(" + pid + ")";
                    final boolean needsManualFilter = android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.N;

                    String line;
                    while (isMonitoring && (line = reader.readLine()) != null) {
                        // Skip empty lines
                        if (line.length() == 0) continue;

                        // For older devices, manually filter by PID
                        if (needsManualFilter && !line.contains(pidFilter)) {
                            continue;
                        }

                        if (logCallbackContext != null) {
                            final String logLine = line;
                            cordova.getActivity().runOnUiThread(new Runnable() {
                                @Override
                                public void run() {
                                    if (logCallbackContext != null) {
                                        PluginResult result = new PluginResult(PluginResult.Status.OK, logLine);
                                        result.setKeepCallback(true);
                                        logCallbackContext.sendPluginResult(result);
                                    }
                                }
                            });
                        }
                    }

                    reader.close();
                } catch (IOException e) {
                    LOG.e(LOG_TAG, "Error monitoring logcat", e);
                }
            }
        });

        logMonitorThread.start();
    }

    private void stopLogMonitoring() {
        isMonitoring = false;

        if (logcatProcess != null) {
            logcatProcess.destroy();
            logcatProcess = null;
        }

        if (logMonitorThread != null) {
            logMonitorThread.interrupt();
            try {
                logMonitorThread.join(1000);
            } catch (InterruptedException e) {
                // Ignore
            }
            logMonitorThread = null;
        }

        logCallbackContext = null;
    }

    private  String getLogsFromLogCat(int _nbLines) {

        LinkedList<String> logs = new LinkedList<String>();

        try {
            Process process = Runtime.getRuntime().exec("logcat -d");
            BufferedReader bufferedReader = new BufferedReader(
                    new InputStreamReader(process.getInputStream()));

            String line ;
            while (( line = bufferedReader.readLine()) != null) {
                logs.add(line);
            }

        } catch (IOException e) {
            e.printStackTrace();
        }

        String log = "";

        int nb = 0;
        while( (nb < _nbLines) && (logs.size() > 0) ) {
            log += logs.getLast();
            log += "\n";
            logs.removeLast();
            nb++;
        }
        return log;
    }

    public boolean execute(String action, JSONArray args, CallbackContext callbackContext)
            throws JSONException {

        if (action.equals("init")) {
            // Stop any existing monitoring
            stopLogMonitoring();

            this.logCallbackContext = callbackContext;
            startLogMonitoring();

            // Send initial success response
            PluginResult result = new PluginResult(PluginResult.Status.OK, "Log monitoring started");
            result.setKeepCallback(true);
            callbackContext.sendPluginResult(result);
            return true;

        } else if (action.equals("stop")) {
            stopLogMonitoring();
            callbackContext.success("Log monitoring stopped");
            return true;

        } else if (action.equals("getLog")) {

            int nbLines = args.getInt(0);
            boolean bCopyToClipBoard = args.getBoolean(1);

            String log = getLogsFromLogCat(nbLines);

            if (bCopyToClipBoard) {
                ClipboardManager clipboard = (ClipboardManager) cordova.getActivity().getSystemService(Context.CLIPBOARD_SERVICE);
                ClipData clip = ClipData.newPlainText("logcat", log);
                clipboard.setPrimaryClip(clip);
            }
            callbackContext.success(log);
            return true;

        }
        else
            return false;
    }


}
