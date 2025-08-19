/*
Copyright (C) <2025>  <Balint Maroti>

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.

*/

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:overmorrow/core/core.dart';
import 'package:overmorrow/weather_refact.dart';

String omConvertTime(String time) {
  return time.split('T')[1];
}

String omAqiDesc(int index, AppLocalizations localizations) {
  return [
    localizations.goodAqiDesc,
    localizations.fairAqiDesc,
    localizations.moderateAqiDesc,
    localizations.poorAqiDesc,
    localizations.veryPoorAqiDesc,
    localizations.unhealthyAqiDesc,
  ][index - 1];
}

String omAqiTitle(int index, AppLocalizations localizations) {
  return [
    localizations.good,
    localizations.fair,
    localizations.moderate,
    localizations.poor,
    localizations.veryPoor,
    localizations.unhealthy,
  ][index - 1];
}

List<double> omGetMaxMinTempForDaily(List<AbstractDay> days) {
  double minTemp = 100;
  var maxTemp = -100.0;
  for (var i = 0; i < days.length; i++) {
    if (days[i].rawMinTemp < minTemp) {
      minTemp = days[i].rawMinTemp;
    }
    if (days[i].rawMaxTemp > maxTemp) {
      maxTemp = days[i].rawMaxTemp;
    }
  }
  return [minTemp, maxTemp];
}

String OMamPmTime(String time) {
  final a = time.split('T')[1];
  final num = a.split(':');
  final hour = int.parse(num[0]);
  final minute = int.parse(num[1]);

  if (hour == 0) {
    return "0:${minute.toString().padLeft(2, "0")}am";
  }
  if (hour == 12) {
    return "12:${minute.toString().padLeft(2, "0")}pm";
  }

  if (hour > 12) {
    return "${hour - 12}:${minute.toString().padLeft(2, "0")}pm";
  }
  return "$hour:${minute.toString().padLeft(2, "0")}am";
}

int aqiIndexCorrection(int aqi) {
  if (aqi <= 20) {
    return 1;
  }
  if (aqi <= 40) {
    return 2;
  }
  if (aqi <= 60) {
    return 3;
  }
  if (aqi <= 80) {
    return 4;
  }
  if (aqi <= 100) {
    return 5;
  }
  return 6;
}

DateTime OMGetLocalTime(Map<String, dynamic> item) {
  final localTime = DateTime.now().toUtc().add(
    Duration(seconds: item['utc_offset_seconds'] as int),
  );
  return localTime;
}

double OMGetSunStatus(Map<String, dynamic> item) {
  final localtime = OMGetLocalTime(item);

  final splitted1 =
      item['daily']['sunrise'][0].split('T')[1].split(':') as List<String>;
  final sunrise = localtime.copyWith(
    hour: int.parse(splitted1[0]),
    minute: int.parse(splitted1[1]),
  );

  final splitted2 =
      item['daily']['sunset'][0].split('T')[1].split(':') as List<String>;
  final sunset = localtime.copyWith(
    hour: int.parse(splitted2[0]),
    minute: int.parse(splitted2[1]),
  );

  final total = sunset.difference(sunrise).inMinutes;
  final passed = localtime.difference(sunrise).inMinutes;

  return min(1, max(passed / total, 0));
}

Future<List<dynamic>> OMRequestData(
  double lat,
  double lng,
  String realLoc,
) async {
  final oMParams = {
    'latitude': lat.toString(),
    'longitude': lng.toString(),
    'minutely_15': ['precipitation'],
    'current': [
      'temperature_2m',
      'weather_code',
      'relative_humidity_2m',
      'apparent_temperature',
    ],
    'hourly': [
      'temperature_2m',
      'precipitation',
      'weather_code',
      'wind_speed_10m',
      'wind_direction_10m',
      'uv_index',
      'precipitation_probability',
      'wind_gusts_10m',
    ],
    'daily': [
      'weather_code',
      'temperature_2m_max',
      'temperature_2m_min',
      'uv_index_max',
      'precipitation_sum',
      'precipitation_probability_max',
      'wind_speed_10m_max',
      'wind_direction_10m_dominant',
      'sunrise',
      'sunset',
    ],
    'timezone': 'auto',
    'forecast_days': '14',
    'forecast_minutely_15': '24',
  };

  final oMUrl = Uri.https('api.open-meteo.com', 'v1/forecast', oMParams);

  //var oMFile = await cacheManager2.getSingleFile(oMUrl.toString(), key: "$real_loc, open-meteo").timeout(const Duration(seconds: 6));
  final oMFile = await XCustomCacheManager.fetchData(
    oMUrl.toString(),
    '$realLoc, open-meteo',
  );

  final oMResponse = await oMFile[0].readAsString();
  final OMData = jsonDecode(oMResponse as String);

  final fetchDatetime = (await oMFile[0].lastModified()) as DateTime;
  final isonline = oMFile[1] as bool;

  return [OMData, fetchDatetime, isonline];
}

String oMGetName(
  int index,
  Map<String, String> settings,
  Map<String, dynamic> item,
  dayDif,
  AppLocalizations localizations,
) {
  final x = item['daily']['time'][index].split('T')[0] as String;
  final z = x.split('-');
  final time = DateTime(int.parse(z[0]), int.parse(z[1]), int.parse(z[2]));
  final weeks = <String>[
    localizations.mon,
    localizations.tue,
    localizations.wed,
    localizations.thu,
    localizations.fri,
    localizations.sat,
    localizations.sun,
  ];
  final weekname = weeks[time.weekday - 1];
  final date = settings['Date format'] == 'mm/dd'
      ? '${time.month}/${time.day}'
      : '${time.day}/${time.month}';
  return '$weekname, $date';
}

String oMamPmTime(String time) {
  final splited = time.split('T');
  final num = splited[1].split(':');
  final hour = int.parse(num[0]);
  if (hour == 0) {
    return '12am';
  }
  if (hour < 12) {
    return '${hour}am';
  }
  if (hour == 12) {
    return '12pm';
  }
  return '${hour - 12}pm';
}

String oM24hour(String time) {
  final splited = time.split('T');
  return splited[1];
}

String oMTextCorrection(int code) {
  return omCodes[code] ?? 'Clear Sky';
}

String oMCurrentTextCorrection(
  int code,
  String absoluteSunriseSunset,
  String time,
) {
  final t = (time.contains('T') ? time.split('T')[1] : time.split(' ')[1]);
  final minute = int.parse(t.split(':')[1]);
  final hour = int.parse(t.split(':')[0]);

  final x = absoluteSunriseSunset.split('/');
  final upH = int.parse(x[0].split(':')[0]);
  final upM = int.parse(x[0].split(':')[1]);

  final downH = int.parse(x[1].split(':')[0]);
  final donwM = int.parse(x[1].split(':')[1]);

  final aCurrent = hour + minute / 60;
  final aUp = upH + upM / 60;
  final aDown = downH + donwM / 60;

  //return textBackground.keys.toList()[0]; // used for testing color combinations

  if (aUp <= aCurrent && aCurrent <= aDown) {
    return omCodes[code] ?? 'Clear Sky';
  } else {
    if (code == 0 || code == 1) {
      return 'Clear Night';
    } else if (code == 2 || code == 3) {
      return 'Cloudy Night';
    }
    return omCodes[code] ?? 'Clear Sky';
  }
}

String oMBackdropCorrection(String text) {
  return textBackground[text] ?? 'clear_sky3.jpg';
}

List<Color> oMtextcolorCorrection(String text) {
  return textFontColor[text] ?? [kWhite, kWhite];
}

IconData oMIconCorrection(String text) {
  //return textIconMap[text] ?? 'sun.png';
  return textMaterialIcon[text] ?? OvermorrowWeatherIcons3.clear_sky;
}

class OMCurrent extends AbstractCurrent {
  const OMCurrent({
    required super.precip,
    required super.humidity,
    required super.feels_like,
    required super.temp,
    required super.text,
    required super.uv,
    required super.wind,
    required super.wind_dir,
    required super.imageService,
    required super.palette,
    required super.colorPop,
    required super.descColor,
  });

  static Future<OMCurrent> fromJson(
    Map<String, dynamic> item,
    Map<String, String> settings,
    AbstractSunstatus sunstatus,
    String timenow,
    String realLoc,
    double lat,
    double lng,
    int start,
    int dayDif,
    AppLocalizations context,
    bool isonline,
  ) async {
    var currentCondition = oMCurrentTextCorrection(
      item['current']['weather_code'] as int,
      sunstatus.absoluteSunriseSunset,
      timenow,
    );

    //offline mode
    if (!isonline) {
      currentCondition = oMCurrentTextCorrection(
        item['hourly']['weather_code'][start] as int,
        sunstatus.absoluteSunriseSunset,
        timenow,
      );
    }

    final imageService = await ImageService.getImageService(
      currentCondition,
      realLoc,
      settings,
    );
    final colorPalette = await ColorPalette.getColorPalette(
      imageService.image,
      settings['Color mode']!,
      settings,
    );

    return OMCurrent(
      imageService: imageService,
      palette: colorPalette.palette,
      colorPop: colorPalette.colorPop,
      descColor: colorPalette.descColor,
      text: conditionTranslation(currentCondition, context) ?? 'TranslationErr',
      uv: (item['daily']['uv_index_max'][dayDif] as double).round(),
      feels_like: unit_coversion(
        item['current']['apparent_temperature'] as double,
        settings['Temperature']!,
      ).round(),
      precip: double.parse(
        unit_coversion(
          item['daily']['precipitation_sum'][dayDif] as double,
          settings['Precipitation']!,
        ).toStringAsFixed(1),
      ),
      wind: unit_coversion(
        item['hourly']['wind_speed_10m'][start] as double,
        settings['Wind']!,
      ).round(),
      humidity: item['current']['relative_humidity_2m'] as int,
      temp: unit_coversion(
        isonline
            ? item['current']['temperature_2m'] as double
            : item['hourly']['temperature_2m'][start] as double,
        settings['Temperature']!,
      ).round(),
      wind_dir: item['hourly']['wind_direction_10m'][start] as int,
    );
  }
}

class OMDay extends AbstractDay {
  const OMDay({
    required super.text,
    required super.icon,
    required super.name,
    required super.minTemp,
    required super.maxTemp,
    required super.rawMinTemp,
    required super.rawMaxTemp,
    required super.hourly,
    required super.precip_prob,
    required super.total_precip,
    required super.windspeed,
    required super.hourly_for_precip,
    required super.mm_precip,
    required super.uv,
    required super.wind_dir,
  });

  static OMDay? build(
    Map<String, dynamic> item,
    Map<String, String> settings,
    int index,
    AbstractSunstatus sunstatus,
    DateTime approximatelocal,
    int dayDif,
    AppLocalizations localizations,
  ) {
    final hours = buildHours(
      index,
      true,
      item,
      settings,
      sunstatus,
      approximatelocal,
      localizations,
    );

    if (hours.isNotEmpty) {
      return OMDay(
        uv: (item['daily']['uv_index_max'][index] as double).round(),
        icon: oMIconCorrection(
          oMTextCorrection(item['daily']['weather_code'][index] as int),
        ),
        text:
            conditionTranslation(
              oMTextCorrection(item['daily']['weather_code'][index] as int),
              localizations,
            ) ??
            'TranslationErr',
        name: oMGetName(index, settings, item, dayDif, localizations),
        windspeed: unit_coversion(
          item['daily']['wind_speed_10m_max'][index] as double,
          settings['Wind']!,
        ).round(),
        total_precip: double.parse(
          unit_coversion(
            item['daily']['precipitation_sum'][index] as double,
            settings['Precipitation']!,
          ).toStringAsFixed(1),
        ),
        minTemp: unit_coversion(
          item['daily']['temperature_2m_min'][index] as double,
          settings['Temperature']!,
        ).round(),
        maxTemp: unit_coversion(
          item['daily']['temperature_2m_max'][index] as double,
          settings['Temperature']!,
        ).round(),
        rawMinTemp: item['daily']['temperature_2m_min'][index] as double,
        rawMaxTemp: item['daily']['temperature_2m_max'][index] as double,
        precip_prob:
            item['daily']['precipitation_probability_max'][index] as int? ?? 0,
        mm_precip: item['daily']['precipitation_sum'][index] as double,
        hourly_for_precip: buildHours(
          index,
          false,
          item,
          settings,
          sunstatus,
          approximatelocal,
          localizations,
        ),
        hourly: hours,
        wind_dir:
            item['daily']['wind_direction_10m_dominant'][index] as int? ?? 0,
      );
    }
    return null;
  }

  static List<OMHour> buildHours(
    int index,
    bool getRidFirst,
    Map<String, dynamic> item,
    Map<String, String> settings,
    AbstractSunstatus sunstatus,
    DateTime approximatelocal,
    AppLocalizations localizations,
  ) {
    final hourly = <OMHour>[];

    final l = item['hourly']['weather_code'].length as int;

    for (var i = 0; i < 24; i++) {
      final j = index * 24 + i;
      final hour = DateTime.parse(item['hourly']['time'][j] as String);
      if ((approximatelocal.difference(hour).inMinutes <= 0 || !getRidFirst) &&
          l > j) {
        hourly.add(
          OMHour.fromJson(item, j, settings, sunstatus, localizations),
        );
      }
    }
    return hourly;
  }
}

class OM15MinutePrecip extends Abstract15MinPrecip {
  const OM15MinutePrecip({
    required super.t_minus,
    required super.precip_sum,
    required super.precips,
  });

  static OM15MinutePrecip fromJson(
    Map<String, dynamic> item,
    Map<String, String> settings,
    int minuteOffset,
    AppLocalizations localizations,
  ) {
    var closest = 100;
    var end = -1;
    double sum = 0;

    final precips = <double>[];

    final offset15 = minuteOffset ~/ 15;

    for (
      var i = offset15;
      i < (item['minutely_15']['precipitation'].length as int);
      i++
    ) {
      final x = item['minutely_15']['precipitation'][i] as double;
      if (x > 0.0) {
        if (closest == 100) {
          closest = i;
        }
        if (i > end) {
          end = i;
        }
      }
      sum += x;

      precips.add(x);
    }

    //make it still be the same length so it doesn't mess up the labeling
    for (var i = 0; i < offset15; i++) {
      precips.add(0);
    }

    sum = max(sum, 0.1); //if there is rain then it shouldn't write 0

    var tMinus = '';
    if (closest != 100) {
      if (closest <= 1) {
        if (end == 1) {
          tMinus = localizations.rainInHalfHour;
        } else if (end <= 2) {
          final x = [15, 30, 45][end];
          tMinus = localizations.rainInMinutes(x);
        } else if (end ~/ 4 == 1) {
          tMinus = localizations.rainInOneHour;
        } else {
          final x = (end + 2) ~/ 4;
          tMinus = localizations.rainInHours(x);
        }
      } else if (closest < 4) {
        final x = [15, 30, 45][closest - 1];
        tMinus = localizations.rainExpectedInMinutes(x);
      } else if ((closest + 2) ~/ 4 == 1) {
        tMinus = localizations.rainExpectedInOneHour;
      } else {
        final x = (closest + 2) ~/ 4;
        tMinus = localizations.rainExpectedInHours(x);
      }
    }

    return OM15MinutePrecip(
      t_minus: tMinus,
      precip_sum: unit_coversion(sum, settings['Precipitation']!),
      precips: precips,
    );
  }
}

class OMHour extends AbstractHour {
  const OMHour({
    required super.temp,
    required super.time,
    required super.icon,
    required super.text,
    required super.precip,
    required super.wind,
    required super.raw_precip,
    required super.raw_temp,
    required super.raw_wind,
    required super.wind_dir,
    required super.wind_gusts,
    required super.uv,
    required super.precip_prob,
    required super.rawText,
  });

  static OMHour fromJson(
    Map<String, dynamic> item,
    int index,
    Map<String, String> settings,
    AbstractSunstatus sunstatus,
    AppLocalizations localizations,
  ) => OMHour(
    temp: unit_coversion(
      item['hourly']['temperature_2m'][index] as double,
      settings['Temperature']!,
    ).round(),
    text:
        conditionTranslation(
          oMCurrentTextCorrection(
            item['hourly']['weather_code'][index] as int,
            sunstatus.absoluteSunriseSunset,
            item['hourly']['time'][index] as String,
          ),
          localizations,
        ) ??
        'TranslationErr',
    icon: oMIconCorrection(
      oMCurrentTextCorrection(
        item['hourly']['weather_code'][index] as int,
        sunstatus.absoluteSunriseSunset,
        item['hourly']['time'][index] as String,
      ),
    ),
    time: settings['Time mode'] == '12 hour'
        ? oMamPmTime(item['hourly']['time'][index] as String)
        : oM24hour(item['hourly']['time'][index] as String),
    precip: double.parse(
      unit_coversion(
        item['hourly']['precipitation'][index] as double,
        settings['Precipitation']!,
      ).toStringAsFixed(1),
    ),
    precip_prob:
        item['hourly']['precipitation_probability'][index] as int? ?? 0,
    wind: double.parse(
      unit_coversion(
        item['hourly']['wind_speed_10m'][index] as double,
        settings['Wind']!,
      ).toStringAsFixed(1),
    ),
    wind_gusts: unit_coversion(
      item['hourly']['wind_gusts_10m'][index] as double,
      settings['Wind']!,
    ).toInt(),
    wind_dir: item['hourly']['wind_direction_10m'][index] as int? ?? 0,
    uv: (item['hourly']['uv_index'][index] as double).round(),
    raw_precip: item['hourly']['precipitation'][index] as double,
    raw_temp: item['hourly']['temperature_2m'][index] as double,
    raw_wind: item['hourly']['wind_speed_10m'][index] as double,
    rawText: '',
  );
}

class OMSunstatus extends AbstractSunstatus {
  const OMSunstatus({
    required super.sunrise,
    required super.sunstatus,
    required super.sunset,
    required super.absoluteSunriseSunset,
  });

  static OMSunstatus fromJson(
    Map<String, dynamic> item,
    Map<String, String> settings,
  ) => OMSunstatus(
    sunrise: settings['Time mode'] == '24 hour'
        ? omConvertTime(item['daily']['sunrise'][0] as String)
        : OMamPmTime(item['daily']['sunrise'][0] as String),
    sunset: settings['Time mode'] == '24 hour'
        ? omConvertTime(item['daily']['sunset'][0] as String)
        : OMamPmTime(item['daily']['sunset'][0] as String),
    absoluteSunriseSunset:
        "${omConvertTime(item["daily"]["sunrise"][0] as String)}/"
        "${omConvertTime(item["daily"]["sunset"][0] as String)}",
    sunstatus: OMGetSunStatus(item),
  );
}

class OMAqi extends AbstractAqi {
  const OMAqi({
    required super.aqi_desc,
    required super.aqi_title,
    required super.aqi_index,
  });

  static Future<OMAqi> fromJson(
    double lat,
    double lng,
    settings,
    AppLocalizations localizations,
  ) async {
    final params = {
      'latitude': lat.toString(),
      'longitude': lng.toString(),
      'current': ['european_aqi'],
    };
    final url = Uri.https(
      'air-quality-api.open-meteo.com',
      'v1/air-quality',
      params,
    );

    //var file = await cacheManager2.getSingleFile(url.toString(), key: "$lat, $lng, aqi open-meteo").timeout(const Duration(seconds: 6));
    final file = await XCustomCacheManager.fetchData(
      url.toString(),
      '$lat, $lng, aqi open-meteo',
    );

    final response = (await file[0].readAsString()) as String;
    final item = (jsonDecode(response) as Map<String, dynamic>)['current'];

    final index = aqiIndexCorrection(item['european_aqi'] as int? ?? 0);

    return OMAqi(
      aqi_index: index,
      aqi_title: omAqiTitle(index, localizations),
      aqi_desc: omAqiDesc(index, localizations),
    );
  }
}

class OMExtendedAqi {
  //this data will only be called if you open the Air quality page
  //this is done to reduce the amount of unused calls to the open-meteo servers

  final double pm2_5;
  final double pm10;
  final double o3;
  final double no2;
  final double co;
  final double so2;

  //percent
  final double pm2_5_p;
  final double pm10_p;
  final double o3_p;
  final double no2_p;
  final double co_p;
  final double so2_p;

  final double alder;
  final double birch;
  final double grass;
  final double mugwort;
  final double olive;
  final double ragweed;

  //hourly
  final List<double> pm2_5_h;
  final List<double> pm10_h;
  final List<double> no2_h;
  final List<double> o3_h;
  final List<double> co_h;
  final List<double> so2_h;

  final String mainPollutant;

  final List<int> dailyAqi;

  final int europeanAqi;
  final int usAqi;
  final String europeanDesc;
  final String usDesc;

  final double aod;
  final String aodDesc;

  final double dust;

  const OMExtendedAqi({
    required this.no2,
    required this.o3,
    required this.pm2_5,
    required this.pm10,
    required this.co,
    required this.so2,
    required this.alder,
    required this.birch,
    required this.grass,
    required this.mugwort,
    required this.olive,
    required this.ragweed,
    required this.aod,
    required this.aodDesc,
    required this.dust,
    required this.europeanAqi,
    required this.usAqi,
    required this.europeanDesc,
    required this.usDesc,
    required this.no2_h,
    required this.o3_h,
    required this.pm2_5_h,
    required this.pm10_h,
    required this.co_h,
    required this.so2_h,
    required this.pm2_5_p,
    required this.pm10_p,
    required this.o3_p,
    required this.no2_p,
    required this.co_p,
    required this.so2_p,
    required this.dailyAqi,
    required this.mainPollutant,
  });

  static Future<OMExtendedAqi> fromJson(
    double lat,
    double lng,
    settings,
    AppLocalizations localizations,
  ) async {
    final params = {
      'latitude': lat.toString(),
      'longitude': lng.toString(),
      'current': [
        'carbon_monoxide',
        'sulphur_dioxide',
        'pm10',
        'pm2_5',
        'nitrogen_dioxide',
        'ozone',
        'alder_pollen',
        'birch_pollen',
        'grass_pollen',
        'mugwort_pollen',
        'olive_pollen',
        'ragweed_pollen',
        'aerosol_optical_depth',
        'dust',
        'european_aqi',
        'us_aqi',
      ],
      'hourly': [
        'pm10',
        'pm2_5',
        'nitrogen_dioxide',
        'ozone',
        'sulphur_dioxide',
        'carbon_monoxide',
      ],
      'timezone': 'auto',
      'forecast_days': '5',
    };
    final url = Uri.https(
      'air-quality-api.open-meteo.com',
      'v1/air-quality',
      params,
    );

    //var file = await cacheManager2.getSingleFile(url.toString(), key: "$lat, $lng, aqi open-meteo extended").timeout(const Duration(seconds: 3));
    final file = await XCustomCacheManager.fetchData(
      url.toString(),
      '$lat, $lng, aqi-extended open-meteo',
    );

    final response = (await file[0].readAsString()) as String;
    final item = jsonDecode(response) as Map<String, dynamic>;

    final no2H = List<double>.from(
      (item['hourly']['nitrogen_dioxide'] as List?)?.map(
            (e) => (e as double?) ?? 0.0,
          ) ??
          [],
    );
    final o3H = List<double>.from(
      (item['hourly']['ozone'] as List?)?.map((e) => (e as double?) ?? 0.0) ??
          [],
    );
    final pm25H = List<double>.from(
      (item['hourly']['pm2_5'] as List?)?.map((e) => (e as double?) ?? 0.0) ??
          [],
    );
    final pm10H = List<double>.from(
      (item['hourly']['pm10'] as List?)?.map((e) => (e as double?) ?? 0.0) ??
          [],
    );
    final coH = List<double>.from(
      (item['hourly']['carbon_monoxide'] as List?)?.map(
            (e) => (e as double?) ?? 0.0,
          ) ??
          [],
    );
    final so2H = List<double>.from(
      (item['hourly']['sulphur_dioxide'] as List?)?.map(
            (e) => (e as double?) ?? 0.0,
          ) ??
          [],
    );

    //determine the individual air quality indexes for each day using the hourly values of the different contaminants
    // https://www.airnow.gov/publications/air-quality-index/technical-assistance-document-for-reporting-the-daily-aqi/

    const aqiCategories = <int>[0, 51, 101, 151, 201, 301, 500];
    const europeanAqiCategories = <int>[0, 26, 51, 151, 76, 101, 500];
    const pollutantNames = <String>[
      'ozone',
      'pm2.5',
      'pm10',
      'carbon monoxide',
      'sulphur dioxide',
      'nitrogen dioxide',
    ];
    const breakpoints = <List<double>>[
      [0, 0.055, 0.071, 0.086, 0.106, 0.201, 0.604], //o3
      [0, 9.1, 35.5, 55.5, 125.5, 225.5, 325.4], //pm2.5
      [0, 55, 155, 255, 355, 425, 604], //pm10
      [0, 4.5, 9.5, 12.5, 15.5, 30.5, 50.4], //co
      [0, 36, 76, 186, 305, 605, 1004], //so2
      [0, 54, 101, 361, 650, 1250, 2049], //no2
    ];

    final dailyAqi = <int>[];
    var mainPollutant = 'hehe';
    for (var i = 0; i < (item['hourly']['pm2_5'].length as int) / 24; i++) {
      //some of the values in the documentation are in ppm so open-meteo's mg/m^3 data has to be converted to ppm
      //https://teesing.com/en/tools/ppm-mg3-converter <- used this as a reference
      //the division by 1000 is because is because we're converting micrograms to grams

      final values = <double>[
        double.parse(
          (o3H.getRange(i * 24, (i + 1) * 24).reduce(max) * 24.45 / 48 / 1000)
              .toStringAsFixed(3),
        ),
        double.parse(
          pm25H.getRange(i * 24, (i + 1) * 24).reduce(max).toStringAsFixed(1),
        ),
        double.parse(
          pm10H.getRange(i * 24, (i + 1) * 24).reduce(max).toStringAsFixed(0),
        ),
        double.parse(
          (coH.getRange(i * 24, (i + 1) * 24).reduce(max) *
                  24.45 /
                  28.01 /
                  1000)
              .toStringAsFixed(1),
        ),
        double.parse(
          (so2H.getRange(i * 24, (i + 1) * 24).reduce(max) *
                  24.45 /
                  64.066 /
                  1000)
              .toStringAsFixed(0),
        ),
        double.parse(
          (no2H.getRange(i * 24, (i + 1) * 24).reduce(max) *
                  24.45 /
                  46.0055 /
                  1000)
              .toStringAsFixed(0),
        ),
      ];

      final finalIndexes = <int>[];

      for (var x = 0; x < 6; x++) {
        final current = values[x];

        //find the above and below breakpoints
        double bpHi = 1;
        double bpLo = 0;

        var iHi = 1;
        var iLo = 0;

        for (var z = 0; z < breakpoints[x].length - 1; z++) {
          if (current >= breakpoints[x][z]) {
            bpLo = breakpoints[x][z];
            bpHi = breakpoints[x][z + 1];

            iLo = aqiCategories[z];
            iHi = aqiCategories[z + 1];
          }
        }

        final finalIndex =
            (((iHi - iLo) / (bpHi - bpLo)) * (current - bpLo) + iLo).round();
        finalIndexes.add(finalIndex);
      }
      final biggest = finalIndexes.reduce(max);

      //determine the main pollutant for today
      if (i == 0) {
        mainPollutant = pollutantNames[finalIndexes.indexOf(biggest)];
      }

      dailyAqi.add(biggest);
    }

    final aodNames = [
      localizations.extremelyHazy,
      localizations.veryClear,
      localizations.clear,
      localizations.slightlyHazy,
      localizations.haze,
      localizations.veryHazy,
      localizations.extremelyHazy,
    ];
    const aodBreakpoints = <double>[0, 0.05, 0.1, 0.2, 0.4, 0.7, 1];

    final aodValue = item['current']['aerosol_optical_depth'] as double? ?? 0.0;

    var aodIndex = 0;
    for (var i = 0; i < aodBreakpoints.length; i++) {
      if (aodValue > aodBreakpoints[i]) {
        aodIndex = i;
      }
    }

    final aodDesc = aodNames[aodIndex];

    var usIndex = 0;
    var europeanIndex = 0;
    for (var i = 0; i < aqiCategories.length; i++) {
      if (item['current']['european_aqi'] as int > aqiCategories[i]) {
        usIndex = i;
      }
      if (item['current']['us_aqi'] as int > europeanAqiCategories[i]) {
        europeanIndex = i;
      }
    }

    final usDesc = omAqiTitle(
      usIndex + 1,
      localizations,
    ); //because the function expects values between 1 and something
    final europeanDesc = omAqiTitle(europeanIndex + 1, localizations);

    return OMExtendedAqi(
      pm10: item['current']['pm10'] as double? ?? -1.0,
      pm2_5: item['current']['pm2_5'] as double? ?? -1.0,
      no2: item['current']['nitrogen_dioxide'] as double? ?? -1.0,
      o3: item['current']['ozone'] as double? ?? -1.0,
      co: item['current']['carbon_monoxide'] as double? ?? -1.0,
      so2: item['current']['sulphur_dioxide'] as double? ?? -1.0,

      alder: item['current']['alder_pollen'] as double? ?? -1,
      birch: item['current']['birch_pollen'] as double? ?? -1,
      grass: item['current']['grass_pollen'] as double? ?? -1,
      mugwort: item['current']['mugwort_pollen'] as double? ?? -1,
      olive: item['current']['olive_pollen'] as double? ?? -1,
      ragweed: item['current']['ragweed_pollen'] as double? ?? -1,

      aod: aodValue,
      aodDesc: aodDesc,

      dust: item['current']['dust'] as double? ?? -1.0,

      no2_h: no2H,
      o3_h: o3H,
      pm2_5_h: pm25H,
      pm10_h: pm10H,
      co_h: coH,
      so2_h: so2H,

      mainPollutant: mainPollutant,

      dailyAqi: dailyAqi,

      europeanAqi: item['current']['european_aqi'] as int? ?? -1,
      usAqi: item['current']['us_aqi'] as int? ?? -1,
      usDesc: usDesc,
      europeanDesc: europeanDesc,

      //i am looking at the one before last because the last is basically only for calculating the high
      //and not actually expected to be reached
      o3_p:
          o3H[0] *
          24.45 /
          48 /
          1000 /
          breakpoints[0][breakpoints[0].length - 2] *
          100,
      pm2_5_p: pm25H[0] / breakpoints[1][breakpoints[1].length - 2] * 100,
      pm10_p: pm10H[0] / breakpoints[2][breakpoints[2].length - 2] * 100,
      co_p:
          coH[0] *
          24.45 /
          28.01 /
          1000 /
          breakpoints[3][breakpoints[3].length - 2] *
          100,
      so2_p:
          so2H[0] *
          24.45 /
          64.066 /
          1000 /
          breakpoints[4][breakpoints[4].length - 2] *
          100,
      no2_p:
          no2H[0] *
          24.45 /
          46.0055 /
          1000 /
          breakpoints[5][breakpoints[5].length - 2] *
          100,
    );
  }
}

Future<WeatherData> OMGetWeatherData(
  double lat,
  double lng,
  String realLoc,
  Map<String, String> settings,
  String placeName,
  AppLocalizations localizations,
) async {
  final om = await OMRequestData(lat, lng, realLoc);
  final oMBody = om[0] as Map<String, dynamic>;

  final fetchDatetime = om[1] as DateTime;
  final isonline = om[2] as bool;

  final localtime = OMGetLocalTime(oMBody);

  final realTime = 'jT${localtime.hour}:${localtime.minute}';

  final lastKnowTime = DateTime.parse(oMBody['current']['time'] as String);

  //get hour diff
  final approximateLocal = DateTime(
    localtime.year,
    localtime.month,
    localtime.day,
    localtime.hour,
  );
  final start = approximateLocal
      .difference(
        DateTime(lastKnowTime.year, lastKnowTime.month, lastKnowTime.day),
      )
      .inHours;

  //get day diff
  final dayDif = DateTime(localtime.year, localtime.month, localtime.day)
      .difference(
        DateTime(lastKnowTime.year, lastKnowTime.month, lastKnowTime.day),
      )
      .inDays;

  //make sure that there is data left
  if (dayDif >= (oMBody['daily']['weather_code'].length as int)) {
    throw const SocketException('Cached data expired');
  }

  final sunstatus = OMSunstatus.fromJson(oMBody, settings);

  final days = <OMDay>[];
  final hourly72 = <dynamic>[];

  for (var n = 0; n < 14; n++) {
    final day = OMDay.build(
      oMBody,
      settings,
      n,
      sunstatus,
      approximateLocal,
      dayDif,
      localizations,
    );
    if (day != null) {
      days.add(day);
      if (hourly72.length < 72) {
        if (n != 0) {
          hourly72.add(day.name);
        }
        for (var z = 0; z < day.hourly.length; z++) {
          if (hourly72.length < 72) {
            hourly72.add(day.hourly[z]);
          }
        }
      }
    }
  }

  return WeatherData(
    radar: await RainviewerRadar.getData(),
    aqi: await OMAqi.fromJson(lat, lng, settings, localizations),
    sunstatus: sunstatus,
    minutely_15_precip: OM15MinutePrecip.fromJson(
      oMBody,
      settings,
      DateTime(
        localtime.year,
        localtime.month,
        localtime.day,
        localtime.hour,
        localtime.minute,
      ).difference(lastKnowTime).inMinutes,
      localizations,
    ),
    alerts: [],
    dailyMinMaxTemp: omGetMaxMinTempForDaily(days),
    hourly72: hourly72,
    current: await OMCurrent.fromJson(
      oMBody,
      settings,
      sunstatus,
      realTime,
      realLoc,
      lat,
      lng,
      start,
      dayDif,
      localizations,
      isonline,
    ),
    days: days,
    lat: lat,
    lng: lng,
    place: placeName,
    settings: settings,
    provider: 'open-meteo',
    real_loc: realLoc,
    fetch_datetime: fetchDatetime,
    updatedTime: DateTime.now(),
    localtime: realTime.split('T')[1],
    isonline: isonline,
  );
}

Future<LightCurrentWeatherData> omGetLightCurrentData(
  Map<String, String> settings,
  String placeName,
  double lat,
  double lon,
) async {
  final oMParams = {
    'latitude': lat.toString(),
    'longitude': lon.toString(),
    'current': ['temperature_2m', 'weather_code'],
    'daily': ['sunrise', 'sunset'],
    'forecast_days': '1',
    'timezone': 'auto',
  };

  final oMUrl = Uri.https('api.open-meteo.com', 'v1/forecast', oMParams);
  final response = (await http.get(oMUrl)).body;

  final item = jsonDecode(response) as Map<String, dynamic>;

  final localtime = OMGetLocalTime(item);
  final realTime = 'jT${localtime.hour}:${localtime.minute}';
  final now = DateTime.now();

  final absoluteSunriseSunset =
      "${omConvertTime(item["daily"]["sunrise"][0] as String)}/"
      "${omConvertTime(item["daily"]["sunset"][0] as String)}";

  return LightCurrentWeatherData(
    condition: oMCurrentTextCorrection(
      item['current']['weather_code'] as int,
      absoluteSunriseSunset,
      realTime,
    ),
    place: placeName,
    temp: unit_coversion(
      item['current']['temperature_2m'] as double,
      settings['Temperature']!,
    ).round(),
    updatedTime: "${now.hour}:${now.minute.toString().padLeft(2, "0")}",
    dateString: getDateStringFromLocalTime(now),
  );
}

Future<LightWindData> omGetLightWindData(
  Map<String, String> settings,
  double lat,
  double lon,
) async {
  final oMParams = {
    'latitude': lat.toString(),
    'longitude': lon.toString(),
    'current': ['wind_speed_10m', 'wind_direction_10m'],
  };

  final oMUrl = Uri.https('api.open-meteo.com', 'v1/forecast', oMParams);
  final response = (await http.get(oMUrl)).body;

  final item = jsonDecode(response);

  return LightWindData(
    windDirAngle: item['current']['wind_direction_10m'] as int,
    windSpeed: unit_coversion(
      item['current']['wind_speed_10m'] as double,
      settings['Wind']!,
    ).round(),
    windUnit: settings['Wind']!,
  );
}

Future<LightHourlyForecastData> omGetHourlyForecast(
  Map<String, String> settings,
  String placeName,
  double lat,
  double lon,
) async {
  final oMParams = {
    'latitude': lat.toString(),
    'longitude': lon.toString(),
    'current': ['temperature_2m', 'weather_code'],
    'hourly': ['temperature_2m', 'weather_code'],
    'daily': ['sunrise', 'sunset'],
    'forecast_days': '1',
    'timezone': 'auto',
  };

  final oMUrl = Uri.https('api.open-meteo.com', 'v1/forecast', oMParams);
  final response = (await http.get(oMUrl)).body;

  final item = jsonDecode(response) as Map<String, dynamic>;

  final localtime = OMGetLocalTime(item);
  final realTime = 'jT${localtime.hour}:${localtime.minute}';
  final now = DateTime.now();

  final absoluteSunriseSunset =
      "${omConvertTime(item["daily"]["sunrise"][0] as String)}/"
      "${omConvertTime(item["daily"]["sunset"][0] as String)}";

  final hourlyConditions = <String>[];
  final hourlyTemps = <int>[];
  final hourlyNames = <String>[];

  for (var i = 0; i < (item['hourly']['temperature_2m'].length as int); i++) {
    final d = DateTime.parse(item['hourly']['time'][i] as String);
    if (d.hour % 6 == 0) {
      hourlyConditions.add(
        oMCurrentTextCorrection(
          item['hourly']['weather_code'][i] as int,
          absoluteSunriseSunset,
          item['hourly']['time'][i] as String,
        ),
      );
      hourlyTemps.add(
        unit_coversion(
          item['hourly']['temperature_2m'][i] as double,
          settings['Temperature']!,
        ).round(),
      );
      hourlyNames.add('${d.hour}h');
    }
  }

  return LightHourlyForecastData(
    place: placeName,
    currentCondition: oMCurrentTextCorrection(
      item['current']['weather_code'] as int,
      absoluteSunriseSunset,
      realTime,
    ),
    currentTemp: unit_coversion(
      item['current']['temperature_2m'] as double,
      settings['Temperature']!,
    ).round(),
    updatedTime: "${now.hour}:${now.minute.toString().padLeft(2, "0")}",
    //i can't sync lists to widgets so i need to encode and then decode them
    hourlyConditions: jsonEncode(hourlyConditions),
    hourlyNames: jsonEncode(hourlyNames),
    hourlyTemps: jsonEncode(hourlyTemps),
  );
}
