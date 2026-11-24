# Flutter plugins are registered by generated code. Firebase and OkHttp do not
# need broad keep rules, but Firebase Auth's task callbacks are reached from
# Android framework entry points in the accessibility-service process.
-keep class com.google.firebase.auth.** { *; }
-keep class com.google.android.gms.tasks.** { *; }
