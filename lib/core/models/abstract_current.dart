import 'package:flutter/material.dart';
import 'package:overmorrow/core/core.dart';

abstract class AbstractCurrent {
  final String text;
  final int temp;
  final int humidity;
  final int feels_like;
  final int uv;
  final double precip;

  final int wind;
  final int wind_dir;

  final ImageService imageService;

  final ColorScheme palette;
  final Color colorPop;
  final Color descColor;

  const AbstractCurrent({
    required this.text,
    required this.temp,
    required this.humidity,
    required this.feels_like,
    required this.uv,
    required this.precip,
    required this.wind,
    required this.wind_dir,
    required this.imageService,
    required this.palette,
    required this.colorPop,
    required this.descColor,
  });
}
