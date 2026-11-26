import 'dart:js_interop';

@JS('open')
external void _jsOpen(String url, String target);

String get updatePlatform => 'web';

bool get canInstallInApp => false;

Future<String> downloadUpdate(String url, String fileName,
    {required void Function(int received, int total) onProgress,
    required bool Function() isCancelled}) async {
  throw UnsupportedError('web 端不支持应用内安装');
}

Future<String> installUpdate(String path) async {
  throw UnsupportedError('web 端不支持应用内安装');
}

Future<void> openExternalUrl(String url) async {
  _jsOpen(url, '_blank');
}