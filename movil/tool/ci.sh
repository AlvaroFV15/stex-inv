#!/usr/bin/env bash
# ---------------------------------------------------------------------
# Pruebas de la app. Lo usan Docker, el CI y tú en tu PC.
#   bash tool/ci.sh analizar     → flutter analyze
#   bash tool/ci.sh unit         → analyze + unitarias + widgets (con cobertura)
#   bash tool/ci.sh integracion  → contra el servidor local (STEX_API_URL)
# ---------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p reportes

modo="${1:-unit}"

analizar() {
  # Las sugerencias de estilo (info) no rompen el build; advertencias y errores sí.
  flutter analyze --no-fatal-infos
}

case "$modo" in
  analizar)
    analizar
    ;;
  unit)
    analizar
    flutter test --exclude-tags integration --coverage --reporter expanded \
      --file-reporter "json:reportes/flutter-unit.json"
    cp coverage/lcov.info reportes/lcov-movil.info 2>/dev/null || true
    ;;
  integracion)
    : "${STEX_API_URL:?Define STEX_API_URL (ej. http://localhost:8080)}"
    echo "Esperando a ${STEX_API_URL}/health …"
    for _ in $(seq 1 60); do
      curl -fsS "${STEX_API_URL}/health" >/dev/null 2>&1 && break
      sleep 1
    done
    curl -fsS "${STEX_API_URL}/health" >/dev/null
    flutter test --tags integration --reporter expanded \
      --file-reporter "json:reportes/flutter-integracion.json"
    ;;
  *)
    echo "Modo desconocido: $modo (usa analizar | unit | integracion)" >&2
    exit 2
    ;;
esac
