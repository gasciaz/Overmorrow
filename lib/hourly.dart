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

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

import 'package:overmorrow/l10n/app_localizations.dart';
import 'package:overmorrow/ui_helper.dart';

class NewHourly extends StatefulWidget {
  final data;
  final hours;
  final elevated;

  const NewHourly(
      {super.key,
      required this.data,
      required this.hours,
      required this.elevated});

  @override
  _NewHourlyState createState() => _NewHourlyState(data, hours, elevated);
}

class _NewHourlyState extends State<NewHourly>
    with AutomaticKeepAliveClientMixin {
  final data;
  final hours;
  final bool elevated;

  int _value = 0;

  @override
  bool get wantKeepAlive => true;

  _NewHourlyState(this.data, this.hours, this.elevated);

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final ColorScheme palette = data.current.palette;
    return Padding(
      padding: elevated
          ? const EdgeInsets.all(0)
          : const EdgeInsets.only(left: 21, right: 21, bottom: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 196,
            child: hourBoxes(hours, data, _value, elevated, context),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 15, left: 5),
            child: Wrap(
              spacing: 5,
              children: List<Widget>.generate(
                4,
                (int index) {
                  return ChoiceChip(
                    elevation: 0,
                    checkmarkColor: palette.onSecondaryContainer,
                    color: WidgetStateProperty.resolveWith((states) {
                      if (index == _value) {
                        return palette.secondaryContainer;
                      }
                      return elevated
                          ? palette.surfaceContainer
                          : palette.surface;
                    }),
                    side: BorderSide(
                        color: index == _value
                            ? palette.secondaryContainer
                            : palette.outlineVariant,
                        width: 1.6),
                    label: comfortatext(
                        [
                          AppLocalizations.of(context)!.sumLowercase,
                          AppLocalizations.of(context)!.precipLowercase,
                          AppLocalizations.of(context)!.windLowercase,
                          AppLocalizations.of(context)!.uvLowercase,
                        ][index],
                        14,
                        data.settings,
                        color: _value == index
                            ? palette.onSecondaryContainer
                            : palette.onSurface),
                    selected: _value == index,
                    onSelected: (bool selected) {
                      setState(() {
                        _value = index;
                        HapticFeedback.lightImpact();
                      });
                    },
                  );
                },
              ).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

Widget hourBoxes(hours, data, value, elevated, context) {
  final ColorScheme palette = data.current.palette;

  return AnimationLimiter(
    child: ListView.builder(
      itemCount: hours.length,
      scrollDirection: Axis.horizontal,
      itemBuilder: (BuildContext context, int index) {
        final hour = hours[index];
        if (hour is String) {
          return AnimationConfiguration.staggeredList(
            position: index,
            duration: const Duration(milliseconds: 500),
            child: SlideAnimation(
              horizontalOffset: 100,
              child: FadeInAnimation(child: dividerWidget(palette, hour, data)),
            ),
          );
        }
        final var childWidgets = <Widget>[
          buildHourlySum(hour, palette, data),
          buildHourlyPrecip(hour, palette, data),
          buildHourlyWind(hour, palette, data),
          buildHourlyUv(hour, palette, data),
        ];

        return AnimationConfiguration.staggeredList(
          position: index,
          duration: const Duration(milliseconds: 500),
          child: SlideAnimation(
            horizontalOffset: 100,
            child: FadeInAnimation(
                child: hourlyDataBuilder(
                    hour, palette, elevated, childWidgets[value], data)),
          ),
        );
      },
    ),
  );
}

Widget hourlyDataBuilder(
    hour, ColorScheme palette, bool elevated, childWidget, data) {
  return Padding(
    padding: const EdgeInsets.all(3),
    child: AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      switchInCurve: Curves.decelerate,
      transitionBuilder: (Widget child, Animation<double> animation) {
        final offsetAnimation = Tween<Offset>(
                begin: const Offset(0, 1), end: const Offset(0, 0))
            .animate(animation);
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SlideTransition(
            position: offsetAnimation,
            child: Container(
              padding: const EdgeInsets.only(top: 7, bottom: 5),
              width: 67,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(40),
                color: elevated
                    ? palette.surfaceContainerHighest
                    : palette.surfaceContainer,
              ),
              child: child,
            ),
          ),
        );
      },
      child: childWidget,
    ),
  );
}

Widget dividerWidget(ColorScheme palette, name, data) {
  return Padding(
    padding: const EdgeInsets.only(top: 3, bottom: 3, left: 6, right: 6),
    child: RotatedBox(
        quarterTurns: -1,
        child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: palette.secondaryContainer,
              borderRadius: BorderRadius.circular(6),
            ),
            padding:
                const EdgeInsets.only(left: 10, top: 5, bottom: 5, right: 10),
            child: Center(
                child: comfortatext(name, 17, data.settings,
                    color: palette.onSecondaryContainer,
                    weight: FontWeight.w500)))),
  );
}

Widget buildHourlySum(var hour, ColorScheme palette, data) {
  return Column(
    key: const ValueKey('sum'),
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 2),
        child: comfortatext('${hour.temp}°', 18, data.settings,
            color: palette.primary, weight: FontWeight.w500),
      ),
      Icon(
        hour.icon,
        color: palette.onSurface,
        size: 37,
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.umbrella, size: 14, color: palette.primary),
          comfortatext('${hour.precip_prob}%', 14, data.settings,
              color: palette.primary, weight: FontWeight.w500)
        ],
      ),
      comfortatext(hour.time, 14, data.settings,
          color: palette.outline)
    ],
  );
}

Widget buildHourlyPrecip(var hour, ColorScheme palette, data) {
  return Stack(
    children: [
      Column(
        key: const ValueKey('precip'),
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Column(
            children: [
              comfortatext('${hour.precip}', 18, data.settings,
                  color: palette.primary, weight: FontWeight.w500),
              comfortatext(
                  '${data.settings["Precipitation"]}', 9, data.settings,
                  color: palette.primary, weight: FontWeight.w500),
            ],
          ),
          SizedBox(
            width: 33,
            height: 33,
            child: Center(
              child: CircularProgressIndicator(
                //this seems to be falsely depreciated, wrapping it in the CircularProgressIndicatorTheme
                //as instructed also trows the same exception
                year2023: false,
                value: hour.precip_prob / 100,
                strokeWidth: 3.5,
                backgroundColor: palette.outlineVariant,
                color: palette.secondary,
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.umbrella, size: 14, color: palette.primary),
              comfortatext('${hour.precip_prob}%', 14, data.settings,
                  color: palette.primary, weight: FontWeight.w500)
            ],
          ),
          comfortatext(hour.time, 14, data.settings,
              color: palette.outline)
        ],
      ),
    ],
  );
}

Widget buildHourlyWind(var hour, ColorScheme palette, data) {
  return Column(
    key: const ValueKey('wind'),
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      Column(
        children: [
          comfortatext('${hour.wind}', 18, data.settings,
              color: palette.primary),
          comfortatext('${data.settings["Wind"]}', 9, data.settings,
              color: palette.primary, weight: FontWeight.w500),
        ],
      ),
      Transform.rotate(
          angle: (hour.wind_dir + 180) * pi / 180,
          child: Icon(
            Icons.navigation_outlined,
            color: palette.onSurface,
            size: 18,
          )),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Icon(Icons.trending_up, size: 13, color: palette.primary),
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: comfortatext('${hour.wind_gusts}', 14, data.settings,
                color: palette.primary, weight: FontWeight.w500),
          ),
          comfortatext('${data.settings["Wind"]}', 9, data.settings,
              color: palette.primary, weight: FontWeight.w500),
        ],
      ),
      comfortatext(hour.time, 14, data.settings,
          color: palette.outline)
    ],
  );
}

Widget buildHourlyUv(var hour, ColorScheme palette, data) {
  return Column(
    key: const ValueKey('uv'),
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      Column(
        children: [
          comfortatext('${hour.uv}', 19, data.settings,
              color: palette.primary, weight: FontWeight.w500),
          comfortatext('UV', 9, data.settings,
              color: palette.primary, weight: FontWeight.w500),
        ],
      ),
      SizedBox(
        height: 65,
        child: ListView.builder(
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 10,
            itemExtent: 6.5,
            itemBuilder: (BuildContext context, int index) {
              if (index < min(max(10 - hour.uv, 0), 10)) {
                return Center(
                  child: Container(
                    width: 13,
                    height: 4,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: palette.outlineVariant,
                    ),
                  ),
                );
              } else {
                return Center(
                  child: Container(
                    width: 13,
                    height: 4,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: palette.secondary,
                    ),
                  ),
                );
              }
            }),
      ),
      comfortatext(hour.time, 14, data.settings,
          color: palette.outline)
    ],
  );
}
