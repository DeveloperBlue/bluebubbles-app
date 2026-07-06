import 'dart:math';
import 'package:flutter/material.dart';
import 'package:bluebubbles/database/models.dart';

class SwipeableAttachmentStack extends StatefulWidget {
  const SwipeableAttachmentStack({
    super.key,
    required this.attachments,
    required this.initialIndex,
    this.onIndexChanged,
  });

  final List<Attachment> attachments;
  final int initialIndex;
  final ValueChanged<int>? onIndexChanged;

  @override
  State<SwipeableAttachmentStack> createState() => _SwipeableAttachmentStackState();
}

class _SwipeableAttachmentStackState extends State<SwipeableAttachmentStack> {
  late int currentIndex;
  double dragOffset = 0.0;
  bool isDragging = false;
  static const int maxStackedItems = 4;
  static const double stackOffset = 8.0;
  static const double stackScale = 0.05;

  @override
  void initState() {
    super.initState();
    currentIndex = widget.initialIndex;
  }

  List<Attachment> get visibleAttachments {
    return widget.attachments.where((a) {
      return a.mimeStart == "image" || 
             a.mimeStart == "video" || 
             a.mimeType == "audio/mp4";
    }).toList();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    setState(() {
      dragOffset += details.primaryDelta ?? 0;
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    final threshold = MediaQuery.of(context).size.width * 0.3;
    
    setState(() {
      if (dragOffset.abs() > threshold) {
        if (dragOffset > 0 && currentIndex > 0) {
          // Swipe right - go to previous
          currentIndex--;
          widget.onIndexChanged?.call(currentIndex);
        } else if (dragOffset < 0 && currentIndex < visibleAttachments.length - 1) {
          // Swipe left - go to next
          currentIndex++;
          widget.onIndexChanged?.call(currentIndex);
        }
      }
      dragOffset = 0.0;
      isDragging = false;
    });
  }

  Widget _buildStackedItem({
    required Attachment attachment,
    required int stackIndex,
    required bool isLeft,
  }) {
    final offset = stackOffset * (stackIndex + 1);
    final scale = 1.0 - (stackScale * (stackIndex + 1));
    
    return Positioned(
      left: isLeft ? -offset : null,
      right: isLeft ? null : -offset,
      top: offset,
      child: Transform.scale(
        scale: scale,
        child: Opacity(
          opacity: 0.6 - (stackIndex * 0.1),
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: _buildAttachmentPreview(attachment),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAttachmentPreview(Attachment attachment) {
    // Placeholder - you'll need to integrate with your actual attachment loading logic
    return Container(
      color: Colors.grey[400],
      child: Center(
        child: Icon(
          attachment.mimeStart == "video" ? Icons.play_circle_outline : Icons.image,
          size: 40,
          color: Colors.white70,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = visibleAttachments;
    if (items.isEmpty) return const SizedBox.shrink();

    final leftStackItems = <Widget>[];
    final rightStackItems = <Widget>[];

    // Build left stack (previous items)
    for (int i = 1; i <= min(maxStackedItems, currentIndex); i++) {
      final index = currentIndex - i;
      leftStackItems.add(
        _buildStackedItem(
          attachment: items[index],
          stackIndex: i - 1,
          isLeft: true,
        ),
      );
    }

    // Build right stack (next items)
    for (int i = 1; i <= min(maxStackedItems, items.length - currentIndex - 1); i++) {
      final index = currentIndex + i;
      rightStackItems.add(
        _buildStackedItem(
          attachment: items[index],
          stackIndex: i - 1,
          isLeft: false,
        ),
      );
    }

    return SizedBox(
      height: 250,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Left stack
          ...leftStackItems,
          
          // Right stack
          ...rightStackItems,
          
          // Main item
          GestureDetector(
            onHorizontalDragUpdate: _handleDragUpdate,
            onHorizontalDragEnd: _handleDragEnd,
            onHorizontalDragStart: (_) => setState(() => isDragging = true),
            child: AnimatedContainer(
              duration: isDragging ? Duration.zero : const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              transform: Matrix4.translationValues(dragOffset, 0, 0),
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    children: [
                      _buildAttachmentPreview(items[currentIndex]),
                      
                      // Counter badge
                      if (items.length > 1)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${currentIndex + 1}/${items.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}