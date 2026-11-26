import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import '../data/password_lock.dart';
import '../lock/biometrics.dart';
import '../state/app_state.dart';
import '../state/lock_attempts.dart';
import 'dialogs.dart';
import 'theme.dart';
import 'widgets.dart';

Future<String?> promptPassword(
  BuildContext context, {
  required String title,
  String? subtitle,
  required LockAttempts attempts,
  required PasswordLock lock,
  String confirmLabel = '解锁',
  Future<bool> Function()? onBiometric,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _PasswordDialog(
      title: title,
      subtitle: subtitle,
      confirmLabel: confirmLabel,
      lock: lock,
      onSubmit: (password) => attempts.verify(lock, password),
      cooldownOf: attempts.cooldownRemainingMs,
      onBiometric: onBiometric,
    ),
  );
}

Future<String?> promptNewPassword(
  BuildContext context, {
  required String title,
  String? subtitle,
  String confirmLabel = '确定',
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _NewPasswordDialog(
      title: title,
      subtitle: subtitle,
      confirmLabel: confirmLabel,
    ),
  );
}

class _PasswordField extends StatefulWidget {
  const _PasswordField({
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.obscure,
    required this.onToggle,
    this.autofocus = false,
    this.onSubmitted,
    this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final bool obscure;
  final VoidCallback onToggle;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _empty = true;

  @override
  void initState() {
    super.initState();
    _empty = widget.controller.text.isEmpty;
    widget.controller.addListener(_syncEmpty);
  }

  @override
  void didUpdateWidget(_PasswordField oldWidget) {
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
      obscureText: widget.obscure,
      enableSuggestions: false,
      autocorrect: false,
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

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({
    required this.title,
    required this.subtitle,
    required this.confirmLabel,
    required this.lock,
    required this.onSubmit,
    required this.cooldownOf,
    this.onBiometric,
  });

  final String title;
  final String? subtitle;
  final String confirmLabel;
  final PasswordLock lock;
  final Future<LockVerifyResult> Function(String password) onSubmit;
  final Future<int> Function() cooldownOf;
  final Future<bool> Function()? onBiometric;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _obscure = true;
  bool _busy = false;
  bool _bioAvailable = false;
  String? _error;
  int _cooldownMs = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _refreshCooldown();
    _probeBio();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _refreshCooldown() async {
    final remaining = await widget.cooldownOf();
    if (!mounted) {
      return;
    }
    if (remaining > 0) {
      _startCooldown(remaining);
    }
  }

  Future<void> _probeBio() async {
    if (widget.onBiometric == null) {
      return;
    }
    final available = await Biometrics.available();
    final autoBio = available && await Biometrics.hasEnrolledBiometrics();
    if (!mounted) {
      return;
    }
    setState(() => _bioAvailable = available);
    developer.log(
        'done, 解锁弹窗生物识别就绪, available: $available, autoBio: $autoBio');
    if (autoBio) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          developer.log('hit, 已录入生物识别自动弹出认证');
          _bioUnlock();
        }
      });
    }
  }

  Future<void> _bioUnlock() async {
    if (_busy || widget.onBiometric == null) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await widget.onBiometric!();
    if (!mounted) {
      return;
    }
    if (ok) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _error = '生物识别未通过，请输入密码';
    });
    _focus.requestFocus();
  }

  void _startCooldown(int ms) {
    setState(() {
      _cooldownMs = ms;
      _error = null;
    });
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _cooldownMs -= 1000;
        if (_cooldownMs <= 0) {
          _cooldownMs = 0;
          timer.cancel();
          _focus.requestFocus();
        }
      });
    });
  }

  void _autoSubmit(String value) {
    if (_busy || _cooldownMs > 0 || value.isEmpty) {
      return;
    }
    if (widget.lock.len != value.length) {
      return;
    }
    if (widget.lock.verify(value)) {
      developer.log('hit, 弹窗静默校验通过自动提交, len: ${value.length}');
      _submit();
      return;
    }
    developer.log('skip, 长度达标静默校验未通过, len: ${value.length}');
  }

  Future<void> _submit() async {
    if (_busy || _cooldownMs > 0) {
      return;
    }
    final password = _controller.text;
    if (password.isEmpty) {
      setState(() => _error = '请输入密码');
      _focus.requestFocus();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await widget.onSubmit(password);
    if (!mounted) {
      return;
    }
    if (result.ok) {
      Navigator.of(context).pop(password);
      return;
    }
    setState(() {
      _busy = false;
      _error = result.cooldownMs > 0 ? null : '密码错误，请重试';
    });
    if (result.cooldownMs > 0) {
      _startCooldown(result.cooldownMs);
    } else {
      _controller.clear();
      _focus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = inkOf(context);
    final cooling = _cooldownMs > 0;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.subtitle != null) ...[
              Text(widget.subtitle!,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: t.inkMuted)),
              const SizedBox(height: spaceMd),
            ],
            _PasswordField(
              controller: _controller,
              focusNode: _focus,
              label: '密码',
              obscure: _obscure,
              autofocus: true,
              onToggle: () => setState(() => _obscure = !_obscure),
              onSubmitted: (_) => _submit(),
              onChanged: _autoSubmit,
            ),
            if (cooling) ...[
              const SizedBox(height: spaceSm),
              Text(
                '错误次数过多，请 ${(_cooldownMs / 1000).ceil()} 秒后重试',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: t.danger),
              ),
            ] else if (_error != null) ...[
              const SizedBox(height: spaceSm),
              Text(_error!,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: t.danger)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消')),
        if (_bioAvailable)
          TextButton.icon(
            onPressed: _busy ? null : _bioUnlock,
            style: TextButton.styleFrom(
              foregroundColor: t.accentText,
              minimumSize: const Size(0, 44),
            ).copyWith(
              mouseCursor:
                  const WidgetStatePropertyAll(SystemMouseCursors.click),
            ),
            icon: const Icon(Icons.fingerprint, size: 20),
            label: const Text('生物识别解锁'),
          ),
        FilledButton(
          onPressed: _busy || cooling ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

class _NewPasswordDialog extends StatefulWidget {
  const _NewPasswordDialog({
    required this.title,
    required this.subtitle,
    required this.confirmLabel,
  });

  final String title;
  final String? subtitle;
  final String confirmLabel;

  @override
  State<_NewPasswordDialog> createState() => _NewPasswordDialogState();
}

class _NewPasswordDialogState extends State<_NewPasswordDialog> {
  final _first = TextEditingController();
  final _second = TextEditingController();
  final _firstFocus = FocusNode();
  final _secondFocus = FocusNode();
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    _firstFocus.dispose();
    _secondFocus.dispose();
    super.dispose();
  }

  void _submit() {
    final password = _first.text;
    if (password.isEmpty) {
      setState(() => _error = '请输入密码');
      return;
    }
    if (password != _second.text) {
      setState(() => _error = '两次输入的密码不一致');
      return;
    }
    Navigator.of(context).pop(password);
  }

  @override
  Widget build(BuildContext context) {
    final t = inkOf(context);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.subtitle != null) ...[
              Text(widget.subtitle!,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: t.inkMuted)),
              const SizedBox(height: spaceMd),
            ],
            _PasswordField(
              controller: _first,
              focusNode: _firstFocus,
              label: '新密码',
              obscure: _obscure,
              autofocus: true,
              onToggle: () => setState(() => _obscure = !_obscure),
            ),
            const SizedBox(height: spaceMd),
            _PasswordField(
              controller: _second,
              focusNode: _secondFocus,
              label: '确认新密码',
              obscure: _obscure,
              onToggle: () => setState(() => _obscure = !_obscure),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: spaceSm),
              Text(_error!,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: t.danger)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消')),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}

Future<bool> unlockNotebookDialog(
    BuildContext context, AppState state, String notebookId) async {
  final lock = state.notebookLock(notebookId);
  if (state.systemLockTrusted || lock == null || !lock.active) {
    return true;
  }
  final name = state.notebookName(notebookId);
  var bioUnlocked = false;
  final password = await promptPassword(
    context,
    title: '解锁笔记本',
    subtitle: '「$name」已上锁，验证通过后本次会话内免密',
    attempts: state.attempts,
    lock: lock,
    onBiometric: state.lockBio
        ? () async {
            final ok = await Biometrics.authenticate('解锁笔记本');
            if (ok) {
              await state.attempts.succeed();
              bioUnlocked = true;
            }
            return ok;
          }
        : null,
  );
  if (bioUnlocked) {
    state.grantNotebookUnlock(notebookId);
    return true;
  }
  if (password == null) {
    return false;
  }
  state.grantNotebookUnlock(notebookId);
  return true;
}

Future<bool> unlockNoteDialog(
    BuildContext context, AppState state, String noteId) async {
  final note = state.noteById(noteId);
  if (note == null) {
    return false;
  }
  if (state.isNotebookLocked(note.notebookId)) {
    final ok = await unlockNotebookDialog(context, state, note.notebookId);
    if (!ok || !context.mounted) {
      return false;
    }
  }
  final lock = state.noteLock(noteId);
  if (state.systemLockTrusted || lock == null || !lock.active) {
    return true;
  }
  var bioUnlocked = false;
  final password = await promptPassword(
    context,
    title: '解锁笔记',
    subtitle: '「${noteDisplayTitle(note)}」已上锁，验证通过后本次会话内免密',
    attempts: state.attempts,
    lock: lock,
    onBiometric: state.lockBio
        ? () async {
            final ok = await Biometrics.authenticate('解锁笔记');
            if (ok) {
              await state.attempts.succeed();
              bioUnlocked = true;
            }
            return ok;
          }
        : null,
  );
  if (bioUnlocked) {
    state.grantNoteUnlock(noteId);
    return true;
  }
  if (password == null) {
    return false;
  }
  state.grantNoteUnlock(noteId);
  return true;
}

Future<void> setNotebookPasswordFlow(
    BuildContext context, AppState state, String notebookId) async {
  final existing = state.notebookLock(notebookId);
  if (existing != null && existing.active) {
    final current = await promptPassword(
      context,
      title: '验证当前密码',
      subtitle: '修改笔记本密码前先验证',
      attempts: state.attempts,
      lock: existing,
      confirmLabel: '验证',
    );
    if (current == null) {
      return;
    }
  }
  if (!context.mounted) {
    return;
  }
  final password = await promptNewPassword(context,
      title: existing != null && existing.active ? '修改笔记本密码' : '设置笔记本密码',
      subtitle: '密码随同步生效，其它设备打开该笔记本也需要输入');
  if (password != null) {
    await state.setNotebookPassword(notebookId, password);
  }
}

Future<void> removeNotebookPasswordFlow(
    BuildContext context, AppState state, String notebookId) async {
  final existing = state.notebookLock(notebookId);
  if (existing == null || !existing.active) {
    return;
  }
  final current = await promptPassword(
    context,
    title: '移除笔记本密码',
    subtitle: '先验证当前密码',
    attempts: state.attempts,
    lock: existing,
    confirmLabel: '验证',
  );
  if (current == null || !context.mounted) {
    return;
  }
  final ok = await confirm(context,
      title: '移除笔记本密码',
      message: '移除后所有设备打开该笔记本都不再需要密码。',
      confirmLabel: '移除');
  if (ok) {
    await state.removeNotebookPassword(notebookId);
  }
}

Future<void> setNotePasswordFlow(
    BuildContext context, AppState state, String noteId) async {
  final existing = state.noteLock(noteId);
  if (existing != null && existing.active) {
    final current = await promptPassword(
      context,
      title: '验证当前密码',
      subtitle: '修改笔记密码前先验证',
      attempts: state.attempts,
      lock: existing,
      confirmLabel: '验证',
    );
    if (current == null) {
      return;
    }
  }
  if (!context.mounted) {
    return;
  }
  final password = await promptNewPassword(context,
      title: existing != null && existing.active ? '修改笔记密码' : '设置笔记密码',
      subtitle: '密码随同步生效，其它设备打开该笔记也需要输入');
  if (password != null) {
    await state.setNotePassword(noteId, password);
  }
}

Future<void> removeNotePasswordFlow(
    BuildContext context, AppState state, String noteId) async {
  final existing = state.noteLock(noteId);
  if (existing == null || !existing.active) {
    return;
  }
  final current = await promptPassword(
    context,
    title: '移除笔记密码',
    subtitle: '先验证当前密码',
    attempts: state.attempts,
    lock: existing,
    confirmLabel: '验证',
  );
  if (current == null || !context.mounted) {
    return;
  }
  final ok = await confirm(context,
      title: '移除笔记密码',
      message: '移除后所有设备打开该笔记都不再需要密码。',
      confirmLabel: '移除');
  if (ok) {
    await state.removeNotePassword(noteId);
  }
}