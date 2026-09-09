# Hisaab ships no reflection-driven code of its own, so the defaults do.
# These keep the plugins that do reach for reflection intact.
-keep class io.flutter.** { *; }
-keep class com.dexterous.** { *; }
-dontwarn io.flutter.embedding.**
