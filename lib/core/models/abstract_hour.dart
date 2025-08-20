import 'package:flutter/material.dart';

abstract class AbstractHour {
  final int temp;
  final IconData icon;
  final String time;
  final String text;
  final double precip;
  final int precip_prob;
  final double wind;
  final int wind_dir;
  final int wind_gusts;
  final int uv;
  final double raw_temp;
  final double raw_precip;
  final double raw_wind;
  final String rawText;

  const AbstractHour({
    required this.temp,
    required this.icon,
    required this.time,
    required this.text,
    required this.precip,
    required this.precip_prob,
    required this.wind,
    required this.wind_dir,
    required this.wind_gusts,
    required this.uv,
    required this.raw_temp,
    required this.raw_precip,
    required this.raw_wind,
    required this.rawText,
  });
}
