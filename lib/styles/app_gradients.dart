import 'package:flutter/material.dart';

class GradientTheme {
  final String name;
  final Gradient gradient;
  final Color? primaryColor;
  final Color? secondaryColor;
  final Color? tertiaryColor;

  const GradientTheme({
    required this.name,
    required this.gradient,
    this.primaryColor = Colors.black,
    this.secondaryColor = Colors.white,
    this.tertiaryColor = Colors.blue,
  });
}

class AppGradients {
  static const List<GradientTheme> themes = [
    GradientTheme(
        name: "Royal Blue",
        gradient: LinearGradient(
          colors: [Color(0xFF6A11CB), Color(0xFF2575FC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        primaryColor: Colors.white,
        secondaryColor: Colors.black,
        tertiaryColor: Colors.blue),
    GradientTheme(
      name: "Sunset Flame",
      gradient: LinearGradient(
        colors: [Color(0xFFFF5F6D), Color(0xFFFFC371)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ),
    ),
    GradientTheme(
        name: "Ocean Sky",
        gradient: LinearGradient(
          colors: [Color(0xFF56CCF2), Color(0xFF2F80ED)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        primaryColor: Colors.white,
        secondaryColor: Colors.black,
        tertiaryColor: Colors.blue),
    GradientTheme(
        name: "Mint Breeze",
        gradient: LinearGradient(
          colors: [Color(0xFF00B09B), Color(0xFF96C93D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        primaryColor: Colors.white,
        secondaryColor: Colors.black,
        tertiaryColor: Colors.blue),
    GradientTheme(
        name: "Purple Dream",
        gradient: LinearGradient(
          colors: [Color(0xFFDA44BB), Color(0xFF8921AA)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        primaryColor: Colors.white,
        secondaryColor: Colors.black,
        tertiaryColor: Colors.blue),
  ];
}
