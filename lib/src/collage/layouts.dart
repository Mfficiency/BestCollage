import 'package:flutter/widgets.dart';

import 'collage_models.dart';

/// A ready-made arrangement for a given number of photos. [build] returns a
/// fresh tree every time so dragging dividers never edits the preset itself.
class LayoutPreset {
  final String id;
  final String name;
  final int count;
  final LayoutNode Function() build;

  const LayoutPreset(this.id, this.name, this.count, this.build);
}

const _h = Axis.horizontal; // side by side
const _v = Axis.vertical; // stacked
const _third = 1 / 3;

LeafNode _l(int slot) => LeafNode(slot);

/// All presets, grouped by photo count; the first of each count is the default.
final List<LayoutPreset> layoutPresets = [
  LayoutPreset('1', 'Single', 1, () => _l(0)),
  // --- 2 ---
  LayoutPreset('2-side', 'Side by side', 2, () => SplitNode(_h, _l(0), _l(1))),
  LayoutPreset('2-stack', 'Stacked', 2, () => SplitNode(_v, _l(0), _l(1))),
  // --- 3 ---
  LayoutPreset('3-left', 'Big left', 3,
      () => SplitNode(_h, _l(0), SplitNode(_v, _l(1), _l(2)), ratio: 0.6)),
  LayoutPreset('3-top', 'Big top', 3,
      () => SplitNode(_v, _l(0), SplitNode(_h, _l(1), _l(2)), ratio: 0.6)),
  LayoutPreset('3-right', 'Big right', 3,
      () => SplitNode(_h, SplitNode(_v, _l(0), _l(1)), _l(2), ratio: 0.4)),
  LayoutPreset('3-bottom', 'Big bottom', 3,
      () => SplitNode(_v, SplitNode(_h, _l(0), _l(1)), _l(2), ratio: 0.4)),
  LayoutPreset('3-cols', 'Columns', 3,
      () => SplitNode(_h, _l(0), SplitNode(_h, _l(1), _l(2)), ratio: _third)),
  LayoutPreset('3-rows', 'Rows', 3,
      () => SplitNode(_v, _l(0), SplitNode(_v, _l(1), _l(2)), ratio: _third)),
  // --- 4 ---
  LayoutPreset(
      '4-grid',
      'Grid',
      4,
      () => SplitNode(
          _v, SplitNode(_h, _l(0), _l(1)), SplitNode(_h, _l(2), _l(3)))),
  LayoutPreset(
      '4-left',
      'Big left',
      4,
      () => SplitNode(
          _h,
          _l(0),
          SplitNode(_v, _l(1), SplitNode(_v, _l(2), _l(3)), ratio: _third),
          ratio: 0.6)),
  LayoutPreset(
      '4-top',
      'Big top',
      4,
      () => SplitNode(
          _v,
          _l(0),
          SplitNode(_h, _l(1), SplitNode(_h, _l(2), _l(3)), ratio: _third),
          ratio: 0.6)),
  LayoutPreset(
      '4-cols',
      'Columns',
      4,
      () => SplitNode(_h, SplitNode(_h, _l(0), _l(1)),
          SplitNode(_h, _l(2), _l(3)))),
  LayoutPreset(
      '4-rows',
      'Rows',
      4,
      () => SplitNode(_v, SplitNode(_v, _l(0), _l(1)),
          SplitNode(_v, _l(2), _l(3)))),
];

List<LayoutPreset> presetsFor(int count) =>
    layoutPresets.where((p) => p.count == count.clamp(1, 4)).toList();
