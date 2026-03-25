# Add project specific ProGuard rules here.
# By default, the flags in this file are appended to flags specified
# in /sdk/tools/proguard/proguard-android.txt

# Keep Ktor and serialization classes
-keep class io.ktor.** { *; }
-keep class kotlinx.serialization.** { *; }

# Keep data classes
-keep class com.lispim.client.data.** { *; }
-keep class com.lispim.client.model.** { *; }
