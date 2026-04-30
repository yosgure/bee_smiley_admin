// 親ファイル lib/plus_schedule_screen.dart のうち、独立した小さなウィジェット類を分離。
// _PlusScheduleContentState の private メンバ・ファイルローカル変数を共有するため part 構成。
part of '../plus_schedule_screen.dart';

/// 右上三角マーク用のカスタムペインター。
class _NoteTrianglePainter extends CustomPainter {
  final Color color;

  _NoteTrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// ホバー時に背景色をハイライトするコンテナ。
/// _PlusScheduleContentState._lessonItemTapped を直接書き換えるため private 共有が必要。
class _HoverContainer extends StatefulWidget {
  final Widget child;
  final VoidCallback? onEnter;
  final VoidCallback? onExit;
  final VoidCallback? onTap;

  const _HoverContainer({
    super.key,
    required this.child,
    this.onEnter,
    this.onExit,
    this.onTap,
  });

  @override
  State<_HoverContainer> createState() => _HoverContainerState();
}

class _HoverContainerState extends State<_HoverContainer> {
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => widget.onEnter?.call(),
      onExit: (_) => widget.onExit?.call(),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) {
          // フラグを設定して、セルレベルのGestureDetectorの追加ダイアログを抑制
          final state = context.findAncestorStateOfType<_PlusScheduleContentState>();
          if (state != null) {
            state._lessonItemTapped = true;
          }
        },
        onPointerUp: (_) {
          // 講師名・教室名がタップされた場合は生徒編集ダイアログを開かない
          if (_quickEditTappedGlobal) {
            _quickEditTappedGlobal = false;
            return;
          }
          widget.onTap?.call();
        },
        child: widget.child,
      ),
    );
  }
}

/// セルに紐づくタスク件数の小バッジ。
class _TaskBadge extends StatefulWidget {
  final int taskCount;
  final bool isToday;

  const _TaskBadge({
    required this.taskCount,
    required this.isToday,
  });

  @override
  State<_TaskBadge> createState() => _TaskBadgeState();
}

class _TaskBadgeState extends State<_TaskBadge> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final baseColor = widget.isToday ? AppColors.primary : const Color(0xFF78909C);
    final bgColor = _isHovered
        ? baseColor.withOpacity(0.2)
        : baseColor.withOpacity(0.12);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 12,
              color: baseColor,
            ),
            const SizedBox(width: 2),
            Text(
              '${widget.taskCount}',
              style: TextStyle(
                color: baseColor,
                fontSize: AppTextSize.caption,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
