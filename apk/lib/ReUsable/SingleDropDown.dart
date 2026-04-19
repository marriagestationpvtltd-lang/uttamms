import 'package:flutter/material.dart';

class SingleSelectDropdown extends StatefulWidget {
  final List<String> items;
  final String selectedItem;
  final String hintText;
  final Function(String) onChanged;

  const SingleSelectDropdown({
    super.key,
    required this.items,
    required this.selectedItem,
    required this.onChanged,
    this.hintText = "Select",
  });

  @override
  State<SingleSelectDropdown> createState() => _SingleSelectDropdownState();
}

class _SingleSelectDropdownState extends State<SingleSelectDropdown> {
  late String currentSelection;
  late List<String> filteredItems;

  @override
  void initState() {
    super.initState();
    currentSelection = widget.selectedItem;
    filteredItems = widget.items;
  }

  void _openDropdown() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return StatefulBuilder(builder: (context, setSheetState) {
          return Container(
            padding: const EdgeInsets.all(16),
            height: MediaQuery.of(context).size.height * 0.5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.hintText,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFE64B37), // red color
                  ),
                ),
                const SizedBox(height: 15),

                // Search Field
                TextField(
                  decoration: InputDecoration(
                    hintText: "Search...",
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: const BorderSide(
                        color: Color(0xFF48A54C), // green border
                        width: 1.5,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                  ),
                  onChanged: (value) {
                    setSheetState(() {
                      filteredItems = widget.items
                          .where((item) => item
                          .toLowerCase()
                          .contains(value.toLowerCase()))
                          .toList();
                    });
                  },
                ),

                const SizedBox(height: 20),

                // List of items
                Expanded(
                  child: filteredItems.isEmpty
                      ? const Center(
                    child: Text(
                      "No items found",
                      style: TextStyle(
                          fontSize: 16, color: Colors.black54),
                    ),
                  )
                      : ListView.builder(
                    itemCount: filteredItems.length,
                    itemBuilder: (_, index) {
                      final item = filteredItems[index];
                      return ListTile(
                        title: Text(
                          item,
                          style: const TextStyle(
                              fontSize: 16, color: Colors.black87),
                        ),
                        trailing: item == currentSelection
                            ? const Icon(Icons.check_circle,
                            color: Color(0xFFE64B37))
                            : null,
                        onTap: () {
                          setState(() {
                            currentSelection = item;
                          });
                          widget.onChanged(item);
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        });
      },
    ).then((_) {
      if (mounted) {
        // Use post-frame callback so unfocus runs after Flutter restores focus
        // from the closed modal route, ensuring the keyboard stays hidden.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) FocusManager.instance.primaryFocus?.unfocus();
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _openDropdown,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: const Color(0xFF48A54C), width: 1.6),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              currentSelection.isEmpty ? widget.hintText : currentSelection,
              style: TextStyle(
                fontSize: 16,
                color: currentSelection.isEmpty
                    ? Colors.black45
                    : Colors.black87,
              ),
            ),
            const Icon(Icons.keyboard_arrow_down, color: Colors.black54),
          ],
        ),
      ),
    );
  }
}
