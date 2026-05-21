// ignore_for_file: use_string_in_part_of_directives, invalid_use_of_protected_member
part of 'call_overlay_manager.dart';

Future<void> openMinimizedCallHost(BuildContext context) async {
  CallOverlayManager().minimizeCall();
  await Navigator.of(context).push(
    MaterialPageRoute(
      settings: const RouteSettings(name: minimizedCallHostRouteName),
      builder: (_) => const MainControllerScreen(initialIndex: 0),
    ),
  );
}

class CallMinimizeButton extends StatelessWidget {
  final VoidCallback onPressed;

  const CallMinimizeButton({
    super.key,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7C4DFF), Color(0xFF00C6FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C4DFF).withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(22),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.picture_in_picture_alt_rounded,
                    color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text(
                  'Minimize',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
