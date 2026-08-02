# Project-specific ProGuard/R8 rules.
# The default `proguard-android-optimize.txt` is applied first (see
# `proguardFiles` in app/build.gradle.kts), and the Flutter Gradle
# plugin also injects consumer rules from every plugin's
# consumer-rules.pro automatically, so this file only needs to cover
# things the defaults and plugin consumer rules don't know about.

# Keep our native bridge classes: the Dart side reaches them by
# fully-qualified name through MethodChannel/EventChannel, so R8 must
# not rename them or the method-channel lookups fail at runtime.
-keep class com.wakeywakey.app.AlarmService { *; }
-keep class com.wakeywakey.app.AlarmReceiver { *; }
-keep class com.wakeywakey.app.BootReceiver { *; }
-keep class com.wakeywakey.app.GeofenceTransitionReceiver { *; }
-keep class com.wakeywakey.app.RingingActivity { *; }

# Google Play Services Geofencing uses reflection to instantiate the
# TransitionPendingIntent receiver. Keep its public API surface.
-keep public class * extends android.content.BroadcastReceiver
-keep public class * extends android.app.Service
-keep public class * extends android.app.Activity
