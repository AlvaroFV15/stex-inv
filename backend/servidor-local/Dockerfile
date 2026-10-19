# Contexto de build: carpeta backend/ (incluye parche-panel/lib/sync,
# que es el mismo código de negocio que usa el panel en producción).
ARG NODE_IMAGE=node:22-alpine

FROM ${NODE_IMAGE} AS build
WORKDIR /app/servidor-local
COPY servidor-local/package.json servidor-local/package-lock.json ./
RUN npm ci
COPY servidor-local/tsconfig.json ./
COPY servidor-local/src ./src
COPY servidor-local/test ./test
COPY parche-panel/lib/sync /app/parche-panel/lib/sync
RUN npm run build && mkdir -p reportes

# Imagen para correr las pruebas (necesita la base de datos levantada).
FROM build AS test
ENV NODE_ENV=test
CMD ["sh", "-c", "npm run test:unit && npm run test:integracion"]
# Los reportes JUnit quedan en /app/servidor-local/reportes

# Imagen del servidor.
FROM ${NODE_IMAGE} AS runtime
WORKDIR /app/servidor-local
ENV NODE_ENV=production
COPY servidor-local/package.json servidor-local/package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY --from=build /app/servidor-local/dist ./dist
USER node
EXPOSE 8080
HEALTHCHECK --interval=5s --timeout=3s --start-period=5s --retries=10 \
  CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||8080)+'/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node", "dist/servidor-local/src/main.js"]
