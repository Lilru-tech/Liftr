# Liftr (Android) — añade reglas al activar R8/ProGuard en release.
# Supabase / Ktor / serialización: seguir la documentación actual de supabase-kt.

# BuildConfig (URLs de Supabase, ids de anuncio inyectados desde local.properties)
-keepclassmembers class com.lilru.liftr.BuildConfig { *; }

# Google Mobile Ads (banners, UMP)
-keep class com.google.android.gms.ads.** { *; }
-dontwarn com.google.android.gms.ads.**

# Google Maps (compose + routes)
-keep class com.google.android.gms.maps.** { *; }
-dontwarn com.google.android.gms.maps.**
-keep class com.google.maps.android.**

# kotlinx-serialization (entidades @Serializable usadas con Postgrest)
-keepattributes *Annotation*, InnerClasses, EnclosingMethod
-dontnote kotlinx.serialization.**

# Modelos @Serializable (el patrón **$$serializer choca con R8: `$` es comodín en ProGuard)
-keep @kotlinx.serialization.Serializable class com.lilru.liftr.** { *; }

# ML Kit text recognition (nutrition label OCR)
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**
