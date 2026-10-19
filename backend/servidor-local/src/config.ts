export type Config = {
  puerto: number;
  databaseUrl: string;
  jwtSecreto: string;
  jwtExpiraSegundos: number;
  /** Si se define, las rutas /auth/v1 exigen la cabecera `apikey` (como Supabase). */
  anonKey: string | null;
};

export function leerConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const databaseUrl = env.DATABASE_URL;
  if (!databaseUrl) throw new Error("Falta la variable DATABASE_URL.");

  const jwtSecreto = env.JWT_SECRET ?? "";
  if (jwtSecreto.length < 32) {
    throw new Error("JWT_SECRET debe tener al menos 32 caracteres.");
  }

  return {
    puerto: Number(env.PORT ?? 8080),
    databaseUrl,
    jwtSecreto,
    jwtExpiraSegundos: Number(env.JWT_EXPIRA_SEGUNDOS ?? 3600),
    anonKey: env.ANON_KEY ? env.ANON_KEY : null,
  };
}
