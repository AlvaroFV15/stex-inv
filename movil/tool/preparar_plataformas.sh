#!/usr/bin/env bash
# ---------------------------------------------------------------------
# Genera android/ e ios/ (si no existen) y aplica los ajustes que la app
# necesita. Es idempotente: se puede correr varias veces.
#   - INTERNET en el manifest principal (la plantilla solo lo pone en debug)
#   - Tráfico http permitido SOLO en debug/profile (servidor local Docker)
#   - minSdk 23 como mínimo (SQLCipher + flutter_secure_storage)
#   - Reglas de R8 para SQLCipher en release
#   - iOS 13 como mínimo
# Uso:  bash tool/preparar_plataformas.sh   (Linux, macOS o Git Bash en Windows)
# ---------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d android ] || [ ! -d ios ]; then
  flutter create . --org com.apjltextil --project-name stex_inv_movil --platforms android,ios
  # flutter create agrega un test de ejemplo que no aplica a esta app.
  rm -f test/widget_test.dart
fi

MAIN=android/app/src/main/AndroidManifest.xml
if ! grep -q 'android.permission.INTERNET' "$MAIN"; then
  perl -0pi -e 's#(<manifest xmlns:android="http://schemas.android.com/apk/res/android">)#$1\n    <uses-permission android:name="android.permission.INTERNET"/>#' "$MAIN"
fi
grep -q 'android.permission.INTERNET' "$MAIN" || { echo "No se pudo agregar INTERNET a $MAIN" >&2; exit 1; }

for variante in debug profile; do
  mkdir -p "android/app/src/$variante"
  cat > "android/app/src/$variante/AndroidManifest.xml" <<'XML'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Solo debug/profile: permite http para el servidor local de Docker. -->
    <uses-permission android:name="android.permission.INTERNET"/>
    <application android:usesCleartextTraffic="true"/>
</manifest>
XML
done

for gradle in android/app/build.gradle.kts android/app/build.gradle; do
  [ -f "$gradle" ] || continue
  # Al menos 23, sin bajar el mínimo que ya exija Flutter.
  perl -pi -e 's/minSdk = flutter\.minSdkVersion\b/minSdk = maxOf(flutter.minSdkVersion, 23)/; s/minSdkVersion flutter\.minSdkVersion\b/minSdkVersion Math.max(flutter.minSdkVersion, 23)/' "$gradle"
  grep -Eq 'minSdk(Version)? *=? *(maxOf\(flutter\.minSdkVersion, 23\)|Math\.max\(flutter\.minSdkVersion, 23\)|2[3-9]|3[0-9])' "$gradle" || {
    echo "Revisa minSdk en $gradle (debe ser 23 o más)" >&2; exit 1; }
done

cat > android/app/proguard-rules.pro <<'PRO'
# SQLCipher usa JNI: R8 no debe renombrar ni quitar estas clases.
-keep class net.zetetic.** { *; }
-keep class net.sqlcipher.** { *; }
PRO

if [ -f ios/Podfile ]; then
  perl -pi -e "s/^# *platform :ios, '[0-9.]+'/platform :ios, '13.0'/" ios/Podfile
fi

echo "Plataformas listas."
