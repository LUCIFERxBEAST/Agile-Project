# Flutter Operator Portal: Cloud-Native Infrastructure Monitoring

A cross-platform real-time monitoring and incident remediation dashboard engineered in Flutter (Dart). Supports **Linux Desktop**, **Android Mobile**, and **Web**.

---

## 📱 Features & Capabilities

- **Real-Time Dual-Line Charts**: Interactive `fl_chart` visualization streaming live CPU % (Cyan) and RAM % (Orange) with adaptive time scaling.
- **Server Fleet Dropdown**: Dynamic server discovery via `GET /GetServers` with parameterized filtering (`?server_id=<id>`).
- **Dynamic Spike Alert Banner**: Automatically surfaces when a monitored host sustains >= 85.0% CPU, displaying the offending process name, PID, and a single-tap **Kill Process** button.
- **Human-in-the-Loop Safety Modal**: Derives an 8-character cryptographic token (`sha256(server_id:pid:cmd)[:8]`) and requires typing the code (or executable name) to unlock the termination trigger.
- **Signal Selection**: Toggle between graceful termination (`SIGTERM -15`) and immediate kernel kill (`SIGKILL -9`).
- **Zero-Trust In-Memory Authentication**: API keys remain strictly in RAM during session lifecycle (never persisted unencrypted to disk).

---

## 🚀 Running & Building

### 1. Run on Linux Desktop
```bash
flutter run -d linux \
  --dart-define=API_BASE_URL=https://<api-id>.execute-api.ap-southeast-2.amazonaws.com/Prod \
  --dart-define=API_KEY=<YOUR_API_KEY>
```

### 2. Build Release Android APK
```bash
flutter build apk --release \
  --dart-define=API_BASE_URL=https://<api-id>.execute-api.ap-southeast-2.amazonaws.com/Prod \
  --dart-define=API_KEY=<YOUR_API_KEY>
```

> **Important (`/Prod` Stage Requirement)**: `main.dart` expects `API_BASE_URL` **with the `/Prod` suffix** (e.g., `https://<api-id>.execute-api.ap-southeast-2.amazonaws.com/Prod`). The app directly appends `/GetMetrics`, `/GetServers`, and `/ExecuteCommand` to `API_BASE_URL`. Omitting `/Prod` will cause AWS API Gateway to reject requests with `403 Missing Authentication Token`.
The resulting APK is generated at:
`build/app/outputs/flutter-apk/app-release.apk` (copied to project root as `Cloud_Native_Telemetry_App.apk`).

### 3. Install on Android Phone
```bash
adb install Cloud_Native_Telemetry_App.apk
```

---

## 🧪 Testing & Code Quality

```bash
flutter analyze  # 0 issues found
flutter test     # 4/4 widget tests passed
```
