import 'package:flutter/widgets.dart';
import 'package:video_player_videohole/video_player.dart' as vp;

/// Sizes the hardware video rectangle itself; Flutter clipping alone cannot
/// resize Samsung's separate video plane.
class TizenVideoView extends StatelessWidget {
  const TizenVideoView({
    super.key,
    required this.controller,
    required this.fit,
  });

  final vp.VideoPlayerController controller;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final source = controller.value.size;
      if (source.isEmpty) return const SizedBox.shrink();
      final fitted = applyBoxFit(fit, source, constraints.biggest);
      final width =
          source.width * fitted.destination.width / fitted.source.width;
      final height =
          source.height * fitted.destination.height / fitted.source.height;
      return ClipRect(
        child: OverflowBox(
          alignment: Alignment.center,
          minWidth: width,
          maxWidth: width,
          minHeight: height,
          maxHeight: height,
          child: SizedBox(
            width: width,
            height: height,
            child: vp.VideoPlayer(controller),
          ),
        ),
      );
    },
  );
}
