import 'package:flutter/material.dart';

class PreviewProfilePage extends StatefulWidget {
  const PreviewProfilePage({super.key});

  @override
  State<PreviewProfilePage> createState() => _PreviewProfilePageState();
}

class _PreviewProfilePageState extends State<PreviewProfilePage> {
  double _rating = 0;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 500), () {
      _showRatingPopup();
    });
  }

  // ---------------- RATING POPUP -------------------
  void _showRatingPopup() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(20),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFFFF1500),
                  Color(0xFFFF0066),
                ],
              ),
              borderRadius: BorderRadius.circular(26),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.star, color: Colors.white, size: 70),

                const SizedBox(height: 10),
                const Text(
                  "Rate Your Experience",
                  style: TextStyle(
                    fontSize: 22,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  "Tap a star to give your rating",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 22),

                // Stars
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) {
                    return GestureDetector(
                      onTap: () {
                        setState(() => _rating = (i + 1).toDouble());
                      },
                      child: Icon(
                        _rating >= i + 1 ? Icons.star : Icons.star_border,
                        color: Colors.white,
                        size: 38,
                      ),
                    );
                  }),
                ),

                const SizedBox(height: 28),

                // Buttons Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // CANCEL
                    Expanded(
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text(
                            "Cancel",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // SUBMIT
                    Expanded(
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text(
                            "Submit",
                            style: TextStyle(
                              color: Color(0xFFFF1500),
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: SafeArea(
        child: Column(
          children: [
            // TOP BAR
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back, size: 26),
                  ),
                ],
              ),
            ),

            // PROFILE
            Column(
              children: [
                Container(
                  width: 100,
                  height: 100,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFFF1500),
                      width: 3,
                    ),
                  ),
                  child: const CircleAvatar(
                    backgroundImage: AssetImage(
                      'assets/girl.jpg',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  "Aarati shrestha",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 21,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  "Member id: 002343242837",
                  style: TextStyle(color: Colors.grey),
                ),

                // Rating
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.star, color: Color(0xFFFF1500), size: 22),
                    Icon(Icons.star, color: Color(0xFFFF1500), size: 22),
                    Icon(Icons.star, color: Color(0xFFFF1500), size: 22),
                    Icon(Icons.star, color: Color(0xFFFF1500), size: 22),
                    Icon(Icons.star_half, color: Color(0xFFFF1500), size: 22),
                    SizedBox(width: 6),
                    Text(
                      "4.5",
                      style: TextStyle(
                        color: Color(0xFFFF1500),
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 22),

            // VIEW PROFILE BUTTON
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _gradientButton(
                label: "View Complete Profile",
                onTap: () {},
              ),
            ),

            const SizedBox(height: 25),

            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // PHOTO GALLERY TITLE
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: const [
                          Text(
                            "Photo Gallery",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            "See More",
                            style: TextStyle(
                              color: Color(0xFFFF1500),
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        ],
                      ),
                      const SizedBox(height: 14),

                      GridView.builder(
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: 6,
                        shrinkWrap: true,
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                        ),
                        itemBuilder: (_, i) {
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.asset(
                              'assets/girl.jpg',
                              fit: BoxFit.cover,
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 20),

                      const Text(
                        "About",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt.",
                        style: TextStyle(color: Colors.grey, height: 1.4),
                      ),

                      const SizedBox(height: 25),

                      _gradientButton(label: "Report ID", onTap: () {}),
                      const SizedBox(height: 14),
                      _gradientButton(label: "Block", onTap: () {}),

                      const SizedBox(height: 35),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- BUTTON WIDGET -------------------
  Widget _gradientButton({required String label, required VoidCallback onTap}) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFFF1500),
            Color(0xFFFF0066),
          ],
        ),
        borderRadius: BorderRadius.all(Radius.circular(30)),
      ),
      child: Center(
        child: TextButton(
          onPressed: onTap,
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
