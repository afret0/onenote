import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import 'theme.dart';

class MaskedPasswordController extends TextEditingController {
  bool _masked = true;

  set masked(bool value) {
    if (_masked == value) {
      return;
    }
    _masked = value;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (!_masked) {
      return super.buildTextSpan(
          context: context, style: style, withComposing: withComposing);
    }
    return TextSpan(text: '•' * text.length, style: style);
  }
}

class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.obscure,
    required this.onToggle,
    this.autofocus = false,
    this.customMask = false,
    this.onSubmitted,
    this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final bool obscure;
  final VoidCallback onToggle;
  final bool autofocus;

  // 自绘掩码模式：obscureText 恒 false（true 会触发 macOS 切 ABC 输入法），
  // 需搭配 MaskedPasswordController，掩码切换由调用方在 onToggle 里同步。
  final bool customMask;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _empty = true;

  @override
  void initState() {
    super.initState();
    _empty = widget.controller.text.isEmpty;
    widget.controller.addListener(_syncEmpty);
  }

  @override
  void didUpdateWidget(PasswordField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncEmpty);
      widget.controller.addListener(_syncEmpty);
      _syncEmpty();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncEmpty);
    super.dispose();
  }

  void _syncEmpty() {
    final empty = widget.controller.text.isEmpty;
    if (empty != _empty) {
      setState(() => _empty = empty);
    }
  }

  void _clear() {
    widget.controller.clear();
    widget.focusNode.requestFocus();
    developer.log('done, 密码框一键清空');
  }

  @override
  Widget build(BuildContext context) {
    final t = inkOf(context);
    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      obscureText: widget.customMask ? false : widget.obscure,
      enableSuggestions: false,
      autocorrect: false,
      enableInteractiveSelection: true,
      contextMenuBuilder: (context, editableTextState) {
        final items = editableTextState.contextMenuButtonItems
            .where((item) =>
                !widget.obscure ||
                (item.type != ContextMenuButtonType.copy &&
                    item.type != ContextMenuButtonType.cut))
            .toList();
        if (items.isEmpty) {
          return const SizedBox.shrink();
        }
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: editableTextState.contextMenuAnchors,
          buttonItems: items,
        );
      },
      decoration: InputDecoration(
        labelText: widget.label,
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _suffixButton(
              t,
              label: '清空密码',
              icon: Icons.clear,
              onPressed: _empty ? null : _clear,
            ),
            _suffixButton(
              t,
              label: widget.obscure ? '显示密码' : '隐藏密码',
              icon: widget.obscure
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              onPressed: widget.onToggle,
            ),
          ],
        ),
      ),
      onSubmitted: widget.onSubmitted,
      onChanged: widget.onChanged,
    );
  }

  Widget _suffixButton(
    InkTokens t, {
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        child: IconButton(
          onPressed: onPressed,
          style: const ButtonStyle(
            mouseCursor:
                WidgetStatePropertyAll(SystemMouseCursors.click),
          ),
          icon: Icon(icon, size: 20, color: onPressed == null ? null : t.inkMuted),
        ),
      ),
    );
  }
}