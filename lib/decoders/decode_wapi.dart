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
import 'package:overmorrow/Icons/overmorrow_weather_icons3_icons.dart';
import 'package:overmorrow/api_key.dart';
import 'package:overmorrow/caching.dart';
import 'package:overmorrow/core/core.dart';
import 'package:overmorrow/decoders/decode_OM.dart';
import 'package:overmorrow/decoders/decode_RV.dart';
import 'package:overmorrow/decoders/weather_data.dart';
import 'package:overmorrow/weather/abstract_15_min_precip.dart';
import 'package:overmorrow/weather/abstract_aqi.dart';
import 'package:overmorrow/weather/abstract_current.dart';
import 'package:overmorrow/weather/abstract_day.dart';
import 'package:overmorrow/weather/abstract_hour.dart';
import 'package:overmorrow/weather/abstract_sunstatus.dart';
import 'package:overmorrow/weather_refact.dart' as weather_refactor;
import 'package:overmorrow/weather_refact.dart';

//decodes the whole response from the weatherapi.com api_call

Future<List<dynamic>> WapiMakeRequest(String latlong, String realLoc) async {
  //gets the json response for weatherapi.com
  final params = {
    'key': wapi_Key,
    'q': latlong,
    'days': '3',
    'aqi': 'yes',
    'alerts': 'yes',
  };
  final url = Uri.https('api.weatherapi.com', 'v1/forecast.json', params);

  final file = await XCustomCacheManager.fetchData(
    url.toString(),
    '$realLoc, weatherapi.com',
  );

  final fetchDatetime = (await file[0].lastModified()) as DateTime;
  final isonline = file[1] as bool;

  final response = (await file[0].readAsString()) as String;

  final wapiBody = jsonDecode(response);

  return [wapiBody, fetchDatetime, isonline];
}

int wapiGetWindDir(List<dynamic> data) {
  var total = 0;
  for (var i = 0; i < data.length; i++) {
    final x = data[i]['wind_degree'] as int;
    total += x;
  }
  return (total / data.length).round();
}

List<WapiAlert> getWapiAlerts(
  Map<String, dynamic> data,
  AppLocalizations localizations,
) {
  final alerts = <WapiAlert>[];
  final alertList = data['alerts']['alert'] as List<dynamic>;
  //for some reason weatherapi sometimes returns like 5 of the same alerts, so i have to manually remove duplicates
  final seenDescs = <String>[];
  for (var i = 0; i < alertList.length; i++) {
    final d = alertList[i]['desc'] as String;
    if (!seenDescs.contains(d)) {
      alerts.add(
        WapiAlert.fromJson(alertList[i] as Map<String, dynamic>, localizations),
      );
      seenDescs.add(d);
    }
  }
  return alerts;
}

String amPmTime(String time) {
  final splited = time.split(' ');
  final num = splited[0].split(':');
  final hour = int.parse(num[0]);
  final minute = int.parse(num[1]);
  var atEnd = 'am';
  if (splited[1] == 'PM') {
    atEnd = 'pm';
  }
  if (minute < 10) {
    return '$hour:0$minute$atEnd';
  }

  return '$hour:$minute$atEnd';
}

String convertTime(String input, {String by = ' '}) {
  final splited = input.split(by);
  final num = splited[0].split(':');
  var hour = int.parse(num[0]);
  final minute = int.parse(num[1]);
  if (splited[1] == 'PM') {
    hour += 12;
  }
  if (hour < 10) {
    if (minute < 10) {
      return '0$hour:0$minute';
    }
    return '0$hour:$minute';
  }
  if (minute < 10) {
    return '$hour:0$minute';
  }
  return '$hour:$minute';
}

double getSunStatus(
  String sunrise,
  String sunset,
  DateTime localtime, {
  String by = ' ',
}) {
  final splited1 = sunrise.split(by);
  final num1 = splited1[0].split(':');
  var hour1 = int.parse(num1[0]);
  final minute1 = int.parse(num1[1]);
  if (splited1[1] == 'PM') {
    hour1 += 12;
  }
  final all1 = hour1 * 60 + minute1;

  final splited2 = sunset.split(' ');
  final num2 = splited2[0].split(':');
  var hour2 = int.parse(num2[0]);
  final minute2 = int.parse(num2[1]);
  if (splited2[1] == 'PM') {
    hour2 += 12;
  }
  final all2 = (hour2 * 60 + minute2) - all1;

  final hour3 = localtime.hour;
  final minute3 = localtime.minute;
  final all3 = (hour3 * 60 + minute3) - all1;

  return min(1, max(all3 / all2, 0));
}

/*Future<DateTime> WapiGetLocalTime(lat, lng) async {
  /*
  return await XWorldTime.timeByLocation(
    latitude: lat,
    longitude: lng,
  );
   */

  final params = {
    'key': timezonedbKey,
    'lat': lat.toString(),
    'lng': lng.toString(),
    'format': 'json',
    'by': 'position'
  };
  final url = Uri.https('api.timezonedb.com', 'v2.1/get-time-zone', params);
  var file = await XCustomCacheManager.fetchData(url.toString(), "$lat, $lng timezonedb.com");
  var response = await file[0].readAsString();
  var body = jsonDecode(response);

  return DateTime.parse(body["formatted"]);
}*/

double unit_coversion(double value, String unit, {int decimals = 2}) {
  final p = weather_refactor.conversionTable[unit] ?? [0, 0];
  var a = p[0] + value * p[1];
  a = double.parse(a.toStringAsFixed(decimals));
  return a;
}

IconData iconCorrection(
  dynamic name,
  int isday,
  AppLocalizations localizations,
) {
  final text = textCorrection(name, isday, false, localizations);
  //String p = weather_refactor.textIconMap[text] ?? 'clear_night.png';
  return textMaterialIcon[text] ?? OvermorrowWeatherIcons3.clear_sky;
}

String getTime(String date, bool ampm) {
  if (ampm) {
    final realtime = date.split(' ')[1];
    final realhour = realtime.split(':')[0];
    final num = int.parse(realhour);
    if (num == 0) {
      return '12am';
    } else if (num < 10) {
      final minusHour = (num % 10).toString();
      return '${minusHour}am';
    } else if (num < 12) {
      return '${realhour}am';
    } else if (num == 12) {
      return '12pm';
    }
    return '${num - 12}pm';
  } else {
    final realtime = date.split(' ');
    return realtime[1];
  }
}

String wapiGetName(
  int index,
  Map<String, String> settings,
  AppLocalizations localizations,
  Map<String, dynamic> item,
) {
  final time = DateTime.parse(item['date'] as String);
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

String getDateStringFromLocalTime(DateTime now) {
  final weekNames = <String>[
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  final monthNames = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${weekNames[now.weekday - 1]}, ${monthNames[now.month - 1]} ${now.day}';
}

String backdropCorrection(
  String name,
  int isday,
  AppLocalizations localizations,
) {
  final text = textCorrection(name, isday, false, localizations);
  final backdrop = weather_refactor.textBackground[text] ?? 'haze.jpg';

  return backdrop;
}

String textCorrection(
  dynamic name,
  int isday,
  bool ShouldTranslate,
  AppLocalizations? localizations,
) {
  var x = weather_refactor.weatherTextMap[name] ?? 'Clear Sky';
  if (x == 'Clear Sky') {
    if (isday == 1) {
      x = 'Clear Sky';
    } else {
      x = 'Clear Night';
    }
  } else if (x == 'Partly Cloudy') {
    if (isday == 1) {
      x = 'Partly Cloudy';
    } else {
      x = 'Cloudy Night';
    }
  }

  if (ShouldTranslate) {
    x = conditionTranslation(x, localizations!) ?? 'TranslationErr';
  }
  return x;
}

class WapiCurrent extends AbstractCurrent {
  const WapiCurrent({
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

  static Future<WapiCurrent> fromJson(
    Map<String, dynamic> item,
    Map<String, String> settings,
    String realLoc,
    double lat,
    double lng,
    int start,
    AppLocalizations localizations,
  ) async {
    final currentCondition = textCorrection(
      item['hour'][start]['condition']['code'],
      item['hour'][start]['is_day'] as int,
      false,
      localizations,
    );

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

    return WapiCurrent(
      imageService: imageService,
      palette: colorPalette.palette,
      colorPop: colorPalette.colorPop,
      descColor: colorPalette.descColor,
      text: textCorrection(
        item['hour'][start]['condition']['code'],
        item['hour'][start]['is_day'] as int,
        true,
        localizations,
      ),
      temp: unit_coversion(
        item['hour'][start]['temp_c'] as double,
        settings['Temperature']!,
      ).round(),
      feels_like: unit_coversion(
        item['hour'][start]['feelslike_c'] as double,
        settings['Temperature']!,
      ).round(),
      uv: (item['hour'][start]['uv'] as double).round(),
      humidity: item['hour'][start]['humidity'] as int,
      precip: double.parse(
        unit_coversion(
          item['day']['totalprecip_mm'] as double,
          settings['Precipitation']!,
        ).toStringAsFixed(1),
      ),
      wind: unit_coversion(
        item['hour'][start]['wind_kph'] as double,
        settings['Wind']!,
      ).round(),
      wind_dir: item['hour'][start]['wind_degree'] as int,
    );
  }
}

class WapiDay extends AbstractDay {
  const WapiDay({
    required super.text,
    required super.icon,
    required super.name,
    required super.minTemp,
    required super.maxTemp,
    required super.rawMinTemp,
    required super.rawMaxTemp,
    required super.hourly,
    required super.uv,
    required super.precip_prob,
    required super.total_precip,
    required super.windspeed,
    required super.hourly_for_precip,
    required super.mm_precip,
    required super.wind_dir,
  });

  static WapiDay fromJson(
    Map<String, dynamic> item,
    int index,
    Map<String, String> settings,
    DateTime approximatelocal,
    AppLocalizations localizations,
  ) => WapiDay(
    text: textCorrection(
      item['day']['condition']['code'],
      1,
      true,
      localizations,
    ),
    icon: iconCorrection(
      item['day']['condition']['code'],
      1,
      localizations,
    ),
    name: wapiGetName(index, settings, localizations, item),
    minTemp: unit_coversion(
      item['day']['mintemp_c'] as double,
      settings['Temperature']!,
    ).round(),
    maxTemp: unit_coversion(
      item['day']['maxtemp_c'] as double,
      settings['Temperature']!,
    ).round(),
    rawMinTemp: item['day']['mintemp_c'] as double,
    rawMaxTemp: item['day']['maxtemp_c'] as double,
    hourly: buildWapiHour(
      item['hour'] as List<dynamic>,
      settings,
      index,
      approximatelocal,
      true,
      localizations,
    ),
    hourly_for_precip: buildWapiHour(
      item['hour'] as List<dynamic>,
      settings,
      index,
      approximatelocal,
      false,
      localizations,
    ),
    mm_precip:
        (item['day']['totalprecip_mm'] as double) +
        (item['day']['totalsnow_cm'] as double) / 10,
    total_precip: double.parse(
      unit_coversion(
        item['day']['totalprecip_mm'] as double,
        settings['Precipitation']!,
      ).toStringAsFixed(1),
    ),
    precip_prob: item['day']['daily_chance_of_rain'] as int,
    windspeed: unit_coversion(
      item['day']['maxwind_kph'] as double,
      settings['Wind']!,
    ).round(),
    uv: (item['day']['uv'] as double).round(),
    wind_dir: wapiGetWindDir(item['hour'] as List<dynamic>),
  );

  static List<WapiHour> buildWapiHour(
    List<dynamic> data,
    Map<String, String> settings,
    int index,
    DateTime approximatelocal,
    bool getRidFirst,
    AppLocalizations localizations,
  ) {
    final hourly = <WapiHour>[];

    for (var i = 0; i < 24; i++) {
      final hour = DateTime.parse(data[i]['time'] as String);
      if (approximatelocal.difference(hour).inMinutes <= 0 || !getRidFirst) {
        hourly.add(
          WapiHour.fromJson(
            data[i] as Map<String, dynamic>,
            settings,
            localizations,
          ),
        );
      }
    }
    return hourly;
  }
}

class WapiHour extends AbstractHour {
  const WapiHour({
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

  static WapiHour fromJson(
    Map<String, dynamic> item,
    Map<String, String> settings,
    AppLocalizations localizations,
  ) => WapiHour(
    text: textCorrection(
      item['condition']['code'],
      item['is_day'] as int,
      true,
      localizations,
    ),
    icon: iconCorrection(
      item['condition']['code'],
      item['is_day'] as int,
      localizations,
    ),
    temp: unit_coversion(
      item['temp_c'] as double,
      settings['Temperature']!,
    ).round(),
    time: getTime(item['time'] as String, settings['Time mode'] == '12 hour'),
    precip: double.parse(
      unit_coversion(
        (item['precip_mm'] as double) + ((item['snow_cm'] as double) / 10),
        settings['Precipitation']!,
      ).toStringAsFixed(1),
    ),
    raw_temp: item['temp_c'] as double,
    raw_precip:
        (item['precip_mm'] as double) + ((item['snow_cm'] as double) / 10),
    raw_wind: item['wind_kph'] as double,
    wind: double.parse(
      unit_coversion(
        item['wind_kph'] as double,
        settings['Wind']!,
      ).toStringAsFixed(1),
    ),
    wind_gusts: unit_coversion(
      item['gust_kph'] as double,
      settings['Wind']!,
    ).round(),
    precip_prob: max(
      item['chance_of_rain'] as int,
      item['chance_of_snow'] as int,
    ),
    uv: item['uv'].round() as int,
    wind_dir: item['wind_degree'] as int,
    rawText: '',
  );
}

class WapiSunstatus extends AbstractSunstatus {
  const WapiSunstatus({
    required super.sunrise,
    required super.sunstatus,
    required super.sunset,
    required super.absoluteSunriseSunset,
  });

  static WapiSunstatus fromJson(
    Map<String, dynamic> item,
    Map<String, String> settings,
    DateTime localtime,
  ) => WapiSunstatus(
    sunrise: settings['Time mode'] == '24 hour'
        ? convertTime(
            item['forecast']['forecastday'][0]['astro']['sunrise'] as String,
          )
        : amPmTime(
            item['forecast']['forecastday'][0]['astro']['sunrise'] as String,
          ),
    sunset: settings['Time mode'] == '24 hour'
        ? convertTime(
            item['forecast']['forecastday'][0]['astro']['sunset'] as String,
          )
        : amPmTime(
            item['forecast']['forecastday'][0]['astro']['sunset'] as String,
          ),
    absoluteSunriseSunset:
        "${convertTime(item["forecast"]["forecastday"][0]["astro"]["sunrise"] as String)}/"
        "${convertTime(item["forecast"]["forecastday"][0]["astro"]["sunset"] as String)}",
    sunstatus: getSunStatus(
      item['forecast']['forecastday'][0]['astro']['sunrise'] as String,
      item['forecast']['forecastday'][0]['astro']['sunset'] as String,
      localtime,
    ),
  );
}

class WapiAqi extends AbstractAqi {
  const WapiAqi({
    required super.aqi_index,
    required super.aqi_desc,
    required super.aqi_title,
  });

  static WapiAqi fromJson(Map<String, dynamic> item) => WapiAqi(
    aqi_index: item['current']['air_quality']['us-epa-index'] as int,
    aqi_title: [
      'good',
      'fair',
      'moderate',
      'poor',
      'very poor',
      'unhealthy',
    ][(item['current']['air_quality']['us-epa-index'] as int) - 1],
    aqi_desc: [
      'Air quality is excellent; no health risk.',
      'Acceptable air quality; minor risk for sensitive people.',
      'Sensitive individuals may experience mild effects.',
      'Health effects possible for everyone, serious for sensitive groups.',
      'Serious health effects for everyone.',
      'Emergency conditions; severe health effects for all.',
    ][(item['current']['air_quality']['us-epa-index'] as int) - 1],
  );
}

class WapiAlert {
  final String headline;
  final String start;
  final String end;
  final String desc;
  final String event;
  final String urgency;
  final String severity;
  final String certainty;
  final String areas;

  const WapiAlert({
    required this.headline,
    required this.start,
    required this.end,
    required this.desc,
    required this.event,
    required this.urgency,
    required this.severity,
    required this.certainty,
    required this.areas,
  });

  static WapiAlert fromJson(
    Map<String, dynamic> item,
    AppLocalizations localizations,
  ) {
    var start = DateTime.now();
    var end = DateTime.now();

    try {
      start = DateTime.parse(item['effective'] as String);
      end = DateTime.parse(item['expires'] as String);
    } on FormatException {
      print('no format');
    }

    final weeks = <String>[
      localizations.mon,
      localizations.tue,
      localizations.wed,
      localizations.thu,
      localizations.fri,
      localizations.sat,
      localizations.sun,
    ];

    return WapiAlert(
      headline: (item['headline'] as String?)?.trim() ?? 'No Headline',
      start:
          "${weeks[start.weekday - 1]} ${amPmTime("${start.hour}:${start.minute} j")}",
      end:
          "${weeks[end.weekday - 1]} ${amPmTime("${end.hour}:${end.minute} j")}",
      event: (item['event'] as String?)?.trim() ?? 'No Event',
      desc: (item['desc'] as String?)?.trim() ?? 'No Desc',
      urgency: (item['urgency'] as String?) ?? '--',
      severity: (item['severity'] as String?) ?? '--',
      certainty: (item['certainty'] as String?) ?? '--',
      areas: (item['areas'] as String?) ?? '--',
    );
  }
}

class Wapi15MinutePrecip extends Abstract15MinPrecip {
  //weatherapi doesn't actaully have 15 minute forecast(well it does but it's paid), but i figured i could just use the
  //hourly data and just use some smoothing between the hours to emulate the 15 minutes
  //still better than not having it

  const Wapi15MinutePrecip({
    required super.t_minus,
    required super.precip_sum,
    required super.precips,
  });

  static Wapi15MinutePrecip fromJson(
    Map<String, dynamic> item,
    Map<String, String> settings,
    int day,
    int hour,
    AppLocalizations localizations,
  ) {
    var closest = 100;
    var end = -1;
    double sum = 0;

    final precips = <double>[];
    final hourly = <double>[];

    //int day = 0;
    //int hour = 0;

    var i = 0;

    while (i < 6) {
      if ((item['forecast']['forecastday'].length as int) <= day) {
        break;
      }
      if ((item['forecast']['forecastday'][day]['hour'].length as int) > hour) {
        double x;
        if (hour == 0 && day == 0) {
          x = double.parse(
            item['current']['precip_mm'].toStringAsFixed(1) as String,
          );
        } else {
          x = double.parse(
            item['forecast']['forecastday'][day]['hour'][hour]['precip_mm']
                    .toStringAsFixed(1)
                as String,
          );
        }

        if (x > 0.0) {
          if (closest == 100) {
            closest = i + 1;
          }
          if (i >= end) {
            end = i + 1;
          }
        }

        hourly.add(x);

        i += 1;
        hour += 1;
      } else {
        day += 1;
      }
    }

    //smooth the hours into 15 minute segments

    for (var i = 0; i < hourly.length - 1; i++) {
      final now = hourly[i];
      final next = hourly[i + 1];

      final dif = next - now;
      for (double x = 0; x <= 1; x += 0.25) {
        final g =
            (now + (dif * x)) /
            4; //because we are dividing the sum of 1 hour into quarters
        sum += g;
        precips.add(g);
      }
    }

    var tMinus = '';
    if (closest != 100) {
      if (closest <= 2) {
        if (end <= 1) {
          tMinus = localizations.rainInOneHour;
        } else {
          tMinus = localizations.rainInHours(end);
        }
      } else if (closest < 1) {
        tMinus = localizations.rainExpectedInOneHour;
      } else {
        tMinus = localizations.rainExpectedInHours(closest);
      }
    }

    sum = max(sum, 0.1); //if there is rain then it shouldn't write 0

    return Wapi15MinutePrecip(
      t_minus: tMinus,
      precip_sum: unit_coversion(sum, settings['Precipitation']!),
      precips: precips,
    );
  }
}

Future<WeatherData> WapiGetWeatherData(
  double lat,
  double lng,
  String realLoc,
  Map<String, String> settings,
  String placeName,
  AppLocalizations localizations,
) async {
  final wapi = await WapiMakeRequest('$lat,$lng', realLoc);

  final wapiBody = wapi[0] as Map<String, dynamic>;
  final fetchDatetime = wapi[1] as DateTime;
  final isonline = wapi[2] as bool;

  final lastKnowTime = DateTime.parse(
    wapiBody['location']['localtime'] as String,
  );
  //DateTime lastKnowTime = await WapiGetLocalTime(lat, lng);

  //this gives us the time passed since last fetch, this is all basically for offline mode
  final realTimeOffset = DateTime.now().difference(fetchDatetime);

  //now we just need to apply this time offset to get the real current time
  final localtime = lastKnowTime.add(realTimeOffset);

  //get hour diff
  final approximateLocal = DateTime(
    localtime.year,
    localtime.month,
    localtime.day,
    localtime.hour,
  );
  final start =
      approximateLocal
          .difference(
            DateTime(lastKnowTime.year, lastKnowTime.month, lastKnowTime.day),
          )
          .inHours %
      24;

  //get day diff
  final dayDif = DateTime(localtime.year, localtime.month, localtime.day)
      .difference(
        DateTime(lastKnowTime.year, lastKnowTime.month, lastKnowTime.day),
      )
      .inDays;

  //make sure that there is data left
  if (dayDif >= (wapiBody['forecast']['forecastday'].length as int)) {
    throw const SocketException('Cached data expired');
  }

  //remove outdated days
  wapiBody['forecast']['forecastday'] = wapiBody['forecast']['forecastday']
      .sublist(dayDif);

  //int epoch = wapi_body["location"]["localtime_epoch"];
  final sunstatus = WapiSunstatus.fromJson(
    wapiBody,
    settings,
    DateTime(
      localtime.year,
      localtime.month,
      localtime.day,
      localtime.hour,
      localtime.minute,
    ),
  );

  final days = <WapiDay>[];
  final hourly72 = <dynamic>[];

  for (
    var n = 0;
    n < (wapiBody['forecast']['forecastday'].length as int);
    n++
  ) {
    final day = WapiDay.fromJson(
      wapiBody['forecast']['forecastday'][n] as Map<String, dynamic>,
      n,
      settings,
      approximateLocal,
      localizations,
    );
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

  return WeatherData(
    place: placeName,
    settings: settings,
    provider: 'weatherapi.com',
    real_loc: realLoc,
    lat: lat,
    lng: lng,
    hourly72: hourly72,
    current: await WapiCurrent.fromJson(
      wapiBody['forecast']['forecastday'][0] as Map<String, dynamic>,
      settings,
      realLoc,
      lat,
      lng,
      start,
      localizations,
    ),
    days: days,
    sunstatus: sunstatus,
    aqi: WapiAqi.fromJson(wapiBody),
    radar: await RainviewerRadar.getData(),
    dailyMinMaxTemp: omGetMaxMinTempForDaily(days),
    fetch_datetime: fetchDatetime,
    updatedTime: DateTime.now(),
    localtime: '${localtime.hour}:${localtime.minute}',
    minutely_15_precip: Wapi15MinutePrecip.fromJson(
      wapiBody,
      settings,
      0,
      start,
      localizations,
    ),
    alerts: getWapiAlerts(wapiBody, localizations),
    isonline: isonline,
  );
}

Future<dynamic> wapiGetCurrentResponse(
  Map<String, String> settings,
  String placeName,
  double lat,
  double lon,
) async {
  final params = {
    'key': wapi_Key,
    'q': '$lat, $lon',
    'aqi': 'no',
    'alerts': 'no',
  };
  final url = Uri.https('api.weatherapi.com', 'v1/current.json', params);

  final response = (await http.get(url)).body;

  return jsonDecode(response);
}

Future<LightCurrentWeatherData> wapiGetLightCurrentData(
  Map<String, String> settings,
  String placeName,
  double lat,
  double lon,
) async {
  final item = await wapiGetCurrentResponse(settings, placeName, lat, lon);

  final now = DateTime.now();

  return LightCurrentWeatherData(
    condition: textCorrection(
      item['current']['condition']['code'],
      item['current']['is_day'] as int,
      false,
      null,
    ),
    place: placeName,
    temp: unit_coversion(
      item['current']['temp_c'] as double,
      settings['Temperature']!,
    ).round(),
    updatedTime: "${now.hour}:${now.minute.toString().padLeft(2, "0")}",
    dateString: getDateStringFromLocalTime(now),
  );
}

Future<LightWindData> wapiGetLightWindData(
  Map<String, String> settings,
  String placeName,
  double lat,
  double lon,
) async {
  final item = await wapiGetCurrentResponse(settings, placeName, lat, lon);

  return LightWindData(
    windDirAngle: item['current']['wind_degree'] as int,
    windSpeed: unit_coversion(
      item['current']['wind_kph'] as double,
      settings['Wind']!,
    ).round(),
    windUnit: settings['Wind']!,
  );
}

Future<LightHourlyForecastData> wapiGetLightHourlyData(
  Map<String, String> settings,
  String placeName,
  double lat,
  double lon,
) async {
  final params = {
    'key': wapi_Key,
    'q': '$lat, $lon',
    'aqi': 'no',
    'days': '1',
    'alerts': 'no',
  };
  final url = Uri.https('api.weatherapi.com', 'v1/forecast.json', params);

  final response = (await http.get(url)).body;

  final item = jsonDecode(response);

  final hourlyConditions = <String>[];
  final hourlyTemps = <int>[];
  final hourlyNames = <String>[];

  final now = DateTime.now();

  for (
    var i = 0;
    i < (item['forecast']['forecastday'][0]['hour'].length as int);
    i++
  ) {
    final hour = item['forecast']['forecastday'][0]['hour'][i];

    final d = DateTime.parse(hour['time'] as String);

    if (d.hour % 6 == 0) {
      hourlyConditions.add(
        textCorrection(
          hour['condition']['code'],
          hour['is_day'] as int,
          false,
          null,
        ),
      );
      hourlyTemps.add(
        unit_coversion(
          hour['temp_c'] as double,
          settings['Temperature']!,
        ).round(),
      );
      hourlyNames.add('${d.hour}h');
    }
  }

  print(('wapi hourlytemp', hourlyTemps));

  return LightHourlyForecastData(
    place: placeName,
    currentCondition: textCorrection(
      item['current']['condition']['code'],
      item['current']['is_day'] as int,
      false,
      null,
    ),
    currentTemp: unit_coversion(
      item['current']['temp_c'] as double,
      settings['Temperature']!,
    ).round(),
    updatedTime: "${now.hour}:${now.minute.toString().padLeft(2, "0")}",
    //i can't sync lists to widgets so i need to encode and then decode them
    hourlyConditions: jsonEncode(hourlyConditions),
    hourlyNames: jsonEncode(hourlyNames),
    hourlyTemps: jsonEncode(hourlyTemps),
  );
}
