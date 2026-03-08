## Flutter Local Notifications - giữ generic type signatures
-keep class com.dexterous.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken

## Keep generic signatures (R8 full mode strips these)
-keepattributes Signature
-keepattributes *Annotation*
