import 'package:flutter/material.dart';

import 'collage_controller.dart';
import 'collage_models.dart';
import 'color_matrix.dart';
import 'layouts.dart';

/// The four tools in the bottom bar.
enum CollageTool {
  layout('Layout', Icons.dashboard_outlined, Icons.dashboard,
      'Drag the handles between photos to resize them'),
  photo('Photo', Icons.crop_rotate_outlined, Icons.crop_rotate,
      'Pinch or scroll to zoom · drag to move · double-tap to reset · '
          'long-press to swap'),
  color('Color', Icons.palette_outlined, Icons.palette,
      'Edit all photos together or just the selected one'),
  date('Date', Icons.event_outlined, Icons.event,
      'Drag a date to move it · pinch it to resize');

  const CollageTool(this.label, this.icon, this.selectedIcon, this.hint);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String hint;
}

/// The controls for the active [tool], shown under the collage.
class CollageToolPanel extends StatelessWidget {
  final CollageTool tool;
  final CollageController c;
  final VoidCallback onAddPhoto;
  final VoidCallback onReplace;

  const CollageToolPanel({
    super.key,
    required this.tool,
    required this.c,
    required this.onAddPhoto,
    required this.onReplace,
  });

  @override
  Widget build(BuildContext context) => switch (tool) {
        CollageTool.layout => _LayoutPanel(c: c, onAddPhoto: onAddPhoto),
        CollageTool.photo => _PhotoPanel(c: c, onReplace: onReplace),
        CollageTool.color => _ColorPanel(c: c),
        CollageTool.date => _DatePanel(c: c),
      };
}

// --- Shared bits -------------------------------------------------------------

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
      child: Text(text,
          style: theme.textTheme.labelLarge
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String Function(double) display;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 84, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            label: display(value),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(display(value), textAlign: TextAlign.end),
        ),
      ],
    );
  }
}

String _signedPercent(double v) {
  final p = (v * 100).round();
  return p > 0 ? '+$p' : '$p';
}

class _ColorDots extends StatelessWidget {
  final List<Color> colors;
  final Color selected;
  final ValueChanged<Color> onSelected;
  final String tooltipPrefix;

  const _ColorDots({
    required this.colors,
    required this.selected,
    required this.onSelected,
    required this.tooltipPrefix,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        for (final (i, color) in colors.indexed)
          Tooltip(
            message: '$tooltipPrefix ${i + 1}',
            child: InkResponse(
              onTap: () => onSelected(color),
              radius: 22,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: color == selected
                        ? scheme.primary
                        : scheme.outlineVariant,
                    width: color == selected ? 3 : 1,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Shown on per-photo tools when nothing is selected.
class _SelectHint extends StatelessWidget {
  final String text;
  const _SelectHint(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.touch_app_outlined,
              color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Flexible(
            child: Text(text,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}

/// Icon over a label — the big, easy targets used for photo actions.
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const _ActionButton(this.icon, this.label, this.onPressed);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon),
              const SizedBox(height: 4),
              Text(label,
                  style: Theme.of(context).textTheme.labelSmall,
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Layout -------------------------------------------------------------------

class _LayoutPanel extends StatelessWidget {
  final CollageController c;
  final VoidCallback onAddPhoto;
  const _LayoutPanel({required this.c, required this.onAddPhoto});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final presets = presetsFor(c.photos.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Label('Layout'),
        SizedBox(
          height: 76,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final p in presets)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Tooltip(
                    message: p.name,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => c.usePreset(p),
                      child: Container(
                        width: 64,
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: p.id == c.preset.id
                                ? scheme.primary
                                : scheme.outlineVariant,
                            width: p.id == c.preset.id ? 2.5 : 1,
                          ),
                        ),
                        child: LayoutThumb(node: p.build()),
                      ),
                    ),
                  ),
                ),
              if (c.canAddMore)
                Tooltip(
                  message: 'Add photo',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: onAddPhoto,
                    child: Container(
                      width: 64,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined,
                              color: scheme.primary),
                          Text('Add',
                              style: TextStyle(
                                  fontSize: 12, color: scheme.primary)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const _Label('Shape'),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final s in CanvasShape.all)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(s.label),
                    selected: c.shape == s,
                    onSelected: (_) => c.setShape(s),
                  ),
                ),
            ],
          ),
        ),
        const _Label('Border'),
        _SliderRow(
          label: 'Width',
          value: c.border,
          min: 0,
          max: 24,
          display: (v) => v.round().toString(),
          onChanged: (v) {
            c.border = v;
            c.changed();
          },
        ),
        _SliderRow(
          label: 'Corners',
          value: c.cornerRadius,
          min: 0,
          max: 32,
          display: (v) => v.round().toString(),
          onChanged: (v) {
            c.cornerRadius = v;
            c.changed();
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
          child: _ColorDots(
            colors: borderColors,
            selected: c.borderColor,
            tooltipPrefix: 'Border colour',
            onSelected: (color) {
              c.borderColor = color;
              c.changed();
            },
          ),
        ),
      ],
    );
  }
}

/// A tiny picture of a layout tree — the layout picker's icons.
class LayoutThumb extends StatelessWidget {
  final LayoutNode node;
  const LayoutThumb({super.key, required this.node});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary.withValues(alpha: 0.55);
    Widget build(LayoutNode n) => switch (n) {
          LeafNode() => Container(
              margin: const EdgeInsets.all(1.5),
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(2))),
          SplitNode() => Flex(
              direction: n.axis,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: (n.ratio * 1000).round(), child: build(n.first)),
                Expanded(
                    flex: ((1 - n.ratio) * 1000).round(),
                    child: build(n.second)),
              ],
            ),
        };
    return build(node);
  }
}

// --- Photo --------------------------------------------------------------------

class _PhotoPanel extends StatelessWidget {
  final CollageController c;
  final VoidCallback onReplace;
  const _PhotoPanel({required this.c, required this.onReplace});

  @override
  Widget build(BuildContext context) {
    final p = c.selectedPhoto;
    if (p == null) {
      return const _SelectHint('Tap a photo in the collage to edit it');
    }
    final i = c.selected!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Label('Photo ${i + 1} of ${c.photos.length}'),
        Row(
          children: [
            _ActionButton(Icons.rotate_left, 'Rotate left',
                () => c.rotate(p, clockwise: false)),
            _ActionButton(Icons.rotate_right, 'Rotate right', () => c.rotate(p)),
            _ActionButton(Icons.flip, 'Mirror', () => c.flip(p)),
            _ActionButton(Icons.swap_horiz, 'Replace', onReplace),
            _ActionButton(
                Icons.delete_outline, 'Remove', () => c.removePhoto(i)),
          ],
        ),
        const _Label('Crop'),
        _SliderRow(
          label: 'Zoom',
          value: p.zoom,
          min: 1,
          max: PhotoItem.maxZoom,
          display: (v) => '${v.toStringAsFixed(1)}×',
          onChanged: (v) {
            p.zoom = v;
            c.changed();
          },
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: p.zoom == 1 && p.alignX == 0 && p.alignY == 0
                ? null
                : () {
                    p.resetCrop();
                    c.changed();
                  },
            icon: const Icon(Icons.crop_free),
            label: const Text('Reset crop'),
          ),
        ),
      ],
    );
  }
}

// --- Color --------------------------------------------------------------------

class _ColorPanel extends StatelessWidget {
  final CollageController c;
  const _ColorPanel({required this.c});

  @override
  Widget build(BuildContext context) {
    final hasSelection = c.selectedPhoto != null;
    final scope = hasSelection ? c.colorScope : ColorScope.all;
    final a = c.editedAdjustments;
    final preview = c.selectedPhoto ?? c.photos.first;

    void update(void Function() f) {
      f();
      c.changed();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        SegmentedButton<ColorScope>(
          segments: [
            const ButtonSegment(
                value: ColorScope.all,
                icon: Icon(Icons.collections_outlined),
                label: Text('All photos')),
            ButtonSegment(
                value: ColorScope.selected,
                enabled: hasSelection,
                icon: const Icon(Icons.photo_outlined),
                label: Text(hasSelection
                    ? 'Photo ${c.selected! + 1}'
                    : 'Select a photo')),
          ],
          selected: {scope},
          onSelectionChanged: (s) => update(() => c.colorScope = s.first),
        ),
        const _Label('Tone'),
        SizedBox(
          height: 96,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final t in ToneFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _ToneSwatch(
                    tone: t,
                    photo: preview,
                    selected: a.tone == t,
                    onTap: () => update(() => a.tone = t),
                  ),
                ),
            ],
          ),
        ),
        const _Label('Adjust'),
        _SliderRow(
          label: 'Hue',
          value: a.hue,
          min: -180,
          max: 180,
          display: (v) => '${v.round()}°',
          onChanged: (v) => update(() => a.hue = v),
        ),
        _SliderRow(
          label: 'Saturation',
          value: a.saturation,
          min: -1,
          max: 1,
          display: _signedPercent,
          onChanged: (v) => update(() => a.saturation = v),
        ),
        _SliderRow(
          label: 'Brightness',
          value: a.brightness,
          min: -1,
          max: 1,
          display: _signedPercent,
          onChanged: (v) => update(() => a.brightness = v),
        ),
        _SliderRow(
          label: 'Warmth',
          value: a.warmth,
          min: -1,
          max: 1,
          display: _signedPercent,
          onChanged: (v) => update(() => a.warmth = v),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: a.isIdentity ? null : () => update(a.reset),
            icon: const Icon(Icons.restart_alt),
            label: Text(scope == ColorScope.all
                ? 'Reset all photos'
                : 'Reset this photo'),
          ),
        ),
      ],
    );
  }
}

class _ToneSwatch extends StatelessWidget {
  final ToneFilter tone;
  final PhotoItem photo;
  final bool selected;
  final VoidCallback onTap;

  const _ToneSwatch({
    required this.tone,
    required this.photo,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: SizedBox(
        width: 60,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected ? scheme.primary : Colors.transparent,
                  width: 2.5,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: ColorFiltered(
                  colorFilter: ColorFilter.matrix(ColorMatrix.tone(tone)),
                  child: RotatedBox(
                    quarterTurns: photo.quarterTurns,
                    child: Image(
                        image: photo.image,
                        fit: BoxFit.cover,
                        gaplessPlayback: true),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(tone.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                )),
          ],
        ),
      ),
    );
  }
}

// --- Date ---------------------------------------------------------------------

class _DatePanel extends StatelessWidget {
  final CollageController c;
  const _DatePanel({required this.c});

  String _sourceText(PhotoItem p) => switch (p.dateSource) {
        DateSource.exif => 'from the camera',
        DateSource.fileName => 'from the file name',
        DateSource.fileModified => 'file date — may not be when it was taken',
        DateSource.manual => 'set by you',
        DateSource.unknown => 'unknown',
      };

  Future<void> _pickDate(BuildContext context, PhotoItem p) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: p.takenAt ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      helpText: 'Date taken',
    );
    if (picked == null) return;
    p.takenAt = picked;
    p.dateSource = DateSource.manual;
    c.changed();
  }

  @override
  Widget build(BuildContext context) {
    final p = c.selectedPhoto;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          title: const Text('Show date taken'),
          subtitle: const Text('Stamped as dd.mm.yy'),
          value: c.showDates,
          onChanged: (v) {
            c.showDates = v;
            c.changed();
          },
        ),
        if (c.showDates) ...[
          const _Label('Colour'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _ColorDots(
              colors: dateStampColors,
              selected: c.dateColor,
              tooltipPrefix: 'Date colour',
              onSelected: (color) {
                c.dateColor = color;
                c.changed();
              },
            ),
          ),
          if (p == null)
            const _SelectHint('Tap a photo to resize, hide or change its date')
          else ...[
            _Label('Photo ${c.selected! + 1}'),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: Text(p.takenAt == null
                  ? 'No date found'
                  : formatStampDate(p.takenAt!)),
              subtitle: Text(p.takenAt == null
                  ? 'Set one with "Change date"'
                  : _sourceText(p)),
              value: p.showDate,
              onChanged: p.takenAt == null
                  ? null
                  : (v) {
                      p.showDate = v;
                      c.changed();
                    },
            ),
            _SliderRow(
              label: 'Size',
              value: p.stamp.size,
              min: DateStampPlacement.minSize,
              max: DateStampPlacement.maxSize,
              display: (v) => '${(v * 1000).round()}',
              onChanged: (v) {
                p.stamp.size = v;
                c.changed();
              },
            ),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              children: [
                TextButton.icon(
                  onPressed: () => _pickDate(context, p),
                  icon: const Icon(Icons.edit_calendar_outlined),
                  label: const Text('Change date'),
                ),
                if (c.photos.length > 1)
                  TextButton.icon(
                    onPressed: () => c.applyStampToAll(p),
                    icon: const Icon(Icons.copy_all_outlined),
                    label: const Text('Same spot & size on all'),
                  ),
              ],
            ),
          ],
        ],
      ],
    );
  }
}
