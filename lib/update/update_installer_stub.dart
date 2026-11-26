String get updatePlatform => 'unknown';

bool get canInstallInApp => false;

Future<String> downloadUpdate(String url, String fileName,
    {required void Function(int received, int total) onProgress,
    required bool Function() isCancelled}) async {
  throw UnsupportedError('当前平台不支持下载更新');
}

Future<String> installUpdate(String path) async {
  throw UnsupportedError('当前平台不支持应用内安装');
}

Future<void> openExternalUrl(String url) async {
  throw UnsupportedError('当前平台不支持打开链接');
}