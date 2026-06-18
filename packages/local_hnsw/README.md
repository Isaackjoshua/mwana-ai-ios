# 🧠 local_hnsw

A lightweight, in-memory [HNSW (Hierarchical Navigable Small World)](https://arxiv.org/abs/1603.09320) vector index for Dart & Flutter. Supports fast approximate nearest neighbor (ANN) search with customizable distance metrics.

---

## ✨ Features

- In-memory approximate nearest neighbor search
- Supports **cosine** and **euclidean** similarity
- Generic and type-safe (`LocalHNSW<T>`)
- Add, search, delete, save, and load vectors
- No native dependencies — pure Dart!

---

## 🚀 Getting Started

### 1. Add dependency

```yaml
dependencies:
  local_hnsw: ^1.0.0
```

### 2. Import the package

```dart
import 'package:local_hnsw/local_hnsw.dart';
```

---

## ✅ Example

```dart
final index = LocalHNSW<String>(
  dim: 3,
  metric: LocalHnswMetric.cosine, // or .euclidean
);

index.add(LocalHnswItem(item: 'apple', vector: [0.1, 0.2, 0.3]));
index.add(LocalHnswItem(item: 'banana', vector: [0.2, 0.1, 0.4]));
index.add(LocalHnswItem(item: 'grape', vector: [0.9, 0.8, 0.7]));

final result = index.search([0.1, 0.2, 0.3], 2);

for (final r in result.items) {
  print('Found ${r.item} with distance ${r.distance}');
}
```

---

## 🔁 Save and Load

```dart
final saved = index.save(encodeItem: (v) => v);
final loaded = LocalHNSW<String>.load(
  json: saved,
  dim: 3,
  decodeItem: (s) => s,
);
```

---

## 📌 API Overview

### `LocalHNSW<T>` (Generic)

| Method | Description |
|-------|-------------|
| `add(item)` | Add a vector item |
| `search(query, k)` | Approximate nearest neighbor search |
| `delete(item)` | Remove an item |
| `save()` | Export to Map<String, dynamic> |
| `load()` | Load from a saved Map |

---

## 🧪 Running Tests

```bash
dart test
```

---

## 📄 License

MIT License
