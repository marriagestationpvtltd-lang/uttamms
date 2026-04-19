import 'package:flutter/material.dart';
import '../constant/app_colors.dart';

class TypingDropdown<T> extends StatefulWidget {
  final bool showError;

  final List<T> items;
  final String Function(T) itemLabel;
  final T? selectedItem;
  final void Function(T?) onChanged;
  final String hint;
  final String title;
  final String? errorText;
  final IconData? prefixIcon;

  const TypingDropdown({
    Key? key,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
    this.selectedItem,
    this.hint = "Select",
    required this.title,
    required this.showError,
    this.errorText,
    this.prefixIcon,
  }) : super(key: key);


  @override
  State<TypingDropdown<T>> createState() => _TypingDropdownState<T>();
}

class _TypingDropdownState<T> extends State<TypingDropdown<T>> {
  late TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(
      text: widget.selectedItem != null
          ? widget.itemLabel(widget.selectedItem!)
          : '',
    );
  }

  @override
  void didUpdateWidget(TypingDropdown<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedItem != oldWidget.selectedItem) {
      controller.text = widget.selectedItem != null
          ? widget.itemLabel(widget.selectedItem!)
          : '';
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _openBottomSheet() {
    FocusScope.of(context).unfocus();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        return FractionallySizedBox(
          heightFactor: 0.65, // 👈 HALF SCREEN (65%)
          child: _BottomSheetContent<T>(
            items: widget.items,
            itemLabel: widget.itemLabel,
            selectedItem: widget.selectedItem,
            title: widget.title,
            onSelected: (item) {
              controller.text = widget.itemLabel(item);
              widget.onChanged(item);
              Navigator.pop(context);
            },
            onClear: () {
              controller.clear();
              widget.onChanged(null);
              Navigator.pop(context);
            },
          ),
        );
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
    final bool hasError =
        widget.showError && widget.selectedItem == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 4),
          child: Row(
            children: [
              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                '*',
                style: TextStyle(
                  color: AppColors.error,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        // Dropdown Field
        Container(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: hasError
                    ? AppColors.error.withOpacity(0.1)
                    : AppColors.shadowLight,
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.white,
              border: Border.all(
                color: hasError ? AppColors.error : AppColors.border,
                width: hasError ? 2 : 1.5,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _openBottomSheet,
              child: IgnorePointer(
                child: TextField(
                  controller: controller,
                  readOnly: true,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    hintStyle: const TextStyle(
                      color: AppColors.textHint,
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: widget.prefixIcon != null ? 8 : 16,
                      vertical: 14,
                    ),
                    prefixIcon: widget.prefixIcon != null
                        ? Icon(
                            widget.prefixIcon,
                            color: hasError ? AppColors.error : AppColors.textSecondary,
                            size: 22,
                          )
                        : null,
                    suffixIcon: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: hasError ? AppColors.error : AppColors.textSecondary,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        /// ERROR TEXT
        if (hasError) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 14,
                  color: AppColors.error,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.errorText ?? "Please select ${widget.title}",
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.error,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _BottomSheetContent<T> extends StatefulWidget {
  final List<T> items;
  final String Function(T) itemLabel;
  final T? selectedItem;
  final String title;
  final void Function(T) onSelected;
  final VoidCallback onClear;

  const _BottomSheetContent({
    required this.items,
    required this.itemLabel,
    required this.onSelected,
    required this.onClear,
    this.selectedItem,
    required this.title,
  });

  @override
  State<_BottomSheetContent<T>> createState() =>
      _BottomSheetContentState<T>();
}

class _BottomSheetContentState<T>
    extends State<_BottomSheetContent<T>> {
  late List<T> filteredItems;
  final TextEditingController searchController =
  TextEditingController();

  bool get _showSearch => widget.items.length >= 5;

  @override
  void initState() {
    super.initState();
    filteredItems = widget.items;
    searchController.addListener(_filter);
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  void _filter() {
    final q = searchController.text.toLowerCase();
    setState(() {
      filteredItems = widget.items
          .where((e) =>
          widget.itemLabel(e).toLowerCase().contains(q))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// TITLE
            Text(
              widget.title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),

            const SizedBox(height: 12),

            /// SELECTED CHIP
            if (widget.selectedItem != null)
              Wrap(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.primary,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget
                              .itemLabel(widget.selectedItem!),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: widget.onClear,
                          child: const Icon(
                            Icons.close,
                            size: 16,
                            color: AppColors.primary,
                          ),
                        )
                      ],
                    ),
                  ),
                ],
              ),

             const SizedBox(height: 12),

             /// SEARCH
             if (_showSearch) ...[
               TextField(
                 controller: searchController,
                 autofocus: false,
                 textInputAction: TextInputAction.search,
                 decoration: InputDecoration(
                   hintText: "Search...",
                   prefixIcon: const Icon(Icons.search),
                   enabledBorder: OutlineInputBorder(
                     borderRadius: BorderRadius.circular(30),
                     borderSide: BorderSide(color: AppColors.border, width: 1),
                   ),
                   focusedBorder: OutlineInputBorder(
                     borderRadius: BorderRadius.circular(30),
                     borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                   ),
                   contentPadding:
                   const EdgeInsets.symmetric(
                       horizontal: 20, vertical: 10),
                 ),
               ),

               const SizedBox(height: 16),
             ],

             /// LIST
             Expanded(
               child: ListView.builder(
                itemCount: filteredItems.length,
                itemBuilder: (_, index) {
                  final item = filteredItems[index];
                  return ListTile(
                    title:
                    Text(widget.itemLabel(item)),
                    onTap: () =>
                        widget.onSelected(item),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
