# STEX-INV · atajos. En Windows sin make, copia el comando de cada regla.
COMPOSE := docker compose

.PHONY: help up down logs test test-servidor test-movil test-integracion apk apk-release limpiar

help:
	@echo "make up                → base de datos + API local (http://localhost:8080)"
	@echo "make test              → TODAS las pruebas (servidor, app, integración)"
	@echo "make test-servidor     → unitarias + integración del servidor"
	@echo "make test-movil        → flutter analyze + unitarias + widgets"
	@echo "make test-integracion  → app (Dart) contra el servidor en Docker"
	@echo "make apk               → APK debug que apunta al servidor local (dist/)"
	@echo "make apk-release URL=https://tu-panel SUPABASE_URL=... ANON_KEY=..."
	@echo "make down / limpiar    → apagar / apagar y borrar datos y reportes"

up:
	$(COMPOSE) up -d --build --wait db api
	@echo "API lista en http://localhost:$${API_PORT:-8080}"

down:
	$(COMPOSE) down

logs:
	$(COMPOSE) logs -f api

test: test-servidor test-movil test-integracion
	@echo "Todas las pruebas pasaron. Reportes en ./reportes"

test-servidor: up
	$(COMPOSE) --profile test run --rm --build api-tests

test-movil:
	$(COMPOSE) --profile test run --rm --build movil-test

test-integracion: up
	$(COMPOSE) --profile test run --rm --build movil-integracion

apk:
	docker build --target apk --output type=local,dest=dist movil
	@echo "APK en dist/stex-inv-debug.apk"

apk-release:
	docker build --target apk --output type=local,dest=dist \
	  --build-arg MODO=release \
	  --build-arg API_BASE_URL=$(URL) \
	  --build-arg SUPABASE_URL=$(SUPABASE_URL) \
	  --build-arg SUPABASE_ANON_KEY=$(ANON_KEY) \
	  movil

limpiar:
	$(COMPOSE) --profile test down -v --remove-orphans
	rm -rf reportes dist
