# ---------------------------------------------------------------------
# App móvil STEX-INV (Flutter).
#
#   Pruebas (las usa docker compose):  target "base" + tool/ci.sh
#   APK para instalar:
#     docker build --target apk --output type=local,dest=dist .
#     → dist/stex-inv-debug.apk  (apunta al servidor local 10.0.2.2:8080)
#
# Cambia la versión de Flutter con --build-arg FLUTTER_VERSION=x.y.z
# ---------------------------------------------------------------------
ARG FLUTTER_VERSION=3.44.9
ARG FLUTTER_IMAGE=ghcr.io/cirruslabs/flutter:${FLUTTER_VERSION}

FROM ${FLUTTER_IMAGE} AS base
# SQLite nativo: las pruebas usan una base real (sqflite_common_ffi) en la PC.
RUN apt-get update \
 && apt-get install -y --no-install-recommends libsqlite3-dev curl \
 && rm -rf /var/lib/apt/lists/*
ENV CI=true
WORKDIR /app
# Dependencias primero para aprovechar la caché de Docker.
COPY pubspec.yaml pubspec.lock* ./
RUN flutter pub get
COPY . .
RUN flutter pub get
CMD ["bash", "tool/ci.sh", "unit"]

FROM base AS build-apk
ARG MODO=debug
ARG SUPABASE_URL=http://10.0.2.2:8080
ARG SUPABASE_ANON_KEY=local-anon-key
ARG API_BASE_URL=http://10.0.2.2:8080
RUN bash tool/preparar_plataformas.sh \
 && flutter build apk --${MODO} \
      --dart-define=SUPABASE_URL=${SUPABASE_URL} \
      --dart-define=SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY} \
      --dart-define=API_BASE_URL=${API_BASE_URL} \
 && mkdir -p /out \
 && cp build/app/outputs/flutter-apk/app-${MODO}.apk /out/stex-inv-${MODO}.apk

FROM scratch AS apk
COPY --from=build-apk /out/ /
