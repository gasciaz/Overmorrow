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
import 'package:overmorrow/caching.dart';
import 'package:overmorrow/decoders/decode_OM.dart';
import 'package:overmorrow/decoders/decode_RV.dart';
import 'package:overmorrow/decoders/decode_wapi.dart';
import 'package:overmorrow/decoders/weather_data.dart';
import 'package:overmorrow/l10n/app_localizations.dart';
import 'package:overmorrow/services/color_service.dart';
import 'package:overmorrow/services/image_service.dart';
import 'package:overmorrow/ui_helper.dart';
import 'package:overmorrow/weather_refact.dart';

String metNTextCorrection(String text, bool shouldTranslate, localizations) {
  var p = metNWeatherToText[text] ?? 'Clear Sky';
  if (shouldTranslate) {
    p = conditionTranslation(p, localizations) ?? 'TranslationErr';
  }
  return p;
}

int metNCalculateHourDif(DateTime timeThere) {
  final now = DateTime.now().toUtc();

  return now.hour - timeThere.hour;
}

Duration metNCalculateTimeOffset(DateTime timeThere) {
  final var now = DateTime.now().toUtc();
  return now.difference(timeThere);
}

int metNcalculateFeelsLike(double t, double r, double v) {
  //unfortunately met norway has no feels like temperatures, so i have to calculate it myself based on:
  //temperature, relative humidity, and wind speed
  // https://meteor.geol.iastate.edu/~ckarsten/bufkit/apparent_temperature.html

  if (t >= 24) {
    t = (t * 1.8) + 32;

    final var heatIndex = -42.379 +
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

    final windChill = 35.74 +
        (0.6215 * t) -
        (35.75 * pow(v, 0.16)) +
        (0.4275 * t * pow(v, 0.16));

    return ((windChill - 32) / 1.8).round();
  } else {
    return t.round();
  }
}

String metNGetName(index, settings, item, start, hourDif, localizations) {
  final String x = item['properties']['timeseries'][start]['time'].split('T')[0];
  final String hour = item['properties']['timeseries'][start]['time']
      .split('T')[1]
      .split(':')[0];
  final var z = x.split('-');
  final timeBefore = DateTime(
      int.parse(z[0]), int.parse(z[1]), int.parse(z[2]), int.parse(hour));
  final var time = timeBefore.add(-Duration(hours: hourDif));
  final var weeks = <String>[
    localizations.mon,
    localizations.tue,
    localizations.wed,
    localizations.thu,
    localizations.fri,
    localizations.sat,
    localizations.sun
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
  return textBackColor[text] ?? BLACK;
}

Color metNAccentColorCorrection(String text) {
  return accentColors[text] ?? WHITE;
}

List<Color> metNContentColorCorrection(String text) {
  return textFontColor[text] ?? [WHITE, WHITE];
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

Future<List<dynamic>> MetNMakeRequest(
    double lat, double lng, String realLoc) async {
  final MnParams = {
    'lat': lat.toString(),
    'lon': lng.toString(),
    'altitude': '100',
  };

  final headers = {
    'User-Agent': 'Overmorrow weather (com.marotidev.overmorrow)'
  };
  final MnUrl = Uri.https(
      'api.met.no', 'weatherapi/locationforecast/2.0/complete', MnParams);

  //var MnFile = await cacheManager2.getSingleFile(MnUrl.toString(), key: "$real_loc, met.no", headers: headers).timeout(const Duration(seconds: 6));
  final MnFile = await XCustomCacheManager.fetchData(
      MnUrl.toString(), '$realLoc, met.no',
      headers: headers);

  final MnResponse = await MnFile[0].readAsString();
  final bool isonline = MnFile[1];

  final MnData = jsonDecode(MnResponse);

  final DateTime fetchDatetime = await MnFile[0].lastModified();
  return [MnData, fetchDatetime, isonline];
}

class MetNCurrent {
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

  const MetNCurrent({
    required this.precip,
    required this.humidity,
    required this.feels_like,
    required this.temp,
    required this.text,
    required this.uv,
    required this.wind,
    required this.wind_dir,
    required this.imageService,
    required this.palette,
    required this.colorPop,
    required this.descColor,
  });

  static Future<MetNCurrent> fromJson(
      item, settings, realLoc, lat, lng, localizations) async {
    final currentCondition = metNTextCorrection(
        item['properties']['timeseries'][0]['data']['next_1_hours']['summary']
            ['symbol_code'],
        false,
        localizations);

    final it = item['properties']['timeseries'][0]['data'];

    final imageService = await ImageService.getImageService(
        currentCondition, realLoc, settings);
    final colorPalette = await ColorPalette.getColorPalette(
        imageService.image, settings['Color mode'], settings);

    return MetNCurrent(
      imageService: imageService,
      palette: colorPalette.palette,
      colorPop: colorPalette.colorPop,
      descColor: colorPalette.descColor,
      text: metNTextCorrection(
          it['next_1_hours']['summary']['symbol_code'], true, localizations),
      precip: double.parse(unit_coversion(
              it['next_1_hours']['details']['precipitation_amount'],
              settings['Precipitation'])
          .toStringAsFixed(1)),
      temp: unit_coversion(it['instant']['details']['air_temperature'],
              settings['Temperature'])
          .round(),
      humidity: it['instant']['details']['relative_humidity'].round(),
      wind: unit_coversion(
              it['instant']['details']['wind_speed'] * 3.6, settings['Wind'])
          .round(),
      uv: it['instant']['details']['ultraviolet_index_clear_sky'].round(),
      feels_like: metNcalculateFeelsLike(
          it['instant']['details']['air_temperature'],
          it['instant']['details']['relative_humidity'],
          it['instant']['details']['wind_speed'] * 3.6),
      wind_dir: it['instant']['details']['wind_from_direction'].round(),
    );
  }
}

class MetNDay {
  final String text;

  final IconData icon;

  final String name;

  final int minTemp;
  final int maxTemp;
  final double rawMinTemp; //the unconverted numbers used for charts
  final double rawMaxTemp;

  final List<MetNHour> hourly;
  final List<MetNHour> hourly_for_precip;

  final int precip_prob;
  final double total_precip;

  final int windspeed;
  final int wind_dir;

  final double mm_precip;
  final int uv;

  const MetNDay({
    required this.text,
    required this.icon,
    required this.name,
    required this.minTemp,
    required this.maxTemp,
    required this.rawMinTemp,
    required this.rawMaxTemp,
    required this.hourly,
    required this.precip_prob,
    required this.total_precip,
    required this.windspeed,
    required this.hourly_for_precip,
    required this.mm_precip,
    required this.uv,
    required this.wind_dir,
  });

  static MetNDay fromJson(
      item, settings, start, end, index, hourDif, localizations) {
    final var temperatures = <int>[];
    final var rawTemps = <double>[];
    final var windspeeds = <double>[];
    final winddirs = <int>[];
    final var precipMm = <double>[];
    final var precip = <double>[];
    final var uvs = <int>[];

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
      'Cloudy Night'
    ];

    final hours = <MetNHour>[];

    for (int n = start; n < end; n++) {
      final hour = MetNHour.fromJson(item['properties']['timeseries'][n],
          settings, hourDif, localizations);
      temperatures.add(hour.temp);
      rawTemps.add(hour.raw_temp);
      windspeeds.add(hour.wind);
      winddirs.add(hour.wind_dir);
      uvs.add(hour.uv);

      precipMm.add(hour.raw_precip);
      precip.add(hour.precip);

      final var index = weatherNames.indexOf(hour.rawText);
      final var value = weatherConditionBiassTable[hour.rawText] ?? 0;
      oneSummary[index] += value;

      if (hour.precip_prob > precipProb) {
        precipProb = hour.precip_prob;
      }
      hours.add(hour);
    }

    final largestValue = oneSummary.reduce(max);
    final var BIndex = oneSummary.indexOf(largestValue);

    return MetNDay(
        mm_precip: precipMm.reduce((a, b) => a + b),
        precip_prob: precipProb,
        minTemp: temperatures.reduce(min),
        maxTemp: temperatures.reduce(max),
        rawMinTemp: rawTemps.reduce(min),
        rawMaxTemp: rawTemps.reduce(max),
        hourly: hours,
        hourly_for_precip: hours,
        total_precip:
            double.parse(precip.reduce((a, b) => a + b).toStringAsFixed(1)),
        windspeed:
            (windspeeds.reduce((a, b) => a + b) / windspeeds.length).round(),
        name: metNGetName(index, settings, item, start, hourDif, localizations),
        text: conditionTranslation(weatherNames[BIndex], localizations) ??
            'TranslationErr',
        icon: metNIconCorrection(weatherNames[BIndex]),
        wind_dir:
            (windspeeds.reduce((a, b) => a + b) / windspeeds.length).round(),
        uv: uvs.reduce(max));
  }
}

class MetNHour {
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

  final rawText;

  const MetNHour({
    required this.temp,
    required this.time,
    required this.icon,
    required this.text,
    required this.precip,
    required this.wind,
    required this.raw_precip,
    required this.raw_temp,
    required this.raw_wind,
    required this.wind_dir,
    required this.wind_gusts,
    required this.uv,
    required this.precip_prob,
    required this.rawText,
  });

  static MetNHour fromJson(item, settings, hourDif, localizations) {
    final nextHours =
        item['data']['next_1_hours'] ?? item['data']['next_6_hours'];

    return MetNHour(
      wind_gusts: 0,
      rawText: metNTextCorrection(
          nextHours['summary']['symbol_code'], false, localizations),
      text: metNTextCorrection(
          nextHours['summary']['symbol_code'], true, localizations),
      temp: unit_coversion(
              item['data']['instant']['details']['air_temperature'],
              settings['Temperature'])
          .round(),
      precip: unit_coversion(nextHours['details']['precipitation_amount'],
          settings['Precipitation']),
      precip_prob:
          (nextHours['details']['probability_of_precipitation'] ?? 0).round(),
      icon: metNIconCorrection(
        metNTextCorrection(
            nextHours['summary']['symbol_code'], false, localizations),
      ),
      time: settings['Time mode'] == '24 hour'
          ? metN24HourTime(item['time'], hourDif)
          : metNTimeCorrect(item['time'], hourDif),
      wind: double.parse(unit_coversion(
              item['data']['instant']['details']['wind_speed'] * 3.6,
              settings['Wind'])
          .toStringAsFixed(1)),
      wind_dir:
          item['data']['instant']['details']['wind_from_direction'].round(),
      uv: (item['data']['instant']['details']['ultraviolet_index_clear_sky'] ??
              0)
          .round(),
      raw_wind: item['data']['instant']['details']['wind_speed'] * 3.6,
      raw_precip: nextHours['details']['precipitation_amount'],
      raw_temp: item['data']['instant']['details']['air_temperature'],
    );
  }
}

class MetNSunstatus {
  final String sunrise;
  final String sunset;
  final double sunstatus;
  final String absoluteSunriseSunset;

  const MetNSunstatus({
    required this.sunrise,
    required this.sunstatus,
    required this.sunset,
    required this.absoluteSunriseSunset,
  });

  static Future<MetNSunstatus> fromJson(item, settings, lat, lng, int dif,
      DateTime timeThere, DateTime fetchDate) async {
    final MnParams = {
      'lat': lat.toString(),
      'lon': lng.toString(),
      'date':
          "${fetchDate.year}-${fetchDate.month.toString().padLeft(2, "0")}-${fetchDate.day.toString().padLeft(2, "0")}",
    };
    final headers = {
      'User-Agent': 'Overmorrow weather (com.marotidev.overmorrow)'
    };
    final MnUrl =
        Uri.https('api.met.no', 'weatherapi/sunrise/3.0/sun', MnParams);

    //var MnFile = await cacheManager2.getSingleFile(MnUrl.toString(), key: "$lat, $lng, sunstatus met.no", headers: headers).timeout(const Duration(seconds: 6));
    final MnFile = await XCustomCacheManager.fetchData(
        MnUrl.toString(), '$lat, $lng met.no aqi',
        headers: headers);
    final MnResponse = await MnFile[0].readAsString();
    final item = jsonDecode(MnResponse);

    final List<String> sunriseString = item['properties']['sunrise']['time']
        .split('T')[1]
        .split('+')[0]
        .split(':');
    final sunrise = timeThere.copyWith(
      hour: (int.parse(sunriseString[0]) - dif) % 24,
      minute: int.parse(sunriseString[1]),
    );

    final List<String> sunsetString = item['properties']['sunset']['time']
        .split('T')[1]
        .split('+')[0]
        .split(':');
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
              0),
          1),
    );
  }
}

class MetN15MinutePrecip {
  //met norway doesn't actaully have 15 minute forecast, but i figured i could just use the
  //hourly data and just use some smoothing between the hours to emulate the 15 minutes
  //still better than not having it
  final String t_minus;
  final double precip_sum;
  final List<double> precips;

  const MetN15MinutePrecip({
    required this.t_minus,
    required this.precip_sum,
    required this.precips,
  });

  static MetN15MinutePrecip fromJson(
      item, settings, AppLocalizations localizations) {
    var closest = 100;
    var end = -1;
    double sum = 0;

    final precips = <double>[];
    final hourly = <double>[];

    for (var i = 0; i < 6; i++) {
      final x = double.parse(item['properties']['timeseries'][i]['data']
              ['next_1_hours']['details']['precipitation_amount']
          .toStringAsFixed(1));

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
        final g = (now + dif * x) /
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
      precip_sum: unit_coversion(sum, settings['Precipitation']),
      precips: precips,
    );
  }
}

Future<WeatherData> MetNGetWeatherData(
    lat, lng, realLoc, settings, placeName, AppLocalizations localizations) async {
  final Mn = await MetNMakeRequest(lat, lng, realLoc);
  final MnBody = Mn[0];

  //DateTime lastKnowTime = await MetNGetLocalTime(lat, lng);
  final var lastKnowTime = DateTime.now();
  final DateTime fetchDatetime = Mn[1];

  //this gives us the time passed since last fetch, this is all basically for offline mode
  final var realTimeOffset = DateTime.now().difference(fetchDatetime);

  //now we just need to apply this time offset to get the real current time
  final var localTime = lastKnowTime.add(realTimeOffset);

  final var hourDif = metNCalculateHourDif(localTime);

  final bool isonline = Mn[2];

  //I have to use the fetch date because on offline it wouldn't work because it changes
  final sunstatus = await MetNSunstatus.fromJson(
      MnBody, settings, lat, lng, hourDif, localTime, fetchDatetime);

  //removes the outdated hours
  final start = localTime
      .difference(DateTime(lastKnowTime.year, lastKnowTime.month,
          lastKnowTime.day, lastKnowTime.hour))
      .inHours;

  //make sure that there is data left
  if (start >= MnBody['properties']['timeseries'].length) {
    throw const SocketException('Cached data expired');
  }

  //remove outdated hours
  MnBody['properties']['timeseries'] =
      MnBody['properties']['timeseries'].sublist(start);

  final var days = <MetNDay>[];
  final var hourly72 = <dynamic>[];

  var begin = 0;
  var index = 0;

  var previousHour = 0;
  for (var n = 0; n < MnBody['properties']['timeseries'].length; n++) {
    final var hour = (int.parse(MnBody['properties']['timeseries'][n]['time']
                .split('T')[1]
                .split(':')[0]) -
            hourDif) %
        24;
    if (n > 0 && hour - previousHour < 1) {
      final var day = MetNDay.fromJson(
          MnBody, settings, begin, n, index, hourDif, localizations);
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
    minutely_15_precip:
        MetN15MinutePrecip.fromJson(MnBody, settings, localizations),
    current: await MetNCurrent.fromJson(
        MnBody, settings, realLoc, lat, lng, localizations),
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

Future<dynamic> metNGetLightResponse(settings, placeName, lat, lon) async {
  final params = {
    'lat': lat.toString(),
    'lon': lon.toString(),
    'altitude': '100',
  };

  final headers = {
    'User-Agent': 'Overmorrow weather (com.marotidev.overmorrow)'
  };
  final url = Uri.https(
      'api.met.no', 'weatherapi/locationforecast/2.0/compact', params);

  final response = (await http.get(url, headers: headers)).body;

  return jsonDecode(response);
}

Future<LightCurrentWeatherData> metNGetLightCurrentData(
    settings, placeName, lat, lon) async {
  final item = await metNGetLightResponse(settings, placeName, lat, lon);

  final now = DateTime.now();

  return LightCurrentWeatherData(
    condition: metNTextCorrection(
        item['properties']['timeseries'][0]['data']['next_1_hours']['summary']
            ['symbol_code'],
        false,
        null),
    place: placeName,
    temp: unit_coversion(
            item['properties']['timeseries'][0]['data']['instant']['details']
                ['air_temperature'],
            settings['Temperature'])
        .round(),
    updatedTime: "${now.hour}:${now.minute.toString().padLeft(2, "0")}",
    dateString: getDateStringFromLocalTime(now),
  );
}

Future<LightWindData> metNGetLightWindData(
    settings, placeName, lat, lon) async {
  final item = await metNGetLightResponse(settings, placeName, lat, lon);

  return LightWindData(
    windDirAngle: item['properties']['timeseries'][0]['data']['instant']
            ['details']['wind_from_direction']
        .round(),
    windSpeed: unit_coversion(
            item['properties']['timeseries'][0]['data']['instant']['details']
                    ['wind_speed'] *
                3.6,
            settings['Wind'])
        .round(),
    windUnit: settings['Wind'],
  );
}

Future<LightHourlyForecastData> metNGetLightHourlyData(
    settings, placeName, lat, lon) async {
  final item = await metNGetLightResponse(settings, placeName, lat, lon);

  final var hourlyConditions = <String>[];
  final var hourlyTemps = <int>[];
  final hourlyNames = <String>[];

  final now = DateTime.now();

  for (var i = 0; i < min(item['properties']['timeseries'].length, 23); i++) {
    final hour = item['properties']['timeseries'][i];

    final d = DateTime.parse(hour['time']);

    if (d.hour % 6 == 0) {
      hourlyConditions.add(metNTextCorrection(
          hour['data']['next_1_hours']['summary']['symbol_code'], false, null));
      hourlyTemps.add(
        unit_coversion(hour['data']['instant']['details']['air_temperature'],
                settings['Temperature'])
            .round(),
      );
      hourlyNames.add('${d.hour}h');
    }
  }

  return LightHourlyForecastData(
    place: placeName,
    currentCondition: metNTextCorrection(
        item['properties']['timeseries'][0]['data']['next_1_hours']['summary']
            ['symbol_code'],
        false,
        null),
    currentTemp: unit_coversion(
            item['properties']['timeseries'][0]['data']['instant']['details']
                ['air_temperature'],
            settings['Temperature'])
        .round(),
    updatedTime: "${now.hour}:${now.minute.toString().padLeft(2, "0")}",
    //i can't sync lists to widgets so i need to encode and then decode them
    hourlyConditions: jsonEncode(hourlyConditions),
    hourlyNames: jsonEncode(hourlyNames),
    hourlyTemps: jsonEncode(hourlyTemps),
  );
}
