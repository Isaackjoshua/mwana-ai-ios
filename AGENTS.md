# AGENTS.md — Mwana-AI iOS: Agentic Reference

This file is written for future AI agents and LLMs working in this repository.
It covers the full picture: what the app does, how every piece fits together,
known constraints, and decisions that are not obvious from reading the code alone.

---

## 1. What This App Does

**Mwana-AI** is a Flutter iOS app for AI-assisted breast cancer screening from
ultrasound images. It is entirely offline after initial model installation —
no patient data leaves the device at any point.

**End-to-end user flow:**

```
Load Gemma 4 model (once)
        │
        ▼
Pick ultrasound image (camera / gallery / Files app)
        │
        ▼
Validate it looks like a greyscale ultrasound
        │
        ▼
On-device ONNX inference (ResNet50 U-Net)
   ├── 3-class classification  → Benign / Malignant / Normal
   └── pixel segmentation mask → lesion boundary
        │
        ▼
Render segmentation overlay on original image
        │
        ▼
Assign ACR BI-RADS category (1 / 2 / 3 / 4A / 4B / 4C-5)
        │
        ▼
Generate structured clinical report (on-device Gemma 4, or template fallback)
        │
        ▼
Export PDF via iOS share sheet (AirDrop, Files, Mail, etc.)
```

---

## 2. Repository Layout

```
mwana_ai_ios/
├── AGENTS.md                        ← this file
├── pubspec.yaml                     ← dependencies + flutter_launcher_icons config
├── analysis_options.yaml            ← excludes packages/** from analyzer
├── ios/
│   ├── Podfile                      ← iOS 16.0, use_frameworks! :static
│   └── Runner/
│       ├── Info.plist               ← camera/photo permissions, display name
│       └── Assets.xcassets/AppIcon.appiconset/
├── assets/
│   ├── models/                      ← GITIGNORED — place files here manually
│   │   ├── model_simplified.onnx    ← 190 MB ResNet50 U-Net (FP32)
│   │   └── *.litertlm               ← Gemma 4 model (installed via app UI)
│   └── icons/
│       └── app_icon.png             ← source icon (1024×1024, no alpha)
├── lib/
│   ├── main.dart                    ← FlutterGemma.initialize() then runApp
│   ├── app.dart                     ← MaterialApp, onGenerateRoute, all named routes
│   ├── models/                      ← pure Dart data classes, no Flutter imports
│   ├── services/                    ← one class per file, all async
│   ├── screens/                     ← one file per screen
│   └── widgets/                     ← reusable UI only, no service calls
├── packages/                        ← vendored upstream packages (DO NOT EDIT)
│   ├── flutter_gemma/               ← local Gemma 4 LLM (LiteRT/MediaPipe)
│   ├── flutter_onnxruntime/         ← on-device ONNX inference
│   ├── local_hnsw/                  ← approximate nearest-neighbour (unused by app)
│   └── dart_sentencepiece_tokenizer/
└── test/
    ├── unit/                        ← 45 unit tests
    └── widget/                      ← 3 widget tests
```

---

## 3. Named Routes

All navigation uses named routes defined in `lib/app.dart:26`.
**Never use `popUntil` with `ModalRoute.withName`** — `onGenerateRoute` does
not pass `settings` into `MaterialPageRoute`, so route names are null at
runtime. Use `Navigator.pushNamedAndRemoveUntil` instead.

| Route | Screen | Arguments |
|---|---|---|
| `/splash` | `SplashScreen` | none |
| `/model-setup` | `ModelSetupScreen` | none |
| `/input` | `InputSelectionScreen` | none |
| `/confirm` | `ImageConfirmScreen` | `String imagePath` |
| `/analysis` | `AnalysisScreen` | `String imagePath` |
| `/report` | `ReportScreen` | `Map {inferenceResult, overlayBytes?}` |
| `/export` | `ExportScreen` | `Map {inferenceResult, reportResult, overlayBytes?}` |

---

## 4. Inference Pipeline (Critical Constants)

**Do not change any value below without re-running `validate_mobile.py`
on the full BUSI test set.**

### 4.1 Image Preprocessing — `lib/services/image_preprocessor.dart`

| Step | Detail |
|---|---|
| Input | Any JPEG/PNG accepted by `package:image` |
| Resize | 256×256 bilinear interpolation |
| Layout | CHW (channel-first): R-plane, G-plane, B-plane |
| Normalise | `(pixel/255 − mean) / std` per channel |
| Mean | `[0.485, 0.456, 0.406]` (ImageNet RGB) |
| Std | `[0.229, 0.224, 0.225]` (ImageNet RGB) |
| Output | `Float32List` of length 196 608 (3×256×256) |

### 4.2 Test-Time Augmentation (TTA)

Two passes are run per image: original and horizontal flip.
Softmax probabilities are averaged element-wise. The flipped segmentation
mask is un-flipped by mirroring the x-axis before averaging.
This happens in `OnnxInferenceService.runInference` and
`OnnxInferenceService._averageSegMasks`.

### 4.3 ONNX Model

| Property | Value |
|---|---|
| File | `assets/models/model_simplified.onnx` |
| Size | ~199 MB FP32 |
| Input node | `"image"` — shape `[1, 3, 256, 256]` |
| Classification output | `"cls_logits"` — shape `[1, 3]` (raw logits) |
| Segmentation output | `"seg_logits"` — shape `[1, 1, 256, 256]` (raw logits) |
| Class order | `0=benign, 1=malignant, 2=normal` |

The model file is **gitignored**. Copy it from:
`BUSI.project/BUSI/model_export/model_simplified.onnx`
into `assets/models/` before building.

### 4.4 Postprocessing

```
cls_logits  → softmax (numerically stable) → avg with flipped pass
           → malignant override: if probs[1] >= 0.35 → class 1
           → else argmax

seg_logits  → avg raw logits with un-flipped pass → sigmoid per pixel
           → binary mask: pixel = 1.0 if sigmoid >= 0.275 else 0.0
```

| Constant | Value | Location |
|---|---|---|
| `malignantThreshold` | `0.35` | `OnnxInferenceService` |
| `segThreshold` | `0.275` | `OnnxInferenceService` |

### 4.5 BI-RADS Assignment — `lib/services/birads_service.dart`

| Condition | Category |
|---|---|
| Normal (index 2) | BI-RADS 1 |
| Benign (index 0), prob ≥ 0.80 | BI-RADS 2 |
| Benign (index 0), prob < 0.80 | BI-RADS 3 |
| Malignant, prob ≥ 0.85 | BI-RADS 4C–5 |
| Malignant, 0.70 ≤ prob < 0.85 | BI-RADS 4B |
| Malignant, prob < 0.70 | BI-RADS 4A |

---

## 5. Gemma 4 Integration

### Model lifecycle
- `FlutterGemma.initialize()` is called once in `main.dart` before `runApp`.
- The model file (`.litertlm`) is not bundled in the app — the user installs it
  on first launch via `ModelSetupScreen` (from device storage or URL).
- `ModelManagerService` wraps `FlutterGemma.listInstalledModels()` and
  `FlutterGemma.installModel()`. Its constructor accepts override callbacks
  for unit testing without a native platform channel.

### Report generation — `lib/services/local_gemma_report_service.dart`
- Calls `FlutterGemma.getActiveModel(maxTokens: 2048)`, creates a chat
  session, sends the structured findings prompt, parses section headers.
- Falls back to `_templateReport()` on any error (model unavailable, timeout,
  parse failure).

### Template fallback (offline / model not loaded)
The `_templateReport()` method generates **class-specific** clinical prose —
not generic text with swapped numbers. Three distinct branches:

| Class | Key findings prose |
|---|---|
| Malignant | Irregular shape, non-parallel, non-circumscribed/spiculated margins, hypoechoic, posterior shadowing, possible architectural distortion |
| Benign | Oval/round, parallel, circumscribed/microlobulated, hypoechoic-to-isoechoic, echogenic pseudocapsule, no shadowing |
| Normal | No discrete mass, normal fibroglandular parenchyma, no overlay generated, negative AI result caveat |

---

## 6. Segmentation Overlay Rendering — `lib/services/overlay_renderer.dart`

1. Binary mask (256×256 Float32List) → grayscale `img.Image`
2. Upsample to original image dimensions (nearest-neighbour)
3. Alpha-blend mask-positive pixels with a colour (default red, opacity 0.5)
4. Compute bounding box of mask-positive region → draw 2px rect
5. Encode to PNG → `Uint8List` passed through to PDF and report screens

---

## 7. Ultrasound Validation — `lib/services/ultrasound_validator.dart`

Runs on a 128×128 thumbnail before inference. Rejects the image if:
- Average HSV saturation > 0.25 (not greyscale — likely a colour photo)
- Dark pixel ratio < 0.08 (not enough dark background — not a scanner frame)

These thresholds are deliberately relaxed to allow colour-Doppler overlays
and tightly-cropped scans. Do not tighten without re-testing on real BUSI images.

---

## 8. PDF Export — `lib/services/pdf_export_service.dart`

- Built with `package:pdf` and `package:printing`.
- **iOS-specific**: uses `Share.shareXFiles` (share_plus) — not `open_filex`
  (Android-only). File is written to `getTemporaryDirectory()` and deleted
  after the share sheet is dismissed.
- Footer on every page: AI disclaimer in red bold.
- iPad popover: `ExportScreen` captures the share button's `Rect` via
  `GlobalKey` and passes it as `sharePositionOrigin` to prevent a crash.

---

## 9. iOS Platform Notes

### Deployment target
**iOS 16.0** (not 15). `flutter_gemma` podspec hard-requires 16.0.
This is set in `ios/Podfile` and `ios/Runner.xcodeproj/project.pbxproj`.

### CocoaPods
MediaPipe ships as static XCFrameworks. The Podfile must use:
```ruby
use_frameworks! :linkage => :static
```
Do **not** add `use_modular_headers!` — it conflicts with static linkage.

### flutter_gemma build hook
`packages/flutter_gemma/hook/build.dart` has a compatibility shim for the
Flutter 3.24 → 3.44 native assets config format change (`out_dir` → `out_file`).
If this breaks on a future Flutter version, check the `BuildConfig` API for new
output keys.

### Permissions (Info.plist)
- `NSCameraUsageDescription` — image capture
- `NSPhotoLibraryUsageDescription` — gallery read
- `NSPhotoLibraryAddUsageDescription` — save to Photos (PDF export fallback)

### Build for device
```bash
flutter build ios --release --device-id <UDID>
```
Debug builds cannot launch from the home screen on iOS 14+ — always use
release mode for physical device testing outside of `flutter run`.

---

## 10. Key Dependencies

| Package | Purpose | Notes |
|---|---|---|
| `flutter_onnxruntime` | ONNX inference | Vendored in `packages/` |
| `flutter_gemma` | On-device Gemma 4 LLM | Vendored in `packages/`; requires iOS 16.0 |
| `image` | Image decode/resize/encode | Used in preprocessor and overlay renderer |
| `pdf` + `printing` | PDF generation | Helvetica fallback used; em-dash (U+2014) may not render — known cosmetic issue |
| `share_plus` | iOS share sheet | Replaces Android's `open_filex` |
| `path_provider` | Temp directory for PDF file | |
| `permission_handler` | Camera/gallery runtime permissions | |
| `file_picker` | Files app access | |
| `flutter_spinkit` | Loading spinners | |
| `flutter_launcher_icons` | Generates all iOS icon sizes | Run with `flutter pub run flutter_launcher_icons` after changing `assets/icons/app_icon.png` |

---

## 11. Testing

```bash
flutter analyze      # must be 0 issues
flutter test         # 48 tests (45 unit + 3 widget)
```

- Unit tests: `test/unit/` — test service logic with injected fakes, no platform channel
- Widget tests: `test/widget/` — test screen rendering with `pumpWidget`
- The `packages/**` directory is excluded from the analyzer in `analysis_options.yaml`
- `packages/flutter_gemma/example/config.json` is gitignored (contained a real HuggingFace token that was scrubbed from history on 2026-06-18)

---

## 12. Git / GitHub

- Repo: https://github.com/Isaackjoshua/mwana-ai-ios
- Branch: `main`
- Large files excluded via `.gitignore`: `assets/models/*.onnx`, `*.litertlm`, `*.task`
- CocoaPods excluded: `ios/Pods/`, `ios/.symlinks/`
- Xcode SPM excluded: `ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/`

To clone and build:
```bash
git clone https://github.com/Isaackjoshua/mwana-ai-ios.git
cd mwana-ai-ios
cp /path/to/model_simplified.onnx assets/models/
flutter pub get
cd ios && pod install && cd ..
flutter build ios --release
```

---

## 13. What NOT to Change Without Expert Review

| Item | Risk |
|---|---|
| ImageNet mean/std in `image_preprocessor.dart` | Model accuracy collapses |
| `malignantThreshold` (0.35) | Sensitivity/specificity shift — re-run `validate_mobile.py` |
| `segThreshold` (0.275) | Segmentation mask coverage shifts |
| ONNX input/output node names | Runtime crash |
| Class index order `[0=benign,1=malignant,2=normal]` | All labels wrong |
| `use_frameworks! :linkage => :static` in Podfile | MediaPipe XCFrameworks fail to link |
| iOS deployment target below 16.0 | `flutter_gemma` pod install fails |
