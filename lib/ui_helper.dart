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

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:overmorrow/core/core.dart';
import 'package:overmorrow/main.dart';
import 'package:overmorrow/search_screens.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kWhite = Color(0xffFFFFFF);
const kBlack = Color(0xff000000);

double getFontSize(String set) {
  var x = Platform.isLinux ? 0.85 : 0.92;

  if (set == 'small') {
    x = 0.85 * x;
  } else if (set == 'very small') {
    x = 0.75 * x;
  } else if (set == 'big') {
    x = 1.1 * x;
  }
  return x;
}

Widget comfortatext(
  String text,
  double size,
  Map<String, String> settings, {
  Color color = kWhite,
  TextAlign align = TextAlign.left,
  FontWeight weight = FontWeight.w400,
  TextDecoration decoration = TextDecoration.none,
  int maxLines = 40,
}) {
  final x = getFontSize(settings['Font size']!);
  final baseStyle = GoogleFonts.outfit(
    color: color,
    fontSize: size * x * 1.1,
    fontWeight: weight,
    decoration: decoration,
    height: 1.05,
    decorationColor: color,
  );

  final styleWithFallback = baseStyle.copyWith(
    fontFamilyFallback: [
      'NotoSans',
    ],
  );

  return Text(
    text,
    style: styleWithFallback,
    overflow: TextOverflow.ellipsis,
    maxLines: maxLines,
    textAlign: align,
  );
}

bool estimateBrightnessForColor(Color color) {
  final relativeLuminance = color.computeLuminance();

  const kThreshold = 0.15;
  return (relativeLuminance + 0.05) * (relativeLuminance + 0.05) > kThreshold;
}

Color darken(Color color, [double amount = .1]) {
  assert(amount >= 0 && amount <= 1, 'Amount must be between 0 and 1');

  final hsl = HSLColor.fromColor(color);
  final hslDark = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));

  return hslDark.toColor();
}

Color lighten(Color color, [double amount = .1]) {
  assert(amount >= 0 && amount <= 1, 'Amount must be between 0 and 1');

  final hsl = HSLColor.fromColor(color);
  final hslLight = hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0));

  return hslLight.toColor();
}

Color darken2(Color c, [double amount = 0.1]) {
  assert(0 <= amount && amount <= 1, 'Amount must be between 0 and 1');
  final f = 1 - amount;
  return Color.fromARGB(
    c.a.toInt(),
    (c.r * f).round(),
    (c.g * f).round(),
    (c.b * f).round(),
  );
}

Color lighten2(Color c, [double amount = 0.1]) {
  assert(0 <= amount && amount <= 1, 'Amount must be between 0 and 1');
  return Color.fromARGB(
    c.a.toInt(),
    c.r.toInt() + ((255 - c.r) * amount).round(),
    c.g.toInt() + ((255 - c.g) * amount).round(),
    c.b.toInt() + ((255 - c.b) * amount).round(),
  );
}

Color lightAccent(Color color, int intensity) {
  final x = intensity / (color.r + color.g + color.b);
  return Color.fromRGBO(
    sqrt(color.r * x).toInt(),
    sqrt(color.g * x).toInt(),
    sqrt(color.b * x).toInt(),
    1,
  );
}

Widget newAqiDataPoints(
  String name,
  double value,
  WeatherData data, [
  double size = 15,
]) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      comfortatext(
        name,
        size,
        data.settings,
        color: data.current.palette.primary,
        align: TextAlign.end,
        weight: FontWeight.w500,
      ),
      Padding(
        padding: const EdgeInsets.all(3),
        child: Container(
          width: 2.5,
          height: 2.5,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: data.current.palette.primaryContainer, //primarySecond
          ),
        ),
      ),
      comfortatext(
        value.toString(),
        size,
        data.settings,
        color: data.current.palette.primaryContainer, //primarySecond
        align: TextAlign.end,
        weight: FontWeight.w600,
      ),
    ],
  );
}

bool isUppercase(String str) {
  return str == str.toUpperCase();
}

String generateAbbreviation(String countryName) {
  final words = countryName.split(' ');

  if (words.length == 1) {
    return countryName;
  } else {
    var abbreviation = '';
    for (final word in words) {
      if (word.isNotEmpty && isUppercase(word[0])) {
        abbreviation += word[0];
      }
    }
    return abbreviation;
  }
}

class MySearchParent extends StatefulWidget {
  final Function updateLocation;
  final ColorScheme palette;
  final String place;
  final Map<String, String> settings;
  final Image image;
  final bool isTabletMode;

  const MySearchParent({
    super.key,
    required this.updateLocation,
    required this.palette,
    required this.place,
    required this.settings,
    required this.image,
    required this.isTabletMode,
  });

  @override
  _MySearchParentState createState() => _MySearchParentState(
    palette: palette,
    place: place,
    settings: settings,
    image: image,
    isTabletMode: isTabletMode,
  );
}

class _MySearchParentState extends State<MySearchParent> {
  bool isEditing = false;

  final ColorScheme palette;
  final String place;
  final Map<String, String> settings;
  final Image image;
  final bool isTabletMode;

  _MySearchParentState({
    required this.palette,
    required this.place,
    required this.settings,
    required this.image,
    required this.isTabletMode,
  });

  late Future<SharedPreferences> _prefsFuture;

  @override
  void initState() {
    super.initState();
    _prefsFuture = SharedPreferences.getInstance();
  }

  List<String> getFavorites(SharedPreferences? prefs) {
    final ifnot = [
      '{\n        "id": 2651922,\n        "name": "Nashville",\n        "region": "Tennessee",\n        "country": "United States of America",\n        "lat": 36.17,\n        "lon": -86.78,\n        "url": "nashville-tennessee-united-states-of-america"\n    }',
    ];
    final used = prefs?.getStringList('favorites') ?? ifnot;
    var n = 0;
    while (n < used.length) {
      try {
        jsonDecode(used[n]);
        n += 1;
      } on FormatException {
        used.remove(used[n]);
      }
    }
    return used;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SharedPreferences>(
      future: _prefsFuture,
      builder:
          (BuildContext context, AsyncSnapshot<SharedPreferences> snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            } else if (snapshot.hasError) {
              if (kDebugMode) {
                print(snapshot.error);
              }
              return Center(
                child: ErrorWidget(snapshot.error!),
              );
            }
            final favorites = getFavorites(snapshot.data);
            //return buildWholeThing(snapshot.data);
            return MySearchWidget(
              updateLocation: widget.updateLocation,
              palette: palette,
              favorites: favorites,
              prefs: snapshot.data!,
              place: place,
              settings: settings,
              image: image,
              isTabletMode: isTabletMode,
            );
          },
    );
  }
}

class MySearchWidget extends StatefulWidget {
  final ColorScheme palette;
  final String place;
  final Function updateLocation;
  final List<String> favorites;
  final SharedPreferences prefs;
  final Map<String, String> settings;
  final Image image;
  final bool isTabletMode;

  const MySearchWidget({
    super.key,
    required this.palette,
    required this.updateLocation,
    required this.favorites,
    required this.prefs,
    required this.place,
    required this.settings,
    required this.image,
    required this.isTabletMode,
  });

  @override
  _MySearchWidgetState createState() => _MySearchWidgetState(
    palette: palette,
    updateLocation: updateLocation,
    beginFavorites: favorites,
    prefs: prefs,
    place: place,
    settings: settings,
    image: image,
    isTabletMode: isTabletMode,
  );
}

class _MySearchWidgetState extends State<MySearchWidget> {
  //final FloatingSearchBarController _controller = FloatingSearchBarController();
  final ColorScheme palette;
  final String place;
  final Function updateLocation;
  final SharedPreferences prefs;
  final Map<String, String> settings;
  final Image image;
  final bool isTabletMode;

  final List<String> beginFavorites;

  _MySearchWidgetState({
    required this.palette,
    required this.updateLocation,
    required this.beginFavorites,
    required this.prefs,
    required this.place,
    required this.settings,
    required this.image,
    required this.isTabletMode,
  });

  final ValueNotifier<List<String>> recommend = ValueNotifier<List<String>>([]);
  ValueNotifier<List<String>> favorites = ValueNotifier<List<String>>([]);

  @override
  void initState() {
    super.initState();
    favorites = ValueNotifier<List<String>>(beginFavorites);
  }

  void updateFav(List<String> fav) {
    prefs.setStringList('favorites', fav);

    //Save the favorites so the widgts can access them when selecting location
    final jsonString = jsonEncode(fav);
    WidgetService.saveData('widget.favorites', jsonString);

    setState(() {
      favorites.value = fav;
    });
  }

  void updateRec(List<String> rec) {
    setState(() {
      recommend.value = rec;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (isTabletMode) {
      //go straight to the page itself, since the sidebar has that by default
      return HeroSearchPage(
        palette: palette,
        place: place,
        settings: settings,
        recommend: recommend,
        updateRec: updateRec,
        updateLocation: updateLocation,
        favorites: favorites,
        updateFav: updateFav,
        isTabletMode: true,
        image: image,
      );
    }
    return searchBar2(
      palette,
      recommend,
      updateLocation,
      updateFav,
      favorites,
      updateRec,
      place,
      context,
      settings,
      image,
    );
  }
}
