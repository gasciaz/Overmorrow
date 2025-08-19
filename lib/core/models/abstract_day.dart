import 'package:flutter/material.dart';
import 'package:overmorrow/core/core.dart';

abstract class AbstractDay {
  final String text;
  final IconData icon;
  final String name;
  final int minTemp;
  final int maxTemp;
  final double rawMinTemp; //the unconverted numbers used for charts
  final double rawMaxTemp;
  final List<AbstractHour> hourly;
  final List<AbstractHour> hourly_for_precip;
  final int precip_prob;
  final double total_precip;
  final int windspeed;
  final int wind_dir;
  final double mm_precip;
  final int uv;

  const AbstractDay({
    required this.text,
    required this.icon,
    required this.name,
    required this.minTemp,
    required this.maxTemp,
    required this.rawMinTemp,
    required this.rawMaxTemp,
    required this.hourly,
    required this.hourly_for_precip,
    required this.precip_prob,
    required this.total_precip,
    required this.windspeed,
    required this.wind_dir,
    required this.mm_precip,
    required this.uv,
  });
}
