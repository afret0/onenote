export 'background_lock_stub.dart'
    if (dart.library.io) 'background_lock_io.dart'
    if (dart.library.js_interop) 'background_lock_web.dart';