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
        tertiaryColor: Color(0xFF6A11CB)),
    GradientTheme(
      name: "Sunset Flame",
      gradient: LinearGradient(
        colors: [Color(0xFFFF5F6D), Color(0xFFFFC371)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ),
      tertiaryColor: Color(0xFFFF5F6D),
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
        tertiaryColor: Color(0xFF56CCF2)),
    GradientTheme(
        name: "Mint Breeze",
        gradient: LinearGradient(
          colors: [Color(0xFF00B09B), Color(0xFF96C93D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        primaryColor: Colors.white,
        secondaryColor: Colors.black,
        tertiaryColor: Color(0xFF00B09B)),
    GradientTheme(
        name: "Deep Space",
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF434343), // #434343
            Color(0xFF000000), // #000000
          ],
        ),
        primaryColor: Colors.white,
        secondaryColor: Colors.black,
        tertiaryColor: Colors.black),
    GradientTheme(
        name: "Lawrencium",
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color(0xFF24243e), // #24243e
            Color(0xFF302b63), // #302b63
            Color(0xFF0f0c29), // #0f0c29
          ],
        ),
        primaryColor: Colors.white,
        secondaryColor: Colors.black,
        tertiaryColor: Color(0xFF302b63)),
    GradientTheme(
        name: "Flickr",
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF33001b), // #33001b
            Color(0xFFFF0084), // #ff0084
          ],
        ),
        primaryColor: Colors.white,
        secondaryColor: Colors.black,
        tertiaryColor: Color(0xFF33001b)),
    GradientTheme(
        name: 'Under the Lake',
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF237A57), // #237A57
            Color(0xFF093028), // #093028
          ],
        ),
        primaryColor: Colors.white,
        secondaryColor: Colors.black,
        tertiaryColor: Color(0xff093d28)),
    GradientTheme(
        name: 'Red Gradient',
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFdd1818), // #dd1818
            Color(0xFF333333), // #333333
          ],
        ),
        primaryColor: Colors.white,
        secondaryColor: Colors.black,
        tertiaryColor: Color(0xFFdd1818)),
    GradientTheme(
        name: 'Purple Gradient',
        gradient: LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: [
            Color(0xFF8e2de2), // #8e2de2
            Color(0xFF4a00e0), // #4a00e0
          ],
        ),
        primaryColor: Colors.white,
        secondaryColor: Colors.black,
        tertiaryColor: Color(0xFF8e2de2)),
  ];
}
