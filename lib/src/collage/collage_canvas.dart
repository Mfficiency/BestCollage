import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'collage_controller.dart';
import 'collage_models.dart';
import 'color_matrix.dart';

/// The collage itself: the layout tree drawn as photo cells separated by
/// draggable dividers, with date stamps on top. Everything visible here is
/// exactly what gets saved — editing chrome (selection outline, divider
/// handles, empty-slot placeholders) disappears while
/// [CollageController.exporting] is true.
class CollageCanvas extends StatelessWidget {
  final CollageController controller;

  /// Wraps the saved area; [CollageSaver.render] captures it.
  final GlobalKey boundaryKey;

  /// Tapped an empty slot (fewer photos than the layout has room for).
  final VoidCallback onAddPhoto;

  const CollageCanvas({
    super.key,
    required this.controller,
    required this.boundaryKey,
    required this.onAddPhoto,
  });

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Center(
      child: AspectRatio(
        aspectRatio: c.shape.ratio,
        child: RepaintBoundary(
          key: boundaryKey,
          child: LayoutBuilder(builder: (context, box) {
            final shortSide = box.biggest.shortestSide;
            return Container(
              color: c.borderColor,
              padding: EdgeInsets.all(c.border),
              child: _NodeView(
                node: c.layout,
                c: c,
                shortSide: shortSide,
                onAddPhoto: onAddPhoto,
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _NodeView extends StatelessWidget {
  final LayoutNode node;
  final CollageController c;
  final double shortSide;
  final VoidCallback onAddPhoto;

  const _NodeView({
    required this.node,
    required this.c,
    required this.shortSide,
    required this.onAddPhoto,
  });

  @override
  Widget build(BuildContext context) {
    final n = node;
    return switch (n) {
      LeafNode() => n.slot < c.photos.length
          ? PhotoCell(
              key: ValueKey(c.photos[n.slot]),
              c: c,
              index: n.slot,
              shortSide: shortSide)
          : _EmptySlot(exporting: c.exporting, onTap: onAddPhoto),
      SplitNode() => _SplitView(
          node: n, c: c, shortSide: shortSide, onAddPhoto: onAddPhoto),
    };
  }
}

/// Two children separated by a gap of [CollageController.border], with a
/// handle on the gap that drags the split ratio.
class _SplitView extends StatelessWidget {
  final SplitNode node;
  final CollageController c;
  final double shortSide;
  final VoidCallback onAddPhoto;

  const _SplitView({
    required this.node,
    required this.c,
    required this.shortSide,
    required this.onAddPhoto,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final horizontal = node.axis == Axis.horizontal;
      final total = horizontal ? box.maxWidth : box.maxHeight;
      final gap = c.border;
      final avail = math.max(0.0, total - gap);
      final firstLen = avail * node.ratio;
      final secondLen = avail - firstLen;
      const hit = 28.0; // touch target across the divider
      final center = firstLen + gap / 2;

      Widget child(LayoutNode n) => _NodeView(
          node: n, c: c, shortSide: shortSide, onAddPhoto: onAddPhoto);

      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            width: horizontal ? firstLen : box.maxWidth,
            height: horizontal ? box.maxHeight : firstLen,
            child: child(node.first),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            width: horizontal ? secondLen : box.maxWidth,
            height: horizontal ? box.maxHeight : secondLen,
            child: child(node.second),
          ),
          if (!c.exporting)
            Positioned(
              left: horizontal ? center - hit / 2 : 0,
              top: horizontal ? 0 : center - hit / 2,
              width: horizontal ? hit : box.maxWidth,
              height: horizontal ? box.maxHeight : hit,
              child: _DividerHandle(
                horizontal: horizontal,
                onDrag: (delta) {
                  if (avail <= 0) return;
                  node.ratio = (node.ratio + delta / avail)
                      .clamp(SplitNode.minRatio, SplitNode.maxRatio);
                  c.changed();
                },
              ),
            ),
        ],
      );
    });
  }
}

class _DividerHandle extends StatelessWidget {
  /// True for a split whose children sit side by side (a vertical line).
  final bool horizontal;
  final ValueChanged<double> onDrag;

  const _DividerHandle({required this.horizontal, required this.onDrag});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: horizontal
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.resizeRow,
      child: Tooltip(
        message: 'Drag to resize',
        waitDuration: const Duration(milliseconds: 800),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragUpdate:
              horizontal ? (d) => onDrag(d.delta.dx) : null,
          onVerticalDragUpdate: horizontal ? null : (d) => onDrag(d.delta.dy),
          child: Center(
            child: Container(
              key: const Key('divider-handle'),
              width: horizontal ? 8 : 44,
              height: horizontal ? 44 : 8,
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: scheme.primary, width: 1.5),
                boxShadow: const [
                  BoxShadow(blurRadius: 4, color: Color(0x55000000)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptySlot extends StatelessWidget {
  final bool exporting;
  final VoidCallback onTap;

  const _EmptySlot({required this.exporting, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (exporting) return const SizedBox.expand();
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_photo_alternate_outlined,
                  color: scheme.onSurfaceVariant),
              const SizedBox(height: 4),
              Text('Add photo',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

/// One photo, cropped to its cell. Pinch (or mouse wheel) zooms, drag pans,
/// double-tap resets, tap selects, long-press + drop on another photo swaps.
class PhotoCell extends StatefulWidget {
  final CollageController c;
  final int index;
  final double shortSide;

  const PhotoCell({
    super.key,
    required this.c,
    required this.index,
    required this.shortSide,
  });

  @override
  State<PhotoCell> createState() => _PhotoCellState();
}

class _PhotoCellState extends State<PhotoCell> {
  double _startZoom = 1;

  CollageController get c => widget.c;
  PhotoItem get p => c.photos[widget.index];

  /// Size of the photo drawn inside a [cell]: just covers it at zoom 1.
  Size _drawnSize(Size cell) {
    final o = p.orientedSize;
    if (o.isEmpty) return cell;
    final cover = math.max(cell.width / o.width, cell.height / o.height);
    return Size(o.width * cover * p.zoom, o.height * cover * p.zoom);
  }

  void _pan(Offset delta, Size cell) {
    final drawn = _drawnSize(cell);
    final spareX = drawn.width - cell.width;
    final spareY = drawn.height - cell.height;
    // Alignment -1 shows the left/top edge. Moving the finger right should
    // move the photo right, i.e. towards showing its left edge.
    if (spareX > 0.5) {
      p.alignX = (p.alignX - delta.dx * 2 / spareX).clamp(-1.0, 1.0);
    }
    if (spareY > 0.5) {
      p.alignY = (p.alignY - delta.dy * 2 / spareY).clamp(-1.0, 1.0);
    }
  }

  void _setZoom(double z) {
    p.zoom = z.clamp(1.0, PhotoItem.maxZoom);
  }

  @override
  Widget build(BuildContext context) {
    final selected = c.selected == widget.index && !c.exporting;
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(c.cornerRadius),
      child: LayoutBuilder(builder: (context, box) {
        final cell = box.biggest;
        final photo = _photo(cell);
        return DragTarget<int>(
          onWillAcceptWithDetails: (d) => d.data != widget.index,
          onAcceptWithDetails: (d) {
            HapticFeedback.selectionClick();
            c.swapPhotos(d.data, widget.index);
          },
          builder: (context, candidates, _) => Stack(
            fit: StackFit.expand,
            children: [
              Listener(
                // Select on touch-down so it feels instant (onTap waits for
                // the double-tap timeout).
                onPointerDown: (_) => c.select(widget.index),
                onPointerSignal: (e) {
                  if (e is PointerScrollEvent) {
                    _setZoom(p.zoom * (e.scrollDelta.dy < 0 ? 1.1 : 1 / 1.1));
                    c.select(widget.index);
                    c.changed();
                  }
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => c.select(widget.index),
                  onDoubleTap: () {
                    p.resetCrop();
                    c.changed();
                  },
                  onScaleStart: (_) {
                    _startZoom = p.zoom;
                    c.select(widget.index);
                  },
                  onScaleUpdate: (d) {
                    if (d.pointerCount > 1) _setZoom(_startZoom * d.scale);
                    _pan(d.focalPointDelta, cell);
                    c.changed();
                  },
                  child: LongPressDraggable<int>(
                    data: widget.index,
                    hapticFeedbackOnStart: true,
                    feedback: _DragFeedback(photo: p),
                    childWhenDragging: Opacity(opacity: 0.35, child: photo),
                    child: photo,
                  ),
                ),
              ),
              if (c.showDates && p.showDate && p.takenAt != null)
                _DateStamp(
                    c: c, photo: p, index: widget.index, shortSide: widget.shortSide),
              if (selected || candidates.isNotEmpty)
                IgnorePointer(
                  child: DecoratedBox(
                    key: selected ? const Key('selected-outline') : null,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(c.cornerRadius),
                      border: Border.all(
                        color: candidates.isNotEmpty
                            ? scheme.tertiary
                            : scheme.primary,
                        width: 3,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  Widget _photo(Size cell) {
    final drawn = _drawnSize(cell);
    final filter = ColorMatrix.filterFor(c.globalAdjustments, p.adjustments);
    Widget img = Image(
      image: p.image,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
    );
    if (filter != null) img = ColorFiltered(colorFilter: filter, child: img);
    return OverflowBox(
      minWidth: drawn.width,
      maxWidth: drawn.width,
      minHeight: drawn.height,
      maxHeight: drawn.height,
      alignment: Alignment(p.alignX, p.alignY),
      child: Transform.flip(
        flipX: p.flipped,
        child: RotatedBox(quarterTurns: p.quarterTurns, child: img),
      ),
    );
  }
}

class _DragFeedback extends StatelessWidget {
  final PhotoItem photo;
  const _DragFeedback({required this.photo});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 88,
        height: 88,
        child: RotatedBox(
          quarterTurns: photo.quarterTurns,
          child: Image(image: photo.image, fit: BoxFit.cover),
        ),
      ),
    );
  }
}

/// The dd.mm.yy stamp. Drag to move inside the photo, pinch to resize.
class _DateStamp extends StatefulWidget {
  final CollageController c;
  final PhotoItem photo;
  final int index;
  final double shortSide;

  const _DateStamp({
    required this.c,
    required this.photo,
    required this.index,
    required this.shortSide,
  });

  @override
  State<_DateStamp> createState() => _DateStampState();
}

class _DateStampState extends State<_DateStamp> {
  final GlobalKey _textKey = GlobalKey();
  double _startSize = DateStampPlacement.defaultSize;

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final p = widget.photo;
    final s = p.stamp;
    final fontSize = widget.shortSide * s.size;
    final color = c.dateColor;
    final editing = !c.exporting && c.selected == widget.index;

    return LayoutBuilder(builder: (context, box) {
      final cell = box.biggest;
      return Align(
        alignment: Alignment(s.x * 2 - 1, s.y * 2 - 1),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => c.select(widget.index),
          onScaleStart: (_) {
            _startSize = s.size;
            c.select(widget.index);
          },
          onScaleUpdate: (d) {
            if (d.pointerCount > 1) {
              s.size = (_startSize * d.scale).clamp(
                  DateStampPlacement.minSize, DateStampPlacement.maxSize);
            }
            final stamp = _textKey.currentContext?.size ?? Size.zero;
            final freeX = cell.width - stamp.width;
            final freeY = cell.height - stamp.height;
            if (freeX > 1) {
              s.x = (s.x + d.focalPointDelta.dx / freeX).clamp(0.0, 1.0);
            }
            if (freeY > 1) {
              s.y = (s.y + d.focalPointDelta.dy / freeY).clamp(0.0, 1.0);
            }
            c.changed();
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.move,
            child: Container(
              key: _textKey,
              padding: EdgeInsets.symmetric(
                  horizontal: fontSize * 0.3, vertical: fontSize * 0.1),
              decoration: editing
                  ? BoxDecoration(
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.8),
                          width: 1),
                      borderRadius: BorderRadius.circular(4),
                    )
                  : null,
              child: Text(
                formatStampDate(p.takenAt!),
                key: Key('date-stamp-${widget.index}'),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontFamilyFallback: const ['Consolas', 'Courier New'],
                  fontWeight: FontWeight.w700,
                  fontSize: fontSize,
                  letterSpacing: fontSize * 0.08,
                  color: color,
                  shadows: [
                    // Soft glow like a film camera's burned-in date...
                    Shadow(
                        blurRadius: fontSize * 0.3,
                        color: color.withValues(alpha: 0.55)),
                    // ...plus a faint outline so it reads on light photos.
                    Shadow(
                        blurRadius: fontSize * 0.08,
                        color: (color.computeLuminance() > 0.5
                                ? Colors.black
                                : Colors.white)
                            .withValues(alpha: 0.45)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}
