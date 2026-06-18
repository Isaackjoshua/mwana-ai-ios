# Mwana-AI

AI-assisted breast cancer screening iOS app. Analyses breast ultrasound images entirely on-device — no patient data ever leaves the phone.

---

## What It Does

1. Load a Gemma 4 language model once (from device storage or a URL)
2. Pick a breast ultrasound image (camera, photo library, or Files app)
3. On-device ONNX inference classifies the image as **Benign / Malignant / Normal** and segments the lesion boundary
4. The segmentation mask is rendered as a colour overlay on the original image
5. An ACR BI-RADS category (1 / 2 / 3 / 4A / 4B / 4C–5) is assigned
6. On-device Gemma 4 generates a structured clinical report (falls back to a deterministic template if the model is not loaded)
7. Export the report as a PDF via the iOS share sheet

Everything runs offline after the initial model download.

---

## Requirements

| Requirement | Version |
|---|---|
| iOS | 16.0 or later |
| Flutter | 3.44.2 or later |
| CocoaPods | 1.16.0 or later |
| Xcode | 16.0 or later |
| ONNX model | `model_simplified.onnx` (~199 MB, not included in repo) |
| Gemma 4 model | `.litertlm` file installed via the app's model setup screen |

---

## Getting Started

### 1. Clone and install dependencies

```bash
git clone https://github.com/Isaackjoshua/mwana-ai-ios.git
cd mwana-ai-ios
flutter pub get
cd ios && pod install && cd ..
```

### 2. Add the ONNX model

The model file is excluded from git (190 MB). Copy it into the assets folder:

```bash
cp /path/to/model_simplified.onnx assets/models/
```

The source model lives at `BUSI.project/BUSI/model_export/model_simplified.onnx` in the companion training repository.

### 3. Build and run

```bash
# Run on a connected device
flutter run --release

# Build release IPA
flutter build ios --release
```

### 4. Load the Gemma 4 model

On first launch the app opens the **Model Setup** screen. Tap **From Device** and select your `.litertlm` Gemma 4 model file, or use **Download URL** to pull it from HuggingFace (requires a HuggingFace access token).

---

## Project Structure

```
lib/
├── main.dart                         ← app entry point
├── app.dart                          ← MaterialApp + named routes
├── models/                           ← pure Dart data classes
│   ├── classification_result.dart    ← predicted class, probabilities, BI-RADS
│   ├── segmentation_result.dart      ← binary mask, bounding box
│   ├── inference_result.dart         ← classification + segmentation combined
│   ├── report_result.dart            ← 6 clinical report sections
│   └── patient_context.dart          ← optional patient metadata
├── services/
│   ├── image_picker_service.dart     ← camera / gallery / Files access
│   ├── image_preprocessor.dart       ← resize → normalise → CHW tensor
│   ├── ultrasound_validator.dart     ← reject non-ultrasound images
│   ├── onnx_inference_service.dart   ← 2-way TTA inference pipeline
│   ├── birads_service.dart           ← probability → BI-RADS category
│   ├── overlay_renderer.dart         ← mask → annotated PNG
│   ├── local_gemma_report_service.dart ← Gemma 4 report + template fallback
│   ├── model_manager_service.dart    ← install / check Gemma 4 model
│   └── pdf_export_service.dart       ← build PDF, share via iOS sheet
└── screens/
    ├── splash_screen.dart
    ├── model_setup_screen.dart
    ├── input_selection_screen.dart
    ├── image_confirm_screen.dart
    ├── analysis_screen.dart
    ├── report_screen.dart
    └── export_screen.dart
```

---

## AI Model Details

### ONNX Classification + Segmentation Model

- **Architecture**: ResNet50 U-Net v10
- **Format**: ONNX FP32 (~199 MB)
- **Input**: `image` — `[1, 3, 256, 256]` CHW Float32, ImageNet-normalised
- **Outputs**:
  - `cls_logits` — `[1, 3]` raw logits → softmax → [benign, malignant, normal]
  - `seg_logits` — `[1, 1, 256, 256]` raw logits → sigmoid → binary mask
- **TTA**: two passes (original + horizontal flip), results averaged
- **Malignant override**: if P(malignant) ≥ 0.35 the class is set to malignant regardless of argmax

### Gemma 4 (on-device LLM)

- Runs via `flutter_gemma` (LiteRT/MediaPipe backend)
- Generates a structured BI-RADS report from numerical model findings
- Falls back to a deterministic, class-specific template if unavailable

---

## BI-RADS Assignment

| Prediction | Confidence | Category |
|---|---|---|
| Normal | — | BI-RADS 1 — Negative |
| Benign | ≥ 80% | BI-RADS 2 — Benign |
| Benign | < 80% | BI-RADS 3 — Probably Benign |
| Malignant | ≥ 85% | BI-RADS 4C–5 — High Suspicion |
| Malignant | 70–85% | BI-RADS 4B — Intermediate Suspicion |
| Malignant | < 70% | BI-RADS 4A — Low Suspicion |

---

## Running Tests

```bash
flutter analyze   # must return 0 issues
flutter test      # 48 tests (45 unit + 3 widget)
```

---

## Disclaimer

> **This app is not a medical device and does not provide clinical diagnoses.**
> All AI outputs require review by a qualified radiologist before any clinical decision is made.
> The app is intended for research and educational use only.

---

## Repository Notes

- Large model files (`*.onnx`, `*.litertlm`, `*.task`) are excluded from git — download or copy them separately
- Vendored packages are in `packages/` and excluded from `flutter analyze`
- See `AGENTS.md` for a detailed agentic reference covering architecture, inference constants, and iOS-specific constraints
