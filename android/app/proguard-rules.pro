# R8 rules for the release build. Flutter and the plugins ship their own
# consumer rules; this file only adds what they do not cover.

# Keep line numbers for Crashlytics (the mapping file restores the names).
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# Flutter's deferred components reference Play Core classes that the app
# does not include.
-dontwarn com.google.android.play.core.**
