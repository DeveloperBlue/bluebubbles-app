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
  final double childWidthFactor; // e.g., 0.78 for 78% width
  final bool invertStagger;

  const OverlapColumn({
    super.key,
    required this.children,
    this.overlap = 8.0,
    this.showDebugBorder = false,
    this.debugBorderColor,
    this.childWidthFactor = 1.0,
    this.invertStagger = false,
  });

  @override
  State<OverlapColumn> createState() => _OverlapColumnState();
}

class _OverlapColumnState extends State<OverlapColumn> {
  @override
  Widget build(BuildContext context) {
    Widget child = _OverlapColumnRenderWidget(
      overlap: widget.overlap,
      childWidthFactor: widget.childWidthFactor,
      invertStagger: widget.invertStagger,
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
  final double childWidthFactor;
  final bool invertStagger;

  _OverlapColumnRenderWidget({
    required this.overlap,
    required this.childWidthFactor,
    required this.invertStagger,
    required List<Widget> children,
  }) : super(children: children);

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderOverlapColumn(
      overlap: overlap,
      childWidthFactor: childWidthFactor,
      invertStagger: invertStagger,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderOverlapColumn renderObject) {
    renderObject
      ..overlap = overlap
      ..childWidthFactor = childWidthFactor
      ..invertStagger = invertStagger;
  }
}

class OverlapColumnParentData extends ContainerBoxParentData<RenderBox> {}

class RenderOverlapColumn extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, OverlapColumnParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, OverlapColumnParentData> {
  double _overlap;
  double _childWidthFactor;
  bool _invertStagger;

  RenderOverlapColumn({
    required double overlap,
    required double childWidthFactor,
    required bool invertStagger,
  })  : _overlap = overlap,
        _childWidthFactor = childWidthFactor,
        _invertStagger = invertStagger;

  double get overlap => _overlap;
  set overlap(double value) {
    if (_overlap != value) {
      _overlap = value;
      markNeedsLayout();
    }
  }

  double get childWidthFactor => _childWidthFactor;
  set childWidthFactor(double value) {
    if (_childWidthFactor != value) {
      _childWidthFactor = value;
      markNeedsLayout();
    }
  }

  bool get invertStagger => _invertStagger;
  set invertStagger(bool value) {
    if (_invertStagger != value) {
      _invertStagger = value;
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

    // Calculate the actual width children should use
    final containerWidth = constraints.maxWidth;
    final childWidth = containerWidth * _childWidthFactor;
    final rightOffset = containerWidth - childWidth; // Space for right alignment

    double yOffset = 0.0;
    double maxWidth = containerWidth; // Use full container width
    RenderBox? child = firstChild;
    int index = 0;
    double lastChildBottom = 0.0;

    // Layout each child with the reduced width constraint
    while (child != null) {
      final childParentData = child.parentData as OverlapColumnParentData;
      
      // Constrain children to the reduced width
      final childConstraints = BoxConstraints(
        minWidth: childWidth,
        maxWidth: childWidth,
        minHeight: 0,
        maxHeight: constraints.maxHeight.isFinite ? constraints.maxHeight : double.infinity,
      );
      
      child.layout(childConstraints, parentUsesSize: true);

      // Calculate x offset based on index and alignment setting
      double xOffset = 0.0;
      if (index % 2 == (invertStagger ? 1 : 0)) {
      // Even-numbered children (index 0, 2, 4...) stay left-aligned at 0
        xOffset = rightOffset;
      }
      // Odd-numbered children (index 1, 3, 5...) are left-aligned

      // Position the child
      childParentData.offset = Offset(xOffset, yOffset);

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
      final childHeight = child.getMinIntrinsicHeight(width * _childWidthFactor);
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