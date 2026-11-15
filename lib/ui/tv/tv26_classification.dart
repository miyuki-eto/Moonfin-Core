import 'package:flutter/cupertino.dart';

import 'tv26_style.dart';

class Tv26Classification extends StatelessWidget {
  final String type;
  final bool isMovie;
  final List<String> genres;
  final String? rating;

  const Tv26Classification({
    super.key,
    required this.type,
    this.isMovie = false,
    this.genres = const [],
    this.rating,
  });

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 23,
        height: 23,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0x40000000),
          border: Border.all(color: const Color(0x88FFFFFF), width: .7),
        ),
        child: Icon(
          isMovie ? CupertinoIcons.bag_fill : CupertinoIcons.tv,
          size: 13,
          color: Tv26Style.foreground,
        ),
      ),
      const SizedBox(width: 7),
      Flexible(
        child: Text(
          [type, ...genres.take(2)].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Tv26Style.text(14),
        ),
      ),
      if (rating?.isNotEmpty ?? false) ...[
        const SizedBox(width: 7),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            border: Border.all(color: Tv26Style.foreground, width: .7),
            borderRadius: BorderRadius.circular(1),
          ),
          child: Text(
            rating!,
            style: Tv26Style.text(10, weight: FontWeight.w600, height: 1.05),
          ),
        ),
      ],
    ],
  );
}
