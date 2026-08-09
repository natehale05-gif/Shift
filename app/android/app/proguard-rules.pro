# Flutter's engine is reached through JNI, so the shrinker cannot see the
# references and removes classes the app needs at runtime.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
