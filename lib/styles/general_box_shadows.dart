import 'package:flutter/material.dart';

class GeneralBoxShadows {
  static BoxShadow elevationBoxShadow = BoxShadow(
    color: Colors.black.withOpacity(0.15), // rgba(0, 0, 0, 0.15)
    offset: const Offset(0, 3), // x: 0px, y: 3px
    blurRadius: 4, // 4px blur radius
    spreadRadius: 0, // 0px spread radius
  );
}
