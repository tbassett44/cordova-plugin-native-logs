# Cordova-Plugin-Native-Logs
A Cordova plugin to retrieve native logs directly from your app to let your users easily share them with you for troubleshooting.
Those logs will be identical to the ones retrieved by the `adb logcat` command (Android), or displayed in XCode debugger (iOS).

#### Platform support

* iOS
* Android

#### Installing

```
cordova plugin add cordova-plugin-native-logs
```

#### Uninstalling

```
cordova plugin remove cordova-plugin-native-logs
```

---

## Usage

### Real-time Log Monitoring

Use `init()` to start receiving native log messages in real-time via a callback. This is useful for displaying native logs in your app's console or sending them to a remote logging service.

```javascript
NativeLogs.init(logCallback, successCB, failureCB)
```

##### Params
* `logCallback`: callback function that receives each log message as it occurs: `function(logMessage)`
* `successCB`: callback called on successful initialization
* `failureCB`: callback called if initialization fails

##### Example

```javascript
// Start receiving native logs
NativeLogs.init(
    function(logMessage) {
        console.log('[Native]', logMessage);
    },
    function(status) {
        console.log('Log monitoring started:', status);
    },
    function(error) {
        console.error('Failed to start log monitoring:', error);
    }
);
```

### Stop Log Monitoring

Use `stop()` to stop receiving real-time log messages.

```javascript
NativeLogs.stop(successCB, failureCB)
```

##### Example

```javascript
NativeLogs.stop(
    function() {
        console.log('Log monitoring stopped');
    },
    function(error) {
        console.error('Error stopping log monitoring:', error);
    }
);
```

### Get Log History

Use `getLog()` to retrieve the latest available logs as a single string.

```javascript
NativeLogs.getLog(_nbLines, _bCopyToClipboard, _successCB, _failureCB)
```

##### Params
* `_nbLines`: maximum number of lines to retrieve
* `_bCopyToClipboard`: copy the logs to the clipboard to let the user easily share it
* `_successCB`: callback that will receive the log as a string
* `_failureCB`: callback called if retrieval fails

##### Example

```javascript
NativeLogs.getLog(1000, false, function(_logs) {
    // do something with the logs
    console.log(_logs);
});
```

---

## Platform Notes

### iOS
- Captures `stderr` output (NSLog messages) by redirecting to a file
- Real-time monitoring uses file system events to detect new log entries

### Android
- Uses `logcat` to capture system logs
- Real-time monitoring filters logs to only show messages from your app's process (using `--pid` on API 24+)
- On older Android versions (< API 24), logs are filtered manually by process ID

---

## Ionic Framework Support

To use the plugin in your project, just add this declaration:
```typescript
declare var NativeLogs: any;
```

A complete functional sample is available in the `sample/` directory in the github website: https://github.com/ogoguel/cordova-plugin-native-logs

To build it:
```
cd sample/
ionic state reset
ionic run ios
ionic run android
```

#### Screenshots
![IOS Screenshot](https://raw.githubusercontent.com/ogoguel/cordova-plugin-native-logs/master/sample/screenshots/ios.png)

---

## Send logs through Email

This plugin can be used in conjunction with mail composer plugin to let the user send the log via email.

---

## History

* v1.2.0 Added real-time log monitoring with `init()` and `stop()` methods
* v1.1.1 Previous release
* v1.0.5 Fix version mismatched
* v1.0.4 Fix NPM deployment
* v1.0.3 Fix invalid log count (cf. issue #1)
* v1.0.2 Fix typo in documentation
* v1.0.1 Initial release