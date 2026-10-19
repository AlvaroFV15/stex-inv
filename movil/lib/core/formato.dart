String _dos(int n) => n.toString().padLeft(2, '0');

/// Fecha y hora local: 18/10/2026 19:43
String fechaHora(DateTime d) {
  final l = d.toLocal();
  return '${_dos(l.day)}/${_dos(l.month)}/${l.year} ${_dos(l.hour)}:${_dos(l.minute)}';
}

/// Solo hora local: 19:43
String hora(DateTime d) {
  final l = d.toLocal();
  return '${_dos(l.hour)}:${_dos(l.minute)}';
}

/// Peso con dos decimales: 112.75 kg
String kg(double v) => '${v.toStringAsFixed(2)} kg';

/// Marca de tiempo para guardar en SQLite y enviar al servidor (UTC, ISO 8601).
String ahoraIso() => DateTime.now().toUtc().toIso8601String();

/// Convierte el texto del campo de peso a número. Acepta coma o punto decimal.
double? parsePeso(String texto) =>
    double.tryParse(texto.trim().replaceAll(',', '.'));
