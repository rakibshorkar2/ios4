<div align="center">
  <br>
  <img src="https://img.shields.io/badge/DirXplore-v2.0.0+-FF6B6B?style=for-the-badge&logo=appveyor&labelColor=1A1A2E&color=E94560" alt="Version">
  <br><br>
  <h1>📂 DirXplore</h1>
  <p><strong>HTTP/FTP Open Directory Browser & Download Manager</strong></p>
  <p>
    <img src="https://img.shields.io/badge/Flutter-3.5+-02569B?style=flat-square&logo=flutter&logoColor=white" alt="Flutter">
    <img src="https://img.shields.io/badge/Dart-3.5+-0175C2?style=flat-square&logo=dart&logoColor=white" alt="Dart">
    <img src="https://img.shields.io/badge/Platform-Android%20%7C%20iOS-34A853?style=flat-square&logo=android&logoColor=white" alt="Platform">
    <img src="https://img.shields.io/badge/iOS-16.1+-000000?style=flat-square&logo=apple&logoColor=white" alt="iOS">
    <img src="https://img.shields.io/badge/License-MIT-FF6B6B?style=flat-square" alt="License">
    <img src="https://img.shields.io/badge/PRs-Welcome-8A2BE2?style=flat-square" alt="PRs">
  </p>
  <br>
</div>

---

## 🚀 What is DirXplore?

A powerful **open directory browser** and **download manager** for iOS & Android. Browse HTTP/FTP directory listings, download files with resume support, manage downloads in the background, stream media, route traffic through proxies, and more — all in one polished app.

---

## ✨ Features

### 🌐 Directory Browser

| | Feature |
|-|---------|
| 🗂️ | **Smart Parsing** — Auto-detects Apache/Nginx listings, falls back to WebView |
| 🔍 | **Live Search & Filter** — Real-time name filtering + category chips |
| 🧭 | **Breadcrumb Navigation** — Clickable path bar with back/up/history stack |
| 🖼️ | **Grid / List Views** — Toggle between thumbnail grid and compact list |
| ✅ | **Multi-Select** — Long-press bulk selection, batch queue downloads |
| 🔖 | **Bookmarks** — Save/load favorite directories with defaults |
| 📦 | **Download Preview** — Regex + keyword filter before queueing folder downloads |
| 🕸️ | **WebView Fallback** — Built-in `flutter_inappwebview` for non-standard pages |
| 🖼️ | **Thumbnails** — Image previews and file-type color coding |

### 🌪️ BRWSR — Full Web Browser

| | Feature |
|-|---------|
| 📑 | **Multi-Tab** — Tabbed browsing with persistence and tab switcher grid |
| 🚫 | **Ad Blocker** — Built-in ad/tracker domain filtering |
| 🕶️ | **Incognito Mode** — Private tabs with no cache or history |
| 💻 | **Desktop Mode** — Spoof desktop user agent |
| 🔍 | **Find in Page** — Search with match navigation |
| ⬇️ | **Download Interception** — Capture downloads and send to DirXplore's engine |
| 🔄 | **Background Keep-Alive** — Silent audio & location service (iOS) |
| 🟣 | **Live Activity** — Dynamic Island progress for page loads (iOS 16.1+) |

### 📥 Download Manager

| | Feature |
|-|---------|
| ⚡ | **Concurrent Downloads** — Configurable 1–10 simultaneous |
| ⏯️ | **Pause / Resume** — HTTP `Range` headers with `206 Partial Content` |
| 🔄 | **Auto-Retry** — Configurable retry count & delay |
| 📊 | **Speed & ETA** — Real-time speed (EMA smoothing) + remaining time |
| 📦 | **Batch Grouping** — Expandable folder-level progress tiles |
| 📋 | **Queue Export/Import** — JSON backup via share sheet / file picker |
| 🔐 | **Hash Verification** — MD5 / SHA1 / SHA256 via Dart isolate + native FFI |
| 💾 | **Storage Analyzer** — Free/total disk space with usage bar |
| 🔗 | **Refresh Link** — Re-validate expired URLs |
| 📁 | **Share & Save** — Share files, open location, Save to Files (iOS) |

### 🛡️ Proxy Manager

| | Feature |
|-|---------|
| 🔌 | **Protocols** — SOCKS4, SOCKS5, HTTP, HTTPS |
| 📦 | **Pre-loaded List** — ~75 proxies from bundled `bypassempire.yaml` |
| ✏️ | **Manual Add** — Host, port, username, password |
| 📥 | **Bulk Import** — Paste multiple proxy URIs at once |
| 📄 | **YAML Import** — Clash-compatible proxy config files |
| ⏱️ | **Latency Testing** — TCP connect latency per proxy or test all |
| 🔄 | **iOS Native Sync** — Proxy → `URLSession.connectionProxyDictionary` |
| 🚫 | **Local Bypass** — `127.x.x.x`, `localhost` not proxied |

### 🎬 Media Player

| | Feature |
|-|---------|
| 🎥 | **Engine** — `media_kit` (libmpv-based) with HW/SW decoder toggle |
| 📺 | **URL Streaming** — Stream from URLs including proxy tunnel (port 8080) |
| 📜 | **Playlist** — Next/Previous with playlist bottom sheet |
| 🎚️ | **Playback Speed** — 0.25x – 2.0x |
| 🔁 | **A-B Repeat** — Loop between set start/end points |
| 🚀 | **Rocket Mode** — Enhanced sensitivity seeking |
| 🔒 | **Screen Lock** — Prevent accidental touches |
| ✋ | **Gesture Controls** — Brightness, Volume, Seek, Double-tap ±10s |
| 🔄 | **Resume Playback** — Position saved via SharedPreferences |

### 📋 Smart Clipboard Manager

| | Feature |
|-|---------|
| 🤖 | **Auto-Monitoring** — Polls clipboard every 3s |
| 🏷️ | **Smart Detection** — Auto-detects URL, Email, Phone, JSON, Code, Color, File Path, Image, Rich Text |
| 🔍 | **Filter Chips** — Filter by content type |
| 🔎 | **Search** — Full-text search across clipboard history |
| ✅ | **Multi-Select** — Batch favorite, delete operations |
| 👆 | **Swipe Actions** — Swipe left to copy, right to delete |
| 📄 | **Rich Previews** — URL preview, syntax-highlighted code, color swatches, image viewer |
| 📤 | **Export/Import** — Export as TXT/JSON/CSV, Import from JSON/TXT |

### 🔒 Security & Privacy

| | Feature |
|-|---------|
| 👤 | **Biometric Auth** — Face ID / Touch ID (iOS) & fingerprint (Android) |
| 🔢 | **Custom PIN Lock** — 4–6 digit PIN with on-screen numpad |
| 🔐 | **PIN Recovery** — Security question/answer for forgotten PIN |
| ⏱️ | **Inactivity Auto-Lock** — Lock after 0s, 30s, 1m, or 2m |
| 🌫️ | **Privacy HUD** — Blurred backdrop when locked |
| 🔄 | **Background Blur** — Auto-locks with blur when app is backgrounded |

---

## 📱 iOS Native Features

| Feature | iOS Version | Framework |
|---------|:-----------:|:----------|
| **Live Activities** (Dynamic Island) | 16.1+ | `ActivityKit` |
| **Lock Screen Widget** | 16.1+ | `WidgetKit` |
| **Background Downloads** | 7.0+ | `URLSession` |
| **Persistent Folder Access** | 11.0+ | Security-scoped bookmarks |
| **Document Picker** | 11.0+ | `UIDocumentPickerViewController` |
| **Share Sheet** | 6.0+ | `UIActivityViewController` |
| **Face ID / Touch ID** | 8.0+ | `LocalAuthentication` |
| **Local Notifications** | 10.0+ | `UserNotifications` |

```
┌──────────────────────┐
│  🔽 MyFile.zip       │
│  ████████░░ 62%      │  ← Dynamic Island / Lock Screen
│  3.2 MB/s  │  1m 24s │
└──────────────────────┘
```

---

## 🛠️ Tech Stack

```
Flutter 3.5+  │  Dart 3.5+  │  Swift  │  Kotlin  │  C++  │  Go
```

| Area | Technologies |
|------|-------------|
| **UI** | Flutter, CupertinoTabScaffold, Provider (state management) |
| **Networking** | Dio, HTTP, SOCKS5 proxy tunnel, flutter_inappwebview |
| **Storage** | SQLite (sqflite), SharedPreferences, file_picker, share_plus |
| **Media** | media_kit (libmpv-based video player) |
| **Security** | local_auth (biometrics), crypto (hashing), custom PIN with recovery |
| **Background** | flutter_local_notifications, flutter_background_service, workmanager |
| **iOS Native** | URLSession background config, ActivityKit (Live Activities), WidgetKit |
| **Native FFI** | Go (BFS crawler), C++ (file I/O & hashing), Dart Isolates |
| **Permissions** | permission_handler, wakelock_plus, battery_plus, connectivity_plus |

---

## 🏗️ Architecture

```
┌──────────────────────────────────────────┐
│              Flutter UI Layer             │
│  Browser · BRWSR · Downloads · Proxy     │
│  Clipboard · Settings · Media Player     │
├──────────────────────────────────────────┤
│           Provider Layer (State)          │
│  AppState · Browser · BRWSR · Download   │
│  Proxy · Clipboard                       │
├──────────────────┬───────────────────────┤
│   Dart Services  │   MethodChannel       │
│   Dio · SQLite   │       │               │
│   HTML Parser    │       ▼               │
│   Proxy Tunnel   │  ┌─────────────────┐  │
│   Isolates       │  │ DownloadPlugin  │  │
│                  │  │ (Swift)         │  │
│  ┌────────────┐  │  │ URLSession      │  │
│  │ Go FFI     │  │  │ ActivityKit     │  │
│  │ C++ FFI    │  │  │ Proxy Config    │  │
│  └────────────┘  │  └─────────────────┘  │
└──────────────────┴───────────────────────┘
```

---

## 🚀 Getting Started

```bash
# Clone
git clone https://github.com/rakibshorkar2/ios3.git

# Install dependencies
flutter pub get

# Run
flutter run

# Build for iOS
flutter build ios --release --no-codesign

# Build for Android
flutter build apk --release
```

---

<div align="center">
  <br>
  <p>
    <a href="https://github.com/rakibshorkar2"><img src="https://img.shields.io/badge/GitHub-rakibshorkar2-181717?style=for-the-badge&logo=github" alt="GitHub"></a>
    <a href="https://github.com/rakibshorkar2/ios3"><img src="https://img.shields.io/badge/Repo-ios3-FF6F00?style=for-the-badge&logo=git" alt="Repo"></a>
  </p>
  <br>
  <p><strong>✨ Created by RAKIB ✨</strong></p>
  <br>
</div>
