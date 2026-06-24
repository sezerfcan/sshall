import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/context_ext.dart';

/// Minimum on-screen size (px) of any panel in a split; the splitter stops
/// pushing once a neighbor would go below it.
const double kMinPanelPx = 140;

/// Hit/visual thickness of a splitter handle.
const double kSplitterThickness = 6;

/// A weight-based, resizable Row/Column (ADR 0019). Children are sized
/// proportionally to [weights] (which sum to 1); draggable handles between them
/// transfer weight to the neighbour. Double-tapping a handle equalizes the
/// branch. Resize is applied locally for a smooth drag and committed to the
/// owner via [onWeights] on drag end (so the rest of the app — terminals
/// included — does not rebuild on every pointer tick).
class ResizableSplit extends StatefulWidget {
  final Axis axis;
  final List<double> weights;
  final List<Widget> children;
  final ValueChanged<List<double>> onWeights;

  const ResizableSplit({
    super.key,
    required this.axis,
    required this.weights,
    required this.children,
    required this.onWeights,
  }) : assert(weights.length == children.length);

  @override
  State<ResizableSplit> createState() => _ResizableSplitState();
}

class _ResizableSplitState extends State<ResizableSplit> {
  late List<double> _weights = List<double>.from(widget.weights);
  double _available = 0;
  bool _dragging = false;

  @override
  void didUpdateWidget(ResizableSplit old) {
    super.didUpdateWidget(old);
    // Re-sync when the owner changed the weights (e.g. a panel was added or
    // removed) — but never mid-drag, where local state is authoritative.
    if (!_dragging && !listEquals(widget.weights, _weights)) {
      _weights = List<double>.from(widget.weights);
    }
  }

  void _onDrag(int i, double deltaPx) {
    if (_available <= 0) return;
    final deltaW = deltaPx / _available;
    final pairSum = _weights[i] + _weights[i + 1];
    final minW = kMinPanelPx / _available;
    var left = _weights[i] + deltaW;
    var right = _weights[i + 1] - deltaW;
    if (pairSum >= 2 * minW) {
      if (left < minW) {
        left = minW;
        right = pairSum - minW;
      }
      if (right < minW) {
        right = minW;
        left = pairSum - minW;
      }
    } else {
      left = pairSum / 2;
      right = pairSum / 2;
    }
    setState(() {
      _weights[i] = left;
      _weights[i + 1] = right;
    });
  }

  void _commit() {
    _dragging = false;
    widget.onWeights(List<double>.from(_weights));
  }

  void _equalize() {
    final n = _weights.length;
    setState(() => _weights = List<double>.filled(n, 1 / n));
    widget.onWeights(List<double>.from(_weights));
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.children.length;
    if (n == 1) return widget.children.first;

    return LayoutBuilder(
      builder: (context, cons) {
        final main = widget.axis == Axis.horizontal
            ? cons.maxWidth
            : cons.maxHeight;
        _available = (main - kSplitterThickness * (n - 1)).clamp(
          0.0,
          double.infinity,
        );

        final items = <Widget>[];
        for (var i = 0; i < n; i++) {
          if (i == n - 1) {
            // The last panel takes the remainder to avoid rounding overflow.
            items.add(Expanded(child: widget.children[i]));
          } else {
            final size = _weights[i] * _available;
            items.add(
              SizedBox(
                width: widget.axis == Axis.horizontal ? size : null,
                height: widget.axis == Axis.vertical ? size : null,
                child: widget.children[i],
              ),
            );
            items.add(
              _Splitter(
                index: i,
                axis: widget.axis,
                onDragStart: () => _dragging = true,
                onDrag: _onDrag,
                onCommit: _commit,
                onEqualize: _equalize,
              ),
            );
          }
        }
        return Flex(direction: widget.axis, children: items);
      },
    );
  }
}

class _Splitter extends StatefulWidget {
  final int index;
  final Axis axis;
  final VoidCallback onDragStart;
  final void Function(int index, double deltaPx) onDrag;
  final VoidCallback onCommit;
  final VoidCallback onEqualize;

  const _Splitter({
    required this.index,
    required this.axis,
    required this.onDragStart,
    required this.onDrag,
    required this.onCommit,
    required this.onEqualize,
  });

  @override
  State<_Splitter> createState() => _SplitterState();
}

class _SplitterState extends State<_Splitter> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final horizontal = widget.axis == Axis.horizontal;
    final line = _hover ? c.accent : c.border;

    return SizedBox(
      key: Key('resizeHandle_${widget.index}'),
      width: horizontal ? kSplitterThickness : null,
      height: horizontal ? null : kSplitterThickness,
      child: MouseRegion(
        cursor: horizontal
            ? SystemMouseCursors.resizeColumn
            : SystemMouseCursors.resizeRow,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Tooltip(
          message: 'Sürükle: panelleri boyutlandır · çift tık: eşitle',
          waitDuration: const Duration(milliseconds: 700),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTap: widget.onEqualize,
            onHorizontalDragStart: horizontal
                ? (_) => widget.onDragStart()
                : null,
            onHorizontalDragUpdate: horizontal
                ? (d) => widget.onDrag(widget.index, d.delta.dx)
                : null,
            onHorizontalDragEnd: horizontal ? (_) => widget.onCommit() : null,
            onVerticalDragStart: horizontal
                ? null
                : (_) => widget.onDragStart(),
            onVerticalDragUpdate: horizontal
                ? null
                : (d) => widget.onDrag(widget.index, d.delta.dy),
            onVerticalDragEnd: horizontal ? null : (_) => widget.onCommit(),
            child: Center(
              child: Container(
                width: horizontal ? (_hover ? 2 : 1) : double.infinity,
                height: horizontal ? double.infinity : (_hover ? 2 : 1),
                color: line,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
