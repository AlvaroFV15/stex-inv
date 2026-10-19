import { createHash } from "node:crypto";

/**
 * Hash del PIN que viaja a la tablet: sha256("<operario_id>:<pin>") en hex.
 * Debe coincidir con `movil/lib/core/pin_hash.dart`.
 */
export function hashPin(operarioId: string, pin: string): string {
  return createHash("sha256").update(`${operarioId}:${pin}`).digest("hex");
}
