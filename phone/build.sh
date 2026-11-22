#!/usr/bin/env bash
# Builds the phone overlay app without Gradle: aapt2, javac, d8, apksigner.
# Needs the Android SDK (build-tools and a platform) and a JDK.
set -euo pipefail
cd "$(dirname "$0")/overlay"
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
BT="$(ls -d "$SDK"/build-tools/* | sort -V | tail -1)"
JAR="$(ls -d "$SDK"/platforms/android-* | sort -V | tail -1)/android.jar"
OUT=build
rm -rf "$OUT" && mkdir -p "$OUT/classes" "$OUT/gen"
"$BT/aapt2" compile --dir res -o "$OUT/res.zip"
"$BT/aapt2" link -I "$JAR" --manifest AndroidManifest.xml --java "$OUT/gen" \
    --min-sdk-version 26 --target-sdk-version 34 -o "$OUT/base.apk" "$OUT/res.zip"
javac --release 11 -nowarn -classpath "$JAR" -d "$OUT/classes" \
    $(find src "$OUT/gen" -name '*.java')
"$BT/d8" --min-api 26 --lib "$JAR" --output "$OUT" $(find "$OUT/classes" -name '*.class')
cp "$OUT/base.apk" "$OUT/unsigned.apk"
(cd "$OUT" && zip -qj unsigned.apk classes.dex)
"$BT/zipalign" -f 4 "$OUT/unsigned.apk" "$OUT/aligned.apk"
"$BT/apksigner" sign --ks keystore.jks --ks-pass pass:sudoclaude \
    --out ../sudoclaude-phone.apk "$OUT/aligned.apk"
rm -f ../sudoclaude-phone.apk.idsig
echo "built phone/sudoclaude-phone.apk"
