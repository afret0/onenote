import 'dart:developer' as developer;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class SyntheticPaste {
  static const MethodChannel _channel =
      MethodChannel('onenote/synthetic_paste');

  static void install() {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'paste' && call.method != 'selectAll') {
        return;
      }
      final context =
          WidgetsBinding.instance.focusManager.primaryFocus?.context;
      if (context == null) {
        developer.log('skip, 合成按键无焦点节点, method: ${call.method}');
        return;
      }
      developer.log(
          'hit, 合成按键派发意图, method: ${call.method}, focus: ${context.widget.runtimeType}');
      if (call.method == 'paste') {
        Actions.maybeInvoke(
            context, const PasteTextIntent(SelectionChangedCause.keyboard));
        return;
      }
      Actions.maybeInvoke(
          context, const SelectAllTextIntent(SelectionChangedCause.keyboard));
    });
  }
}
