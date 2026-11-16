import 'package:flutter/material.dart';

class TvLibraryGrid extends StatelessWidget {
  static const columns = 6;
  static const posterWidth = 119.0;
  static const posterHeight = 178.5;
  static const rowGap = 39.0;
  static const top = 95.0;

  final ScrollController controller;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  const TvLibraryGrid({
    super.key,
    required this.controller,
    required this.itemCount,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) => GridView.builder(
    controller: controller,
    padding: const EdgeInsets.fromLTRB(25, top, 48, 48),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns,
      crossAxisSpacing: 24,
      mainAxisSpacing: rowGap,
      childAspectRatio: 2 / 3,
    ),
    itemCount: itemCount,
    itemBuilder: itemBuilder,
  );
}
