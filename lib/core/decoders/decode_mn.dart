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
import 'package:overmorrow/ui_helper.dart';
import 'package:overmorrow/weather_refact.dart';

String metNTextCorrection(
  String text,
  bool shouldTranslate,
  AppLocalizations? localizations,
) {
  var p = metNWeatherToText[text] ?? 'Clear Sky';
  if (shouldTranslate) {
    p = conditionTranslation(p, localizations!) ?? 'TranslationErr';
  }
  return p;
}

int metNCalculateHourDif(DateTime timeThere) {
  final now = DateTime.now().toUtc();

  return now.hour - timeThere.hour;
}

Duration metNCalculateTimeOffset(DateTime timeThere) {
  final now = DateTime.now().toUtc();
  return now.difference(timeThere);
}

int metNcalculateFeelsLike(double t, double r, double v) {
  //unfortunately met norway has no feels like temperatures, so i have to calculate it myself based on:
  //temperature, relative humidity, and wind speed
  // https://meteor.geol.iastate.edu/~ckarsten/bufkit/apparent_temperature.html

  if (t >= 24) {
    t = (t * 1.8) + 32;

    final heatIndex =
        -42.379 +
        (2.04901523 * t) +
        (10.14333127 * r) -
        (0.22475541 * t * r) -
        (0.00683783 * t * t) -
        (0.05481717 * r * r) +
        (0.00122874 * t * t * r) +
        (0.00085282 * t * r * r) -
        (0.00000199 * t * t * r * r);

    return ((heatIndex - 32) / 1.8).round();
  } else if (t <= 13) {
    t = (t * 1.8) + 32;

    final windChill =
        35.74 +
        (0.6215 * t) -
        (35.75 * pow(v, 0.16)) +
        (0.4275 * t * pow(v, 0.16));

    return ((windChill - 32) / 1.8).round();
  } else {
    return t.round();
  }
}

String metNGetName(
  int index,
  Map<String, String> settings,
  Map<String, dynamic> item,
  int start,
  int hourDif,
  AppLocalizations localizations,
) {
  final x =
      item['properties']['timeseries'][start]['time'].split('T')[0] as String;
  final hour =
      item['properties']['timeseries'][start]['time']
              .split('T')[1]
              .split(':')[0]
          as String;
  final z = x.split('-');
  final timeBefore = DateTime(
    int.parse(z[0]),
    int.parse(z[1]),
    int.parse(z[2]),
    int.parse(hour),
  );
  final time = timeBefore.add(-Duration(hours: hourDif));
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

String metNBackdropCorrection(String text) {
  return textBackground[text] ?? 'clear_sky3.jpg';
}

Color metNBackColorCorrection(String text) {
  return textBackColor[text] ?? kBlack;
}

Color metNAccentColorCorrection(String text) {
  return accentColors[text] ?? kWhite;
}

List<Color> metNContentColorCorrection(String text) {
  return textFontColor[text] ?? [kWhite, kWhite];
}

IconData metNIconCorrection(String text) {
  return textMaterialIcon[text] ?? OvermorrowWeatherIcons3.clear_sky;
}

String metNTimeCorrect(String date, int hourDif) {
  final realtime = date.split('T')[1];
  final realhour = realtime.split(':')[0];
  final num = (int.parse(realhour) - hourDif) % 24;
  if (num == 0) {
    return '12am';
  } else if (num < 12) {
    return '${num}am';
  } else if (num == 12) {
    return '12pm';
  }
  return '${num - 12}pm';
}

String metN24HourTime(String date, int hourDif) {
  final realtime = date.split('T')[1];
  final realhour = realtime.split(':')[0];
  final num = (int.parse(realhour) - hourDif) % 24;
  final hour = num.toString().padLeft(2, '0');
  final minute = realtime.split(':')[1].padLeft(2, '0');
  return '$hour:$minute';
}

/*Future<DateTime> MetNGetLocalTime(lat, lng) async {
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

Future<List<dynamic>> etNMakeRequest(
  double lat,
  double lng,
  String realLoc,
) async {
  final mnParams = {
    'lat': lat.toString(),
    'lon': lng.toString(),
    'altitude': '100',
  };

  final headers = {
    'User-Agent': 'Overmorrow weather (com.marotidev.overmorrow)',
  };
  final mnUrl = Uri.https(
    'api.met.no',
    'weatherapi/locationforecast/2.0/complete',
    mnParams,
  );

  //var mnFile = await cacheManager2.getSingleFile(mnUrl.toString(), key: "$real_loc, met.no", headers: headers).timeout(const Duration(seconds: 6));
  final mnFile = await XCustomCacheManager.fetchData(
    mnUrl.toString(),
    '$realLoc, met.no',
    headers: headers,
  );

  final mnResponse = (await mnFile[0].readAsString()) as String;
  final isonline = mnFile[1] as bool;

  final mnData = jsonDecode(mnResponse);

  final fetchDatetime = (await mnFile[0].lastModified()) as DateTime;
  return [mnData, fetchDatetime, isonline];
}

class MetNCurrent extends AbstractCurrent {
  const MetNCurrent({
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

  static Future<MetNCurrent> fromJson(
    Map<String, dynamic> item,
    Map<String, String> settings,
    String realLoc,
    double lat,
    double lng,
    AppLocalizations localizations,
  ) async {
    final currentCondition = metNTextCorrection(
      item['properties']['timeseries'][0]['data']['next_1_hours']['summary']['symbol_code']
          as String,
      false,
      localizations,
    );

    final it = item['properties']['timeseries'][0]['data'];

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

    return MetNCurrent(
      imageService: imageService,
      palette: colorPalette.palette,
      colorPop: colorPalette.colorPop,
      descColor: colorPalette.descColor,
      text: metNTextCorrection(
        it['next_1_hours']['summary']['symbol_code'] as String,
        true,
        localizations,
      ),
      precip: double.parse(
        unit_coversion(
          it['next_1_hours']['details']['precipitation_amount'] as double,
          settings['Precipitation']!,
        ).toStringAsFixed(1),
      ),
      temp: unit_coversion(
        it['instant']['details']['air_temperature'] as double,
        settings['Temperature']!,
      ).round(),
      humidity: (it['instant']['details']['relative_humidity'] as double)
          .round(),
      wind: unit_coversion(
        it['instant']['details']['wind_speed'] * 3.6 as double,
        settings['Wind']!,
      ).round(),
      uv: (it['instant']['details']['ultraviolet_index_clear_sky'] as double)
          .round(),
      feels_like: metNcalculateFeelsLike(
        it['instant']['details']['air_temperature'] as double,
        it['instant']['details']['relative_humidity'] as double,
        (it['instant']['details']['wind_speed'] as double) * 3.6,
      ),
      wind_dir: (it['instant']['details']['wind_from_direction'] as double)
          .round(),
    );
  }
}

class MetNDay extends AbstractDay {
  const MetNDay({
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

  static MetNDay fromJson(
    Map<String, dynamic> item,
    Map<String, String> settings,
    int start,
    int end,
    int index,
    int hourDif,
    AppLocalizations localizations,
  ) {
    final temperatures = <int>[];
    final rawTemps = <double>[];
    final windspeeds = <double>[];
    final winddirs = <int>[];
    final precipMm = <double>[];
    final precip = <double>[];
    final uvs = <int>[];

    var precipProb = -10;

    final oneSummary = <int>[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    const weatherNames = [
      'Clear Night',
      'Partly Cloudy',
      'Clear Sky',
      'Overcast',
      'Haze',
      'Rain',
      'Sleet',
      'Drizzle',
      'Thunderstorm',
      'Heavy Snow',
      'Fog',
      'Snow',
      'Heavy Rain',
      'Cloudy Night',
    ];

    final hours = <MetNHour>[];

    for (var n = start; n < end; n++) {
      final hour = MetNHour.fromJson(
        item['properties']['timeseries'][n] as Map<String, dynamic>,
        settings,
        hourDif,
        localizations,
      );
      temperatures.add(hour.temp);
      rawTemps.add(hour.raw_temp);
      windspeeds.add(hour.wind);
      winddirs.add(hour.wind_dir);
      uvs.add(hour.uv);

      precipMm.add(hour.raw_precip);
      precip.add(hour.precip);

      final index = weatherNames.indexOf(hour.rawText);
      final value = weatherConditionBiassTable[hour.rawText] ?? 0;
      oneSummary[index] += value;

      if (hour.precip_prob > precipProb) {
        precipProb = hour.precip_prob;
      }
      hours.add(hour);
    }

    final largestValue = oneSummary.reduce(max);
    final bIndex = oneSummary.indexOf(largestValue);

    return MetNDay(
      mm_precip: precipMm.reduce((a, b) => a + b),
      precip_prob: precipProb,
      minTemp: temperatures.reduce(min),
      maxTemp: temperatures.reduce(max),
      rawMinTemp: rawTemps.reduce(min),
      rawMaxTemp: rawTemps.reduce(max),
      hourly: hours,
      hourly_for_precip: hours,
      total_precip: double.parse(
        precip.reduce((a, b) => a + b).toStringAsFixed(1),
      ),
      windspeed: (windspeeds.reduce((a, b) => a + b) / windspeeds.length)
          .round(),
      name: metNGetName(index, settings, item, start, hourDif, localizations),
      text:
          conditionTranslation(weatherNames[bIndex], localizations) ??
          'TranslationErr',
      icon: metNIconCorrection(weatherNames[bIndex]),
      wind_dir: (windspeeds.reduce((a, b) => a + b) / windspeeds.length)
          .round(),
      uv: uvs.reduce(max),
    );
  }
}

class MetNHour extends AbstractHour {
  const MetNHour({
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

  static MetNHour fromJson(
    Map<String, dynamic> item,
    Map<String, String> settings,
    int hourDif,
    AppLocalizations localizations,
  ) {
    final nextHours =
        item['data']['next_1_hours'] ?? item['data']['next_6_hours'];

    return MetNHour(
      wind_gusts: 0,
      rawText: metNTextCorrection(
        nextHours['summary']['symbol_code'] as String,
        false,
        localizations,
      ),
      text: metNTextCorrection(
        nextHours['summary']['symbol_code'] as String,
        true,
        localizations,
      ),
      temp: unit_coversion(
        item['data']['instant']['details']['air_temperature'] as double,
        settings['Temperature']!,
      ).round(),
      precip: unit_coversion(
        nextHours['details']['precipitation_amount'] as double,
        settings['Precipitation']!,
      ),
      precip_prob:
          (nextHours['details']['probability_of_precipitation'] as double? ?? 0)
              .round(),
      icon: metNIconCorrection(
        metNTextCorrection(
          nextHours['summary']['symbol_code'] as String,
          false,
          localizations,
        ),
      ),
      time: settings['Time mode'] == '24 hour'
          ? metN24HourTime(item['time'] as String, hourDif)
          : metNTimeCorrect(item['time'] as String, hourDif),
      wind: double.parse(
        unit_coversion(
          (item['data']['instant']['details']['wind_speed'] as double) * 3.6,
          settings['Wind']!,
        ).toStringAsFixed(1),
      ),
      wind_dir:
          (item['data']['instant']['details']['wind_from_direction'] as double)
              .round(),
      uv:
          (item['data']['instant']['details']['ultraviolet_index_clear_sky']
                      as double? ??
                  0)
              .round(),
      raw_wind:
          (item['data']['instant']['details']['wind_speed'] as double) * 3.6,
      raw_precip: nextHours['details']['precipitation_amount'] as double,
      raw_temp: item['data']['instant']['details']['air_temperature'] as double,
    );
  }
}

class MetNSunstatus extends AbstractSunstatus {
  const MetNSunstatus({
    required super.sunrise,
    required super.sunstatus,
    required super.sunset,
    required super.absoluteSunriseSunset,
  });

  static Future<MetNSunstatus> fromJson(
    Map<String, dynamic> item,
    Map<String, String> settings,
    double lat,
    double lng,
    int dif,
    DateTime timeThere,
    DateTime fetchDate,
  ) async {
    final mnParams = {
      'lat': lat.toString(),
      'lon': lng.toString(),
      'date':
          "${fetchDate.year}-${fetchDate.month.toString().padLeft(2, "0")}-${fetchDate.day.toString().padLeft(2, "0")}",
    };
    final headers = {
      'User-Agent': 'Overmorrow weather (com.marotidev.overmorrow)',
    };
    final mnUrl = Uri.https(
      'api.met.no',
      'weatherapi/sunrise/3.0/sun',
      mnParams,
    );

    //var mnFile = await cacheManager2.getSingleFile(mnUrl.toString(), key: "$lat, $lng, sunstatus met.no", headers: headers).timeout(const Duration(seconds: 6));
    final mnFile = await XCustomCacheManager.fetchData(
      mnUrl.toString(),
      '$lat, $lng met.no aqi',
      headers: headers,
    );
    final mnResponse = (await mnFile[0].readAsString()) as String;
    final item = jsonDecode(mnResponse);

    final sunriseString =
        item['properties']['sunrise']['time']
                .split('T')[1]
                .split('+')[0]
                .split(':')
            as List<String>;
    final sunrise = timeThere.copyWith(
      hour: (int.parse(sunriseString[0]) - dif) % 24,
      minute: int.parse(sunriseString[1]),
    );

    final sunsetString =
        item['properties']['sunset']['time']
                .split('T')[1]
                .split('+')[0]
                .split(':')
            as List<String>;
    final sunset = timeThere.copyWith(
      hour: (int.parse(sunsetString[0]) - dif) % 24,
      minute: int.parse(sunsetString[1]),
    );

    return MetNSunstatus(
      sunrise: settings['Time mode'] == '24 hour'
          ? "${sunrise.hour.toString().padLeft(2, "0")}:${sunrise.minute.toString().padLeft(2, "0")}"
          : OMamPmTime('T${sunrise.hour}:${sunrise.minute}'),
      sunset: settings['Time mode'] == '24 hour'
          ? "${sunset.hour.toString().padLeft(2, "0")}:${sunset.minute.toString().padLeft(2, "0")}"
          : OMamPmTime('T${sunset.hour}:${sunset.minute}'),
      absoluteSunriseSunset:
          '${sunrise.hour}:${sunrise.minute}/${sunset.hour}:${sunset.minute}',
      sunstatus: min(
        max(
          timeThere.difference(sunrise).inMinutes /
              sunset.difference(sunrise).inMinutes,
          0,
        ),
        1,
      ),
    );
  }
}

class MetN15MinutePrecip extends Abstract15MinPrecip {
  //met norway doesn't actaully have 15 minute forecast, but i figured i could just use the
  //hourly data and just use some smoothing between the hours to emulate the 15 minutes
  //still better than not having it
  const MetN15MinutePrecip({
    required super.t_minus,
    required super.precip_sum,
    required super.precips,
  });

  static MetN15MinutePrecip fromJson(
    Map<String, dynamic> item,
    Map<String, String> settings,
    AppLocalizations localizations,
  ) {
    var closest = 100;
    var end = -1;
    double sum = 0;

    final precips = <double>[];
    final hourly = <double>[];

    for (var i = 0; i < 6; i++) {
      final x = double.parse(
        item['properties']['timeseries'][i]['data']['next_1_hours']['details']['precipitation_amount']
                .toStringAsFixed(1)
            as String,
      );

      if (x > 0.0) {
        if (closest == 100) {
          closest = i + 1;
        }
        if (i >= end) {
          end = i + 1;
        }
      }

      hourly.add(x);
    }

    //smooth the hours into 15 minute segments

    for (var i = 0; i < hourly.length - 1; i++) {
      final now = hourly[i];
      final next = hourly[i + 1];

      final dif = next - now;
      for (double x = 0; x <= 1; x += 0.25) {
        final g =
            (now + dif * x) /
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

    return MetN15MinutePrecip(
      t_minus: tMinus,
      precip_sum: unit_coversion(sum, settings['Precipitation']!),
      precips: precips,
    );
  }
}

Future<WeatherData> metNGetWeatherData(
  double lat,
  double lng,
  String realLoc,
  Map<String, String> settings,
  String placeName,
  AppLocalizations localizations,
) async {
  final mn = await etNMakeRequest(lat, lng, realLoc);
  final mnBody = mn[0] as Map<String, dynamic>;

  //DateTime lastKnowTime = await MetNGetLocalTime(lat, lng);
  final lastKnowTime = DateTime.now();
  final fetchDatetime = mn[1] as DateTime;

  //this gives us the time passed since last fetch, this is all basically for offline mode
  final realTimeOffset = DateTime.now().difference(fetchDatetime);

  //now we just need to apply this time offset to get the real current time
  final localTime = lastKnowTime.add(realTimeOffset);

  final hourDif = metNCalculateHourDif(localTime);

  final isonline = mn[2] as bool;

  //I have to use the fetch date because on offline it wouldn't work because it changes
  final sunstatus = await MetNSunstatus.fromJson(
    mnBody,
    settings,
    lat,
    lng,
    hourDif,
    localTime,
    fetchDatetime,
  );

  //removes the outdated hours
  final start = localTime
      .difference(
        DateTime(
          lastKnowTime.year,
          lastKnowTime.month,
          lastKnowTime.day,
          lastKnowTime.hour,
        ),
      )
      .inHours;

  //make sure that there is data left
  if (start >= (mnBody['properties']['timeseries'].length as int)) {
    throw const SocketException('Cached data expired');
  }

  //remove outdated hours
  mnBody['properties']['timeseries'] = mnBody['properties']['timeseries']
      .sublist(start);

  final days = <MetNDay>[];
  final hourly72 = <dynamic>[];

  var begin = 0;
  var index = 0;

  var previousHour = 0;
  for (var n = 0; n < (mnBody['properties']['timeseries'].length as int); n++) {
    final hour =
        (int.parse(
              mnBody['properties']['timeseries'][n]['time']
                      .split('T')[1]
                      .split(':')[0]
                  as String,
            ) -
            hourDif) %
        24;
    if (n > 0 && hour - previousHour < 1) {
      final day = MetNDay.fromJson(
        mnBody,
        settings,
        begin,
        n,
        index,
        hourDif,
        localizations,
      );
      days.add(day);

      if (hourly72.length < 72) {
        if (begin != 0) {
          hourly72.add(day.name);
        }
        for (var z = 0; z < day.hourly.length; z++) {
          if (hourly72.length < 72) {
            hourly72.add(day.hourly[z]);
          }
        }
      }

      index += 1;
      begin = n;
    }
    previousHour = hour;
  }

  return WeatherData(
    radar: await RainviewerRadar.getData(),
    aqi: await OMAqi.fromJson(lat, lng, settings, localizations),
    sunstatus: sunstatus,
    alerts: [],
    minutely_15_precip: MetN15MinutePrecip.fromJson(
      mnBody,
      settings,
      localizations,
    ),
    current: await MetNCurrent.fromJson(
      mnBody,
      settings,
      realLoc,
      lat,
      lng,
      localizations,
    ),
    days: days,
    dailyMinMaxTemp: omGetMaxMinTempForDaily(days),
    hourly72: hourly72,
    lat: lat,
    lng: lng,
    place: placeName,
    settings: settings,
    provider: 'met norway',
    real_loc: realLoc,
    fetch_datetime: fetchDatetime,
    updatedTime: DateTime.now(),
    localtime: '${localTime.hour}:${localTime.minute}',
    isonline: isonline,
  );
}

Future<dynamic> metNGetLightResponse(
  settings,
  String placeName,
  double lat,
  double lon,
) async {
  final params = {
    'lat': lat.toString(),
    'lon': lon.toString(),
    'altitude': '100',
  };

  final headers = {
    'User-Agent': 'Overmorrow weather (com.marotidev.overmorrow)',
  };
  final url = Uri.https(
    'api.met.no',
    'weatherapi/locationforecast/2.0/compact',
    params,
  );

  final response = (await http.get(url, headers: headers)).body;

  return jsonDecode(response);
}

Future<LightCurrentWeatherData> metNGetLightCurrentData(
  Map<String, String> settings,
  String placeName,
  double lat,
  double lon,
) async {
  final item = await metNGetLightResponse(settings, placeName, lat, lon);

  final now = DateTime.now();

  return LightCurrentWeatherData(
    condition: metNTextCorrection(
      item['properties']['timeseries'][0]['data']['next_1_hours']['summary']['symbol_code']
          as String,
      false,
      null,
    ),
    place: placeName,
    temp: unit_coversion(
      item['properties']['timeseries'][0]['data']['instant']['details']['air_temperature']
          as double,
      settings['Temperature']!,
    ).round(),
    updatedTime: "${now.hour}:${now.minute.toString().padLeft(2, "0")}",
    dateString: getDateStringFromLocalTime(now),
  );
}

Future<LightWindData> metNGetLightWindData(
  Map<String, String> settings,
  String placeName,
  double lat,
  double lon,
) async {
  final item = await metNGetLightResponse(settings, placeName, lat, lon);

  return LightWindData(
    windDirAngle:
        (item['properties']['timeseries'][0]['data']['instant']['details']['wind_from_direction']
                as double)
            .round(),
    windSpeed: unit_coversion(
      (item['properties']['timeseries'][0]['data']['instant']['details']['wind_speed']
              as double) *
          3.6,
      settings['Wind']!,
    ).round(),
    windUnit: settings['Wind']!,
  );
}

Future<LightHourlyForecastData> metNGetLightHourlyData(
  Map<String, String> settings,
  String placeName,
  double lat,
  double lon,
) async {
  final item = await metNGetLightResponse(settings, placeName, lat, lon);

  final hourlyConditions = <String>[];
  final hourlyTemps = <int>[];
  final hourlyNames = <String>[];

  final now = DateTime.now();

  for (
    var i = 0;
    i < min(item['properties']['timeseries'].length as int, 23);
    i++
  ) {
    final hour = item['properties']['timeseries'][i];

    final d = DateTime.parse(hour['time'] as String);

    if (d.hour % 6 == 0) {
      hourlyConditions.add(
        metNTextCorrection(
          hour['data']['next_1_hours']['summary']['symbol_code'] as String,
          false,
          null,
        ),
      );
      hourlyTemps.add(
        unit_coversion(
          hour['data']['instant']['details']['air_temperature'] as double,
          settings['Temperature']!,
        ).round(),
      );
      hourlyNames.add('${d.hour}h');
    }
  }

  return LightHourlyForecastData(
    place: placeName,
    currentCondition: metNTextCorrection(
      item['properties']['timeseries'][0]['data']['next_1_hours']['summary']['symbol_code']
          as String,
      false,
      null,
    ),
    currentTemp: unit_coversion(
      item['properties']['timeseries'][0]['data']['instant']['details']['air_temperature']
          as double,
      settings['Temperature']!,
    ).round(),
    updatedTime: "${now.hour}:${now.minute.toString().padLeft(2, "0")}",
    //i can't sync lists to widgets so i need to encode and then decode them
    hourlyConditions: jsonEncode(hourlyConditions),
    hourlyNames: jsonEncode(hourlyNames),
    hourlyTemps: jsonEncode(hourlyTemps),
  );
}
