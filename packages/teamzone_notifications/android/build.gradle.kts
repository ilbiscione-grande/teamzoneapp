group = "se.teamzone.notifications"
version = "1.0"

plugins {
    id("com.android.library")
}

android {
    namespace = "se.teamzone.notifications"

    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        minSdk = 24
    }
}
