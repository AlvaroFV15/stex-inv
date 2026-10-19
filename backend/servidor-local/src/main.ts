import { Pool } from "pg";

import { leerConfig } from "./config";
import { crearServidor } from "./servidor";

const config = leerConfig();
const pool = new Pool({ connectionString: config.databaseUrl, max: 10 });
const servidor = crearServidor(pool, config);

servidor.listen(config.puerto, "0.0.0.0", () => {
  console.info(`STEX servidor local escuchando en :${config.puerto}`);
});

function cerrar(senal: string) {
  console.info(`${senal} recibido, cerrando…`);
  servidor.close(() => {
    pool.end().finally(() => process.exit(0));
  });
  setTimeout(() => process.exit(1), 10_000).unref();
}

process.on("SIGTERM", () => cerrar("SIGTERM"));
process.on("SIGINT", () => cerrar("SIGINT"));
