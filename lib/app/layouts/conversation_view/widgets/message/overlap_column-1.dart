import 'dart:math';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A custom layout widget that arranges children vertically with a slight overlap,
/// while automatically shrinking its total height to fit the overlapped content.
class OverlapColumn extends StatefulWidget {
  final List<Widget> children;
  final double overlap;
  final bool showDebugBorder;
  final Color? debugBorderColor;

  const OverlapColumn({
    super.key,
    required this.children,
    this.overlap = 8.0,
    this.showDebugBorder = false,
    this.debugBorderColor,
  });

  @override
  State<OverlapColumn> createState() => _OverlapColumnState();
}

class _OverlapColumnState extends State<OverlapColumn> {
  @override
  Widget build(BuildContext context) {
    Widget child = _OverlapColumnRenderWidget(
      overlap: widget.overlap,
      children: widget.children,
    );

    if (widget.showDebugBorder) {
      child = DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: widget.debugBorderColor ?? const Color(0xFFFF00FF),
            width: 2,
          ),
        ),
        child: child,
      );
    }

    return child;
  }
}

class _OverlapColumnRenderWidget extends MultiChildRenderObjectWidget {
  final double overlap;

  _OverlapColumnRenderWidget({
    required this.overlap,
    required List<Widget> children,
  }) : super(children: children);

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderOverlapColumn(overlap: overlap);
  }

  @override
  void updateRenderObject(BuildContext context, RenderOverlapColumn renderObject) {
    renderObject.overlap = overlap;
  }
}

class OverlapColumnParentData extends ContainerBoxParentData<RenderBox> {}

class RenderOverlapColumn extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, OverlapColumnParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, OverlapColumnParentData> {
  double _overlap;

  RenderOverlapColumn({
    required double overlap,
  }) : _overlap = overlap;

  double get overlap => _overlap;
  set overlap(double value) {
    if (_overlap != value) {
      _overlap = value;
      markNeedsLayout();
    }
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! OverlapColumnParentData) {
      child.parentData = OverlapColumnParentData();
    }
  }

  @override
  void performLayout() {
    if (childCount == 0) {
      size = constraints.constrain(Size.zero);
      return;
    }

    double yOffset = 0.0;
    double maxWidth = 0.0;
    RenderBox? child = firstChild;
    int index = 0;
    double lastChildBottom = 0.0;

    // Layout each child with the parent's constraints
    while (child != null) {
      final childParentData = child.parentData as OverlapColumnParentData;
      
      // Pass through the parent's constraints to children
      final childConstraints = BoxConstraints(
        minWidth: 0,
        maxWidth: constraints.maxWidth,
        minHeight: 0,
        maxHeight: constraints.maxHeight,
      );
      
      child.layout(childConstraints, parentUsesSize: true);

      // Position the child
      childParentData.offset = Offset(0, yOffset);

      // Track the widest child
      maxWidth = max(maxWidth, child.size.width);

      // Calculate the bottom of this child
      lastChildBottom = yOffset + child.size.height;

      // Calculate next offset - don't apply overlap for the first item
      if (index == 0) {
        yOffset += child.size.height;
      } else {
        yOffset += child.size.height - _overlap;
      }

      child = childParentData.nextSibling;
      index++;
    }

    // The total height should be the bottom of the last child
    // This accounts for all overlaps correctly
    final totalHeight = lastChildBottom;

    // Set our size based on constraints and calculated dimensions
    size = constraints.constrain(Size(maxWidth, totalHeight));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    if (childCount == 0) return 0.0;
    
    double totalHeight = 0.0;
    RenderBox? child = firstChild;
    int index = 0;

    while (child != null) {
      final childHeight = child.getMinIntrinsicHeight(width);
      if (index == 0) {
        totalHeight = childHeight;
      } else {
        totalHeight += childHeight - _overlap;
      }
      child = (child.parentData as OverlapColumnParentData).nextSibling;
      index++;
    }

    return totalHeight;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    return computeMinIntrinsicHeight(width);
  }
}