import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Firebase configuration options for BetterME
/// Được tạo từ Firebase Console
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDSSoCsZk2PwUx63SbpwViwDirF8TSH3oY',
    appId: '1:511578303045:android:4a532d2a939be5ceb8912c',
    messagingSenderId: '511578303045',
    projectId: 'betterme-18411',
    storageBucket: 'betterme-18411.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyClgVRhO0HOX1l9yOSQbWBL11ypbQO3Q1Q',
    appId: '1:511578303045:ios:b9764b655944374eb8912c',
    messagingSenderId: '511578303045',
    projectId: 'betterme-18411',
    storageBucket: 'betterme-18411.firebasestorage.app',
    iosBundleId: 'com.betterme.betterme',
    iosClientId: '511578303045-4r2o6iv6f6udmlpcfbjrrh78k5susbrg.apps.googleusercontent.com',
    androidClientId: '511578303045-equhps42mls4j01f01v9679rgkkf9d7i.apps.googleusercontent.com',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'YOUR-API-KEY',
    appId: 'YOUR-APP-ID',
    messagingSenderId: 'YOUR-SENDER-ID',
    projectId: 'YOUR-PROJECT-ID',
    authDomain: 'YOUR-AUTH-DOMAIN',
    storageBucket: 'YOUR-STORAGE-BUCKET',
  );
}
