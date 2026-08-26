import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Empty placeholder for a full-page attachment category.
class AttachmentSectionEmpty extends StatelessWidget {
  final String message;
  final VoidCallback? onClearFilters;

  const AttachmentSectionEmpty({
    super.key,
    required this.message,
    this.onClearFilters,
  });

  /// Items exist, but the active filters exclude all of them.
  const AttachmentSectionEmpty.noFilterResults({
    super.key,
    required VoidCallback this.onClearFilters,
  }) : message = "No results for the selected filters";

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 20.0),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.theme.textTheme.bodyMedium!.copyWith(
                color: context.theme.colorScheme.outline,
              ),
            ),
            if (onClearFilters != null)
              TextButton(
                onPressed: onClearFilters,
                child: const Text("Clear filters"),
              ),
          ],
        ),
      ),
    );
  }
}
