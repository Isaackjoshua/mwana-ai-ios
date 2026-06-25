import 'dart:typed_data';
import 'package:flutter/material.dart';

enum _ViewMode { original, boundingBox, heatmap }

/// Full-screen pinch-to-zoom viewer with a toggle bar for switching between
/// the original image, the bounding-box segmentation overlay, and the
/// Grad-CAM-style heatmap.
///
/// Pass null for any view that is not available — the toggle button for
/// that view is hidden automatically.
class ImageViewerScreen extends StatefulWidget {
  /// Raw original image bytes (JPEG/PNG from the device).
  final Uint8List? originalBytes;

  /// Segmentation overlay with coloured mask and bounding box.
  final Uint8List? boundingBoxBytes;

  /// Jet-colourmap heatmap (U-Net probability map rendered with HeatmapRenderer).
  final Uint8List? heatmapBytes;

  final String title;

  const ImageViewerScreen({
    super.key,
    this.originalBytes,
    this.boundingBoxBytes,
    this.heatmapBytes,
    required this.title,
  });

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  late _ViewMode _mode;

  @override
  void initState() {
    super.initState();
    // Default: bounding box > heatmap > original
    if (widget.boundingBoxBytes != null) {
      _mode = _ViewMode.boundingBox;
    } else if (widget.heatmapBytes != null) {
      _mode = _ViewMode.heatmap;
    } else {
      _mode = _ViewMode.original;
    }
  }

  Uint8List? get _currentBytes => switch (_mode) {
        _ViewMode.original => widget.originalBytes,
        _ViewMode.boundingBox => widget.boundingBoxBytes,
        _ViewMode.heatmap => widget.heatmapBytes,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title, style: const TextStyle(fontSize: 15)),
      ),
      body: Column(
        children: [
          Expanded(
            child: _currentBytes != null
                ? InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 8.0,
                    child: Center(
                      child: Image.memory(
                        _currentBytes!,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    ),
                  )
                : const Center(
                    child: Text('View not available',
                        style: TextStyle(color: Colors.white54)),
                  ),
          ),
          _buildToggleBar(context),
          Container(
            color: Colors.grey.shade900,
            padding: const EdgeInsets.only(bottom: 12, top: 4),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.pinch, size: 13, color: Colors.white38),
                SizedBox(width: 5),
                Text(
                  'Pinch to zoom  ·  Drag to pan',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleBar(BuildContext context) {
    final views = <({_ViewMode mode, IconData icon, String label})>[
      if (widget.originalBytes != null)
        (mode: _ViewMode.original, icon: Icons.image_outlined, label: 'Original'),
      if (widget.boundingBoxBytes != null)
        (mode: _ViewMode.boundingBox, icon: Icons.crop_square_rounded, label: 'Bounding Box'),
      if (widget.heatmapBytes != null)
        (mode: _ViewMode.heatmap, icon: Icons.whatshot_rounded, label: 'Heatmap'),
    ];

    if (views.length <= 1) return const SizedBox.shrink();

    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      color: Colors.grey.shade900,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          for (int i = 0; i < views.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: _ToggleButton(
                label: views[i].label,
                icon: views[i].icon,
                selected: _mode == views[i].mode,
                selectedColor: primary,
                onTap: () => setState(() => _mode = views[i].mode),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color selectedColor;
  final VoidCallback onTap;

  const _ToggleButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.selectedColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? selectedColor : Colors.grey.shade800,
          borderRadius: BorderRadius.circular(8),
          border: selected
              ? null
              : Border.all(color: Colors.grey.shade600, width: 0.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: Colors.white),
            const SizedBox(height: 3),
            Text(
              label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
