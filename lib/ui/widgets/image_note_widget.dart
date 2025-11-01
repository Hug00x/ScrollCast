import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/annotations.dart';

/// Image note with corner-drag resize (uniform scale) and rotation handle.
///
/// Interaction model:
/// - Tap to select/deselect.
/// - Drag the image to move it.
/// - When selected, four corner handles appear: drag any to uniformly scale the image
///   relative to its center (similar to Word's corner handles).
/// - A rotation handle appears above the top-center; drag it to rotate freely.
class ImageNoteWidget extends StatefulWidget {
  const ImageNoteWidget({
    super.key,
    required this.note,
    required this.canvasSize,
    required this.onChanged,
    this.onDelete,
  });

  final ImageNote note;
  final Size canvasSize;
  final ValueChanged<ImageNote> onChanged;
  final VoidCallback? onDelete;

  @override
  State<ImageNoteWidget> createState() => _ImageNoteWidgetState();
}

class _ImageNoteWidgetState extends State<ImageNoteWidget> {
  late Offset _pos; // center
  late double _w;
  late double _h;
  double _rotation = 0.0;
  bool _selected = false;

  // used during gestures
  late double _startW;
  late double _startH;
  late double _startRotation;
  late double _handleStartDist; // for corner-drag scaling
  late Offset _centerGlobal;

  static const double _minSize = 24.0;
  // touch target size for handles (larger hitbox)
  static const double _handleTouchSize = 36.0;
  // visible handle size (smaller circle inside the touch area)
  static const double _handleVisualSize = 16.0;
  static const double _rotateHandleDistance = 30.0;

  @override
  void initState() {
    super.initState();
    _pos = widget.note.position;
    _w = widget.note.width;
    _h = widget.note.height;
    _rotation = widget.note.rotation;
  }

  @override
  void didUpdateWidget(covariant ImageNoteWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.note.position != widget.note.position) _pos = widget.note.position;
    if (oldWidget.note.width != widget.note.width) _w = widget.note.width;
    if (oldWidget.note.height != widget.note.height) _h = widget.note.height;
    if (oldWidget.note.rotation != widget.note.rotation) _rotation = widget.note.rotation;
  }

  // no-op start for drag (we only track deltas in update)

  void _onDragUpdate(DragUpdateDetails details) {
    final nx = (_pos.dx + details.delta.dx).clamp(0, widget.canvasSize.width);
    final ny = (_pos.dy + details.delta.dy).clamp(0, widget.canvasSize.height);
    setState(() => _pos = Offset(nx.toDouble(), ny.toDouble()));
  }

  void _onDragEnd(DragEndDetails details) {
    widget.onChanged(widget.note.copyWith(position: _pos, width: _w, height: _h, rotation: _rotation));
  }

  // corner handle: uniform scale based on distance from center
  void _onHandleStart(DragStartDetails details) {
    final rb = context.findRenderObject() as RenderBox?;
    if (rb == null) return;
    _startW = _w;
    _startH = _h;
    _startRotation = _rotation;
  // account for the vertical offset we added for the rotate handle
  _centerGlobal = rb.localToGlobal(Offset(_w / 2, _rotateHandleDistance / 2 + _h / 2));
    _handleStartDist = (details.globalPosition - _centerGlobal).distance;
  }

  void _onHandleUpdate(DragUpdateDetails details) {
    final rb = context.findRenderObject() as RenderBox?;
    if (rb == null || _handleStartDist == 0) return;
    final newDist = (details.globalPosition - _centerGlobal).distance;
    final scale = (newDist / _handleStartDist).isFinite ? newDist / _handleStartDist : 1.0;
    final maxSide = math.max(widget.canvasSize.width, widget.canvasSize.height);
    final nw = (_startW * scale).clamp(_minSize, maxSide);
    final nh = (_startH * scale).clamp(_minSize, maxSide);
    setState(() {
      _w = nw;
      _h = nh;
    });
  }

  void _onHandleEnd(DragEndDetails details) {
    widget.onChanged(widget.note.copyWith(width: _w, height: _h, rotation: _rotation));
  }

  // rotation handle
  late double _startAngle;

  void _onRotateStart(DragStartDetails details) {
    final rb = context.findRenderObject() as RenderBox?;
    if (rb == null) return;
  // account for the vertical offset we added for the rotate handle
  _centerGlobal = rb.localToGlobal(Offset(_w / 2, _rotateHandleDistance / 2 + _h / 2));
    _startAngle = math.atan2(details.globalPosition.dy - _centerGlobal.dy, details.globalPosition.dx - _centerGlobal.dx);
    _startRotation = _rotation;
  }

  void _onRotateUpdate(DragUpdateDetails details) {
    final angle = math.atan2(details.globalPosition.dy - _centerGlobal.dy, details.globalPosition.dx - _centerGlobal.dx);
    final delta = angle - _startAngle;
    setState(() {
      _rotation = _startRotation + delta;
    });
  }

  void _onRotateEnd(DragEndDetails details) {
    widget.onChanged(widget.note.copyWith(rotation: _rotation));
  }

  Widget _buildHandle(Alignment alignment) {
    return Align(
      alignment: alignment,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: _onHandleStart,
        onPanUpdate: _onHandleUpdate,
        onPanEnd: _onHandleEnd,
        child: SizedBox(
          width: _handleTouchSize,
          height: _handleTouchSize,
          // center a smaller visible circle inside a larger hit area
          child: Center(
            child: Container(
              width: _handleVisualSize,
              height: _handleVisualSize,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border.all(color: Theme.of(context).colorScheme.primary, width: 1.2),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pin = 8.0;
    final maxLeft = math.max(0.0, widget.canvasSize.width - _w - pin);
    final maxTop = math.max(0.0, widget.canvasSize.height - _h - pin);

    // delete button sizing: visual size scales with the smaller image side;
    // touch area is a bit larger than the visual circle for better accessibility.
    final double _minDelete = 24.0;
    final double _maxDelete = 64.0;
    final double _deleteVisual = (math.min(_w, _h) * 0.18).clamp(_minDelete, _maxDelete);
    final double _deleteTouch = _deleteVisual + 8.0; // extra hit area

    return Positioned(
      left: (_pos.dx - _w / 2).clamp(0, maxLeft),
      top: (_pos.dy - _h / 2).clamp(0, maxTop),
      width: _w,
      height: _h + _rotateHandleDistance, // leave space for rotate handle
      child: GestureDetector(
        onTap: () => setState(() => _selected = !_selected),
  onPanStart: (_) {},
        onPanUpdate: _onDragUpdate,
        onPanEnd: _onDragEnd,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // rotated image centered in top-left of this box
            Positioned(
              left: 0,
              top: _rotateHandleDistance / 2,
              width: _w,
              height: _h,
              child: Transform.rotate(
                angle: _rotation,
                alignment: Alignment.center,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(widget.note.filePath),
                    width: _w,
                    height: _h,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.grey.shade200,
                      child: const Center(child: Icon(Icons.broken_image)),
                    ),
                  ),
                ),
              ),
            ),

            // selection border is drawn inside the rotated stack below so it follows the image rotation

            // corner handles (inside rotated space visually) - use Align inside positioned image
            if (_selected)
              Positioned(
                left: 0,
                top: _rotateHandleDistance / 2,
                width: _w,
                height: _h,
                child: Transform.rotate(
                  angle: _rotation,
                  alignment: Alignment.center,
                  child: Stack(
                    children: [
                      // border that rotates with the image
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2),
                            ),
                          ),
                        ),
                      ),
                      // delete button placed inside rotated area so it follows rotation
                      if (widget.onDelete != null)
                        Positioned(
                          right: 6,
                          top: 6,
                          child: SizedBox(
                            width: _deleteTouch,
                            height: _deleteTouch,
                            child: Center(
                              child: Material(
                                color: Colors.redAccent,
                                shape: const CircleBorder(),
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: widget.onDelete,
                                  child: SizedBox(
                                    width: _deleteVisual,
                                    height: _deleteVisual,
                                    child: Center(
                                      child: Icon(
                                        Icons.close,
                                        size: (_deleteVisual * 0.5).clamp(12.0, 28.0),
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      // top-left
                      Positioned(
                        left: -_handleTouchSize / 2,
                        top: -_handleTouchSize / 2,
                        child: _buildHandle(Alignment.topLeft),
                      ),
                      // top-right
                      Positioned(
                        right: -_handleTouchSize / 2,
                        top: -_handleTouchSize / 2,
                        child: _buildHandle(Alignment.topRight),
                      ),
                      // bottom-right
                      Positioned(
                        right: -_handleTouchSize / 2,
                        bottom: -_handleTouchSize / 2,
                        child: _buildHandle(Alignment.bottomRight),
                      ),
                      // bottom-left
                      Positioned(
                        left: -_handleTouchSize / 2,
                        bottom: -_handleTouchSize / 2,
                        child: _buildHandle(Alignment.bottomLeft),
                      ),
                    ],
                  ),
                ),
              ),

            // rotate handle (above top-center)
            if (_selected)
              Positioned(
                left: (_w / 2) - (_handleTouchSize / 2),
                top: 0,
                child: GestureDetector(
                  onPanStart: _onRotateStart,
                  onPanUpdate: _onRotateUpdate,
                  onPanEnd: _onRotateEnd,
                  child: SizedBox(
                    width: _handleTouchSize,
                    height: _handleTouchSize,
                    child: Center(
                      child: Container(
                        width: _handleVisualSize,
                        height: _handleVisualSize,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          shape: BoxShape.circle,
                          border: Border.all(color: Theme.of(context).colorScheme.primary, width: 1.2),
                        ),
                        child: const Icon(Icons.rotate_right, size: 12),
                      ),
                    ),
                  ),
                ),
              ),

            // (old non-rotating delete FAB removed — delete is now inside the rotated area)
          ],
        ),
      ),
    );
  }
}
