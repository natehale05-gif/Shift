import 'package:flutter/material.dart';

import '../../models/studio_type.dart';

class StudioQuickActionChip extends StatelessWidget {
  final StudioType studioType;
  final VoidCallback onTap;

  const StudioQuickActionChip({
    super.key,
    required this.studioType,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(studioType.icon, size: 16, color: studioType.accent),
      label: Text(studioType.shortName),
      onPressed: onTap,
    );
  }
}
