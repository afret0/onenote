import 'dart:developer' as developer;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class SyntheticPaste {
  static const MethodChannel _channel =
      MethodChannel('onenote/synthetic_paste');

  static void install() {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'paste') {
        return;
      }
      final context =
          WidgetsBinding.instance.focusManager.primaryFocus?.context;
      if (context == null) {
        developer.log('skip, 合成粘贴无焦点节点');
        return;
      }
      developer.log(
          'hit, 合成粘贴派发 PasteTextIntent, focus: ${context.widget.runtimeType}');
      Actions.maybeInvoke(
          context, const PasteTextIntent(SelectionChangedCause.keyboard));
    });
  }
}
