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

import 'package:overmorrow/caching.dart';


class RainviewerRadar {
  final List<String> images;
  final List<String> times;
  final int real_hour;
  final int starting_index;

  const RainviewerRadar({
    required this.images,
    required this.times,
    required this.real_hour,
    required this.starting_index,
  });

  static Future<RainviewerRadar> getData() async {
    const url = 'https://api.rainviewer.com/public/weather-maps.json';

    final file = await XCustomCacheManager.fetchData(url, url);
    final response = await file[0].readAsString();
    final Map<String, dynamic> data = json.decode(response);

    final String host = data['host'];

    final images = <String>[];
    final times = <String>[];

    final past = data['radar']['past'];
    final future = data['radar']['nowcast'];

    for (final x in past) {
      final var time = DateTime.fromMillisecondsSinceEpoch(x['time'] * 1000);
      images.add(host + x['path']);
      times.add('${time.hour}h ${time.minute}m');
    }

    final realHour = int.parse(times[times.length - 1].split('h')[0]);
    final startingIndex = times.length - 1;

    for (final x in future) {
      final time = DateTime.fromMillisecondsSinceEpoch(x['time'] * 1000);
      images.add(host + x['path']);
      times.add('${time.hour}h ${time.minute}m');
    }

    return RainviewerRadar(images: images, times: times, real_hour: realHour, starting_index: startingIndex);
  }
}

