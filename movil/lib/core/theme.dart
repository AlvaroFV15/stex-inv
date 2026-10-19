import 'package:flutter/material.dart';

/// Colores tomados del mockup y de la guía de planta (alto contraste).
class Colores {
  Colores._();

  static const cabecera = Color(0xFF0F172A); // barra superior azul noche
  static const marca = Color(0xFFEA580C); // logo naranja
  static const primario = Color(0xFF2563EB); // botones azules
  static const primarioSuave = Color(0xFFE8EFFD); // fondo del ícono del libro
  static const fondo = Color(0xFFF4F6F8);
  static const tarjeta = Colors.white;
  static const borde = Color(0xFFE2E8F0);
  static const texto = Color(0xFF0F172A);
  static const textoSuave = Color(0xFF64748B);
  static const exito = Color(0xFF2E7D32);
  static const alerta = Color(0xFFF57C00);
  static const error = Color(0xFFD32F2F);
}

ThemeData construirTema() {
  final esquema = ColorScheme.fromSeed(
    seedColor: Colores.primario,
    primary: Colores.primario,
    error: Colores.error,
    surface: Colores.tarjeta,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: esquema,
    scaffoldBackgroundColor: Colores.fondo,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colores.cabecera,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colores.borde),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colores.borde),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colores.primario, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
  );
}

/// Caja blanca con borde fino, como las tarjetas del mockup.
BoxDecoration decoracionTarjeta() => BoxDecoration(
      color: Colores.tarjeta,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colores.borde),
    );
