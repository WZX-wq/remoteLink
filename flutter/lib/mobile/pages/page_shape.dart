import 'package:flutter/material.dart';

abstract class PageShape extends Widget {
  const PageShape({super.key});

  String get title;
  Widget get icon;
  List<Widget> get appBarActions;
}
