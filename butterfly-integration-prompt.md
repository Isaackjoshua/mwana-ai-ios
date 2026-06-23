# Butterfly iQ Probe Integration — Claude Code Prompt

## Task: Integrate Butterfly iQ Probe into Mwana-AI

### Context

Mwana-AI is a Flutter iOS app for on-device breast cancer screening.
**Repo:** <https://github.com/Isaackjoshua/mwana-ai-ios>

**Current flow:** user picks ultrasound image → validation → ONNX inference (ResNet50 U-Net, 3-class + segmentation) → BI-RADS grading → on-device Gemma 4 report → PDF export. Everything runs on-device.

**Goal:** Add live ultrasound acquisition from a Butterfly iQ probe as a new image source, using the Butterfly ImagingSDK-iOS.

**SDK repo:** <https://github.com/ButterflyNetwork/ImagingSDK-iOS>

### SDK Credentials

I have valid SDK credentials:

- **Access Key:** `[will provide when prompted — do not hardcode in source]`
- **Customer Key:** `[will provide when prompted — do not hardcode in source]`

Store these in a secure configuration that is gitignored (e.g., `ios/Runner/ButterflyConfig.xcconfig` added to `.gitignore`, or via environment variables at build time). **NEVER commit keys to git.**

---

## Decision Framework: Flutter Integration vs Swift Rewrite

**Try Flutter integration first (Phase A).** This preserves the existing working app and adds the probe as a new feature via platform channels.

**Only pivot to full Swift rewrite (Phase B) if ANY of these are true:**

1. The Butterfly SDK has an unresolvable linking conflict with the existing `use_frameworks! :linkage => :static` requirement (MediaPipe) AND you cannot isolate them via SPM + CocoaPods split
2. The SDK requires rendering to a native view hierarchy that cannot be bridged via Flutter's `Texture` widget or `PlatformView`
3. Live frame streaming over EventChannel has >200ms latency making real-time preview unusable

**Document your findings at each decision point before proceeding.** If you hit a blocker, write a brief analysis explaining the conflict, what you tried, and why the Flutter path won't work — then proceed to Phase B.

---

## Phase A: Flutter Integration (TRY THIS FIRST)

### A1: SDK Discovery & Dependency Setup

1. Clone/inspect the Butterfly ImagingSDK-iOS repo. Read **ALL** documentation — README, integration guides, sample code, API reference.
2. Determine:
   - Distribution method (CocoaPods, SPM, manual XCFramework?)
   - Framework type (static or dynamic?)
   - Minimum iOS version (must be ≤ 16.0 to match our target)
   - Authentication setup (how/where are access key + customer key configured at runtime?)
   - How the SDK delivers ultrasound frames (delegate callbacks, Combine, async stream?)
   - Frame format (`CVPixelBuffer`, `CGImage`, JPEG data, raw bytes?)
   - Required entitlements, background modes, `Info.plist` keys
   - Bluetooth vs USB-C connection model
3. Add the SDK to the iOS project:
   - **First try:** CocoaPods alongside existing deps. Check if `use_frameworks! :linkage => :static` works with the SDK.
   - **If conflict:** try adding the Butterfly SDK via SPM while keeping CocoaPods for MediaPipe/ONNX. This is a valid hybrid approach.
   - **If neither works:** try manually vendoring the XCFramework into `ios/Frameworks/` and linking it in Xcode build settings.
   - **If NOTHING works:** document the conflict and go to Phase B.

### A2: Native Plugin (Swift)

Create `ios/Runner/ButterflyProbePlugin.swift` (and register in AppDelegate).

#### MethodChannel (`com.mwana_ai/butterfly_probe`)

| Method | Description |
|---|---|
| `initialize(accessKey, customerKey)` | Init SDK session |
| `startScanning` | Begin BLE probe discovery |
| `getDiscoveredProbes` | Return list of probe IDs/names |
| `connectToProbe(probeId)` | Connect to specific probe |
| `startImaging(preset)` | Begin ultrasound stream (preset = e.g., "MSK" or "breast" if SDK supports presets) |
| `captureFrame` | Grab current frame, convert to JPEG bytes, return via method channel result |
| `freezeFrame` / `unfreezeFrame` | If SDK supports freeze |
| `adjustDepth(cm)` | If SDK supports depth control |
| `adjustGain(value)` | If SDK supports gain control |
| `stopImaging` | Stop stream |
| `disconnect` | Disconnect from probe |
| `getProbeInfo` | Return battery level, serial, firmware version |

#### EventChannel (`com.mwana_ai/butterfly_probe_events`)

Stream of JSON-encoded events:

- `{type: "state", state: "scanning|connecting|connected|imaging|disconnected|error"}`
- `{type: "frame", data: "<base64 jpeg>"}` for live preview
  - **IMPORTANT:** downsample preview frames to ~320px wide to avoid memory pressure over the channel. Full-res only on `captureFrame`.
- `{type: "error", message: "...", code: "..."}`

#### If preview streaming over EventChannel is too slow (>200ms per frame)

Try these alternatives **in order:**

1. **Flutter Texture widget** — register a `FlutterTextureRegistry`, render frames to a `CVPixelBuffer`, return the texture ID to Dart. This avoids serialization overhead entirely.
2. **PlatformView** — embed the SDK's native preview `UIView` directly into the Flutter widget tree via `UiKitView`.
3. **If none of these deliver acceptable performance:** go to Phase B.

### A3: Dart Service Layer

**`lib/services/butterfly_probe_service.dart`:**

- Wraps MethodChannel + EventChannel
- Exposes typed async API matching the native methods
- `Stream<ProbeState>` for connection state
- `Stream<Uint8List>` for preview frames (separate from state)
- Proper error handling: timeout on connect (30s), retry logic for BLE discovery, graceful handling of probe disconnect mid-imaging

**`lib/models/probe_state.dart`:**

```dart
enum ProbeConnectionState {
  disconnected, scanning, connecting, connected, imaging, error
}

class ProbeInfo {
  final String id;
  final String name;
  final int? batteryLevel;
  final String? serialNumber;
}
```

### A4: UI Screens

**`lib/screens/probe_scan_screen.dart`:**

- "Scanning for probes..." with activity indicator
- List of discovered probes with connect button
- Connection status and probe info (battery %) once connected
- "Start Imaging" button when connected
- Handle: no probes found, probe out of range, BLE off

**`lib/screens/probe_imaging_screen.dart`:**

- Live ultrasound preview (`StreamBuilder` + `Image.memory`, or `Texture` widget if using that path)
- Depth/gain controls if SDK supports them
- Freeze/unfreeze toggle
- **"Capture" button** → captures full-res frame → navigates to existing analysis pipeline
- "Stop" button → stops imaging, returns to probe screen
- Visual indicator that probe is actively imaging
- Handle: probe disconnects during imaging (show error, offer to reconnect)

**Image source picker update:** Add "Butterfly iQ Probe" option alongside Camera, Gallery, Files. Only show when running on physical iOS device (not simulator).

### A5: Pipeline Integration

- `captureFrame()` returns `Uint8List` (JPEG bytes)
- Feed into existing flow at the same entry point as camera/gallery
- **Validation bypass consideration:** The existing saturation + dark-pixel validation was tuned for stored ultrasound images. Probe output may have different characteristics (different dynamic range, different encoding). Test with actual probe output. If validation rejects valid probe frames, add a `source: ImageSource.butterflyProbe` flag that adjusts thresholds or skips validation (the image IS from an ultrasound device — the validation exists to reject non-ultrasound photos).
- Tag the image source as "Butterfly iQ" in the report metadata

### A6: Testing

**Automated tests:**

- Unit tests: `ButterflyProbeService` with mock `MethodChannel`
- Widget tests: probe scan screen, imaging screen

**Manual integration test checklist (requires physical probe):**

- [ ] SDK initializes with credentials
- [ ] Probe discovered via BLE scan
- [ ] Connect/disconnect cycle
- [ ] Live preview renders without lag
- [ ] Frame capture produces valid image data
- [ ] Captured frame passes through ONNX inference correctly
- [ ] Report correctly identifies source as Butterfly iQ
- [ ] Probe disconnect mid-imaging handled gracefully
- [ ] Low battery warning (if SDK provides this)

---

## Phase B: Native Swift Rewrite (ONLY IF PHASE A FAILS)

> **Before starting this phase**, document exactly why Flutter integration failed.

### Architecture

**Pattern:** MVVM + Coordinator, UIKit (not SwiftUI — better control over complex image rendering and camera-style interfaces)

### Must replicate ALL existing functionality

1. Model setup screen (Gemma 4 `.litertlm` file install)
2. Image source picker (camera, gallery, files, AND Butterfly probe)
3. Ultrasound image validation (port saturation + dark-pixel checks)
4. ONNX inference — use `onnxruntime-objc`/swift pod directly:
   - **SAME** model: `model_simplified.onnx`
   - **SAME** preprocessing: ImageNet normalization
   - **SAME** TTA: original + horizontal flip averaged
   - **SAME** thresholds: malignant override at P ≥ 0.35
   - **SAME** class order: `[0=benign, 1=malignant, 2=normal]`
   - **SAME** segmentation: 256×256 mask
   - **DO NOT CHANGE ANY OF THESE VALUES.**
5. Segmentation overlay (red alpha-blended mask on original)
6. BI-RADS probability → category mapping (port exactly)
7. Gemma 4 report generation — use MediaPipe LiteRT iOS SDK directly (not the Flutter wrapper)
8. Deterministic template fallback if Gemma model not loaded
9. PDF export via `UIActivityViewController`
10. Butterfly probe integration (direct SDK usage — no bridging needed, this is the advantage of native)

### Project Structure

```
MwanaAI/
├── App/
│   ├── AppDelegate.swift
│   ├── SceneDelegate.swift
│   └── Coordinator/
├── Models/
│   ├── AnalysisResult.swift
│   ├── BiRadsCategory.swift
│   ├── ProbeState.swift
│   └── ...
├── Services/
│   ├── ONNXInferenceService.swift    ← port EXACTLY from Dart
│   ├── GemmaReportService.swift
│   ├── ImageValidationService.swift
│   ├── ButterflyProbeService.swift
│   └── PDFExportService.swift
├── ViewModels/
├── Views/
│   ├── ModelSetup/
│   ├── ImageSource/
│   ├── ProbeImaging/
│   ├── Analysis/
│   └── Report/
├── Resources/
│   ├── model_simplified.onnx
│   └── ...
└── Tests/
```

### Critical Porting Rules

- Before writing ANY inference code, read the existing Dart implementation **line by line**. Port the math exactly. Off-by-one errors in normalization or threshold comparisons will silently produce wrong diagnoses.
- Write comparison tests: given the same input image, the Swift implementation must produce the same class probabilities (within floating point tolerance) as the Dart implementation.
- The BI-RADS mapping logic must be ported as a lookup, not reimplemented from memory.

### Dependencies (Swift native)

- `onnxruntime-ios` (CocoaPods or SPM)
- MediaPipe Tasks LiteRT (for Gemma 4)
- ButterflyNetwork ImagingSDK
- No third-party UI libraries — keep it lean

### Testing for Swift Rewrite

- Port ALL 48 existing tests (45 unit + 3 widget → XCTest)
- Add inference comparison tests (same input → same output)
- Add Butterfly probe integration tests
- Add UI tests for critical flows

---

## Non-Negotiable Rules (BOTH Phases)

1. **SDK credentials go in a gitignored config file.** NEVER in source.
2. **No patient data or ultrasound frames leave the device. Ever.**
3. **All ONNX inference constants preserved exactly.**
4. **App remains explicitly "not a medical device"** — keep all disclaimers and "requires radiologist review" language.
5. **Error handling must be robust** — this is a medical context. Silent failures or crashes during imaging are unacceptable. Every error state must have a user-facing message and a recovery path.
6. **Minimum iOS 16.0 maintained.**
