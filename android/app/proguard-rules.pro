# EduFlow ProGuard-Regeln (Paket 0).
# Retrofit/OkHttp/kotlinx-serialization brauchen keine Sonderregeln im
# Debug-Build; Release behält Serialisierungs-Metadaten.
-keepattributes Signature, InnerClasses, EnclosingMethod
-keepattributes RuntimeVisibleAnnotations, RuntimeVisibleParameterAnnotations
-keep class kotlinx.serialization.** { *; }
-keepclassmembers class ** {
    @kotlinx.serialization.Serializable <fields>;
}
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn retrofit2.**
