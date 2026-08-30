// VM-level code push, platform-split.
//
// dart:io and the staging directory only exist off the web; importing them
// unconditionally made the entire package uncompilable for Flutter Web
// through koolbase.dart -> patch_client.dart.
export 'patch_client_io.dart'
    if (dart.library.js_interop) 'patch_client_web.dart';
