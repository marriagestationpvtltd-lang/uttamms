import 'package:flutter/material.dart';

class InlineSearchDropdown<T> extends StatefulWidget {
  final List<T> items;
  final String Function(T) itemLabel;
  final T? selectedItem;
  final void Function(T?) onChanged;
  final String hint;

  const InlineSearchDropdown({
    Key? key,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
    this.selectedItem,
    this.hint = "Select item",
  }) : super(key: key);

  @override
  _InlineSearchDropdownState<T> createState() =>
      _InlineSearchDropdownState<T>();
}

class _InlineSearchDropdownState<T> extends State<InlineSearchDropdown<T>> {
  late List<T> filteredItems;
  final TextEditingController controller = TextEditingController();
  bool isDropdownOpen = false;

  @override
  void initState() {
    super.initState();
    filteredItems = widget.items;
    if (widget.selectedItem != null) {
      controller.text = widget.itemLabel(widget.selectedItem!);
    }
    controller.addListener(() {
      filterItems();
    });
  }

  void filterItems() {
    final query = controller.text.toLowerCase();
    setState(() {
      filteredItems = widget.items
          .where(
              (item) => widget.itemLabel(item).toLowerCase().contains(query))
          .toList();
    });
  }

  void selectItem(T item) {
    widget.onChanged(item);
    controller.text = widget.itemLabel(item);
    setState(() {
      isDropdownOpen = false;
    });
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: () {
            FocusScope.of(context).unfocus();
            setState(() {
              isDropdownOpen = !isDropdownOpen;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300, width: 1),
              borderRadius: BorderRadius.circular(25),
              color: Colors.white,
            ),
            child: Row(
              children: [
                Expanded(
                  child: IgnorePointer(
                    ignoring: !isDropdownOpen,
                    child: TextField(
                      controller: controller,
                      readOnly: !isDropdownOpen,
                      autofocus: false,
                      enableInteractiveSelection: isDropdownOpen,
                      decoration: InputDecoration(
                        hintText: widget.hint,
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ),
                Icon(
                  isDropdownOpen
                      ? Icons.arrow_drop_up
                      : Icons.arrow_drop_down,
                  size: 28,
                ),
              ],
            ),
          ),
        ),
        if (isDropdownOpen)
          Container(
            margin: const EdgeInsets.only(top: 5),
            padding: const EdgeInsets.all(0),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
              color: Colors.white,
            ),
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: filteredItems.length,
              itemBuilder: (context, index) {
                final item = filteredItems[index];
                return ListTile(
                  title: Text(widget.itemLabel(item)),
                  onTap: () => selectItem(item),
                );
              },
            ),
          ),
      ],
    );
  }
}
