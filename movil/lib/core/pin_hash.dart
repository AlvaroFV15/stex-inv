import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Hash del PIN tal como lo calcula el servidor en /api/sync/download:
/// sha256("<operario_id>:<pin>") en hexadecimal.
///
/// Un PIN de 4 dígitos solo tiene 10 000 combinaciones, así que el hash
/// evita que el PIN quede legible, pero la protección real de estos datos
/// es el cifrado de la base local (SQLCipher) más el bloqueo por intentos.
String hashPin(String operarioId, String pin) =>
    sha256.convert(utf8.encode('$operarioId:$pin')).toString();
