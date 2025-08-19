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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:home_widget/home_widget.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:overmorrow/core/core.dart';
import 'package:overmorrow/features/settings/settings.dart';
import 'package:overmorrow/main_ui.dart';
import 'package:overmorrow/weather_refact.dart';
import 'package:workmanager/workmanager.dart';

const updateWeatherDataKey = 'com.marotidev.overmorrow.updateWeatherData';

const currentWidgetReceiver =
    'com.marotidev.overmorrow.receivers.CurrentWidgetReceiver';
const dateCurrentWidgetReceiver =
    'com.marotidev.overmorrow.receivers.DateCurrentWidgetReceiver';
const windWidgetReceiver =
    'com.marotidev.overmorrow.receivers.WindWidgetReceiver';
const forecastWidgetReceiver =
    'com.marotidev.overmorrow.receivers.ForecastWidgetReceiver';

class WidgetService {
  static Future<void> saveData(String id, dynamic value) async {
    await HomeWidget.saveWidgetData(id, value);
    print(('Saved', id, value));
  }

  static Future<void> syncCurrentDataToWidget(
    LightCurrentWeatherData data,
    int widgetId,
  ) async {
    await saveData('current.temp.$widgetId', data.temp);
    await saveData('current.condition.$widgetId', data.condition);
    await saveData('current.updatedTime.$widgetId', data.updatedTime);
    await saveData('current.place.$widgetId', data.place);
    await saveData('current.date.$widgetId', data.dateString);

    //place is the name of the city while location can include currentLocation
  }

  static Future<void> syncWindDataToWidget(
    LightWindData data,
    int widgetId,
  ) async {
    await saveData('wind.windSpeed.$widgetId', data.windSpeed);
    await saveData('wind.windDirAngle.$widgetId', data.windDirAngle);
    await saveData('wind.windUnit.$widgetId', data.windUnit);
  }

  static Future<void> syncHourlyForecastDataToWidget(
    LightHourlyForecastData data,
    int widgetId,
  ) async {
    await saveData('hourlyForecast.currentTemp.$widgetId', data.currentTemp);
    await saveData(
      'hourlyForecast.currentCondition.$widgetId',
      data.currentCondition,
    );
    await saveData('hourlyForecast.updatedTime.$widgetId', data.updatedTime);
    await saveData('hourlyForecast.place.$widgetId', data.place);

    await saveData('hourlyForecast.hourlyTemps.$widgetId', data.hourlyTemps);
    await saveData(
      'hourlyForecast.hourlyConditions.$widgetId',
      data.hourlyConditions,
    );
    await saveData('hourlyForecast.hourlyNames.$widgetId', data.hourlyNames);
  }

  static Future<void> reloadWidgets() async {
    await HomeWidget.updateWidget(
      androidName: 'CurrentWidget',
      qualifiedAndroidName: currentWidgetReceiver,
    );
    await HomeWidget.updateWidget(
      androidName: 'DateCurrentWidget',
      qualifiedAndroidName: dateCurrentWidgetReceiver,
    );
    await HomeWidget.updateWidget(
      androidName: 'WindWidget',
      qualifiedAndroidName: windWidgetReceiver,
    );
    await HomeWidget.updateWidget(
      androidName: 'ForecastWidget',
      qualifiedAndroidName: forecastWidgetReceiver,
    );
  }
}

//this is the best solution i found to trigger an update of the data after the preferences have been changed
@pragma('vm:entry-point')
Future<void> interactiveCallback(Uri? uri) async {
  print('INTERACTIVE CALLBACK, $uri');
  if (uri?.host == 'update') {
    await Workmanager().registerOneOffTask(
      'test_task_${DateTime.now().millisecondsSinceEpoch}',
      updateWeatherDataKey,
    );
  }
}

@pragma(
  'vm:entry-point',
) // Mandatory if the App is obfuscated or using Flutter 3.1+
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    print(
      'Native called background task: $task',
    ); //simpleTask will be emitted here.

    switch (task) {
      case updateWeatherDataKey:
        try {
          print(
            'HEEEEEEEEEEEEEEEEEEEEEEEERRRRRRRRRRRRRRRRRRRRRRREEEEEEEEEEEEEEEEEEE',
          );

          final installedWidgets = await HomeWidget.getInstalledWidgets();

          if (installedWidgets.isEmpty) {
            print('no widgets installed, skipping update');
            return Future.value(true);
          }

          final settings = await getSettingsUsed();

          for (final widgetInfo in installedWidgets) {
            final widgetId = widgetInfo.androidWidgetId!;
            final widgetClassName = widgetInfo.androidClassName!;
            print(('classname', widgetClassName));

            final locationKey = 'current.location.$widgetId';
            final latLonKey = 'current.latLon.$widgetId';
            final providerKey = 'current.provider.$widgetId';

            final widgetLocation =
                (await HomeWidget.getWidgetData<String>(
                  locationKey,
                  defaultValue: 'unknown',
                )) ??
                'unknown';
            final widgetProvider =
                (await HomeWidget.getWidgetData<String>(
                  providerKey,
                  defaultValue: 'unknown',
                )) ??
                'unknown';

            if (widgetLocation == 'unknown') continue;

            String placeName;
            String latLon;

            if (widgetLocation == 'currentLocation') {
              final lastKnown = await getLastKnownLocation();
              placeName = lastKnown[0];
              latLon = lastKnown[1];
            } else {
              placeName = widgetLocation;
              latLon =
                  (await HomeWidget.getWidgetData<String>(
                    latLonKey,
                    defaultValue: 'unknown',
                  )) ??
                  'unknown';
            }

            //these two are so similar that i'm updating them with the same logic
            if (widgetClassName == currentWidgetReceiver ||
                widgetClassName == dateCurrentWidgetReceiver) {
              final data =
                  await LightCurrentWeatherData.getLightCurrentWeatherData(
                    placeName,
                    latLon,
                    widgetProvider,
                    settings,
                  );

              await WidgetService.syncCurrentDataToWidget(data, widgetId);
            } else if (widgetClassName == windWidgetReceiver) {
              final data = await LightWindData.getLightWindData(
                placeName,
                latLon,
                widgetProvider,
                settings,
              );

              await WidgetService.syncWindDataToWidget(data, widgetId);
            } else if (widgetClassName == forecastWidgetReceiver) {
              final data = await LightHourlyForecastData.getLightForecastData(
                placeName,
                latLon,
                widgetProvider,
                settings,
              );

              await WidgetService.syncHourlyForecastDataToWidget(
                data,
                widgetId,
              );
            }
          }

          await WidgetService.reloadWidgets();
        } catch (e, stacktrace) {
          if (kDebugMode) {
            print(
              'ERRRRRRRRRRRRRRRRRRRRRRRRROOOOOOOOOOOOOOOOOOOOOOOOOOORRRRRRRRRRRRRRRRRRRRRR',
            );
            print((e, stacktrace));
          }
          return Future.value(false);
        }
    }

    return Future.value(true);
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureDependencies();
  await Workmanager().initialize(
    callbackDispatcher, // The top level function, aka callbackDispatcher
    isInDebugMode:
        kDebugMode, // If enabled it will post a notification whenever the task is running. Handy for debugging tasks
  );

  await HomeWidget.registerInteractivityCallback(interactiveCallback);

  if (kDebugMode) {
    print('thissssssssssssssssssssssssssssssssss');
    await Workmanager().registerOneOffTask(
      'test_task_${DateTime.now().millisecondsSinceEpoch}',
      updateWeatherDataKey,
    );
  }

  await Workmanager().registerPeriodicTask(
    'updateWeatherWidget',
    updateWeatherDataKey,
    frequency: const Duration(hours: 1),
    constraints: Constraints(
      networkType: NetworkType.connected,
      requiresBatteryNotLow: true,
    ),
  );

  final data =
      WidgetsBinding.instance.platformDispatcher.views.first.physicalSize;
  final ratio =
      WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;

  if (data.shortestSide / ratio < 600) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]).then((value) => runApp(const MyApp()));
  } else {
    runApp(const MyApp());
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Locale _locale = const Locale('en');

  void setLocale(Locale locale) {
    setState(() {
      _locale = locale;
    });
  }

  @override
  void initState() {
    super.initState();

    setPreferedLocale();
  }

  Future<void> setPreferedLocale() async {
    final loc = await getLanguageUsed();
    final to = languageNameToLocale[loc] ?? const Locale('en');

    setState(() {
      _locale = to;
    });
  }

  @override
  Widget build(BuildContext context) {
    final systemGestureInsets = MediaQuery.of(context).systemGestureInsets;
    if (systemGestureInsets.left > 0) {
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          systemNavigationBarColor: Colors.transparent,
        ),
      );
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    // I have no idea why this works but thank you to https://stackoverflow.com/a/72754385
    return MaterialApp(
      locale: _locale,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: HomePage(
        key: Key(_locale.toString()),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _sanitizePlaceName(String input) {
    final safe = input.replaceAll(RegExp(r'[^\w\s\-,]'), '').trim();
    if (safe.isEmpty) return ''; // Handle empty input after sanitization
    return safe.length > 100 ? safe.substring(0, 100) : safe;
  }

  Future<Widget> getDays(
    bool recall,
    String proposedLoc,
    String backupName,
    bool startup,
  ) async {
    try {
      final localizations = AppLocalizations.of(context)!;

      final settings = await getSettingsUsed();
      final weatherProvider = await getWeatherProvider();
      backupName = _sanitizePlaceName(backupName);

      if (startup) {
        final n = await getLastPlace(); //loads the last place you visited
        proposedLoc = n[1];
        backupName = n[0];
        startup = false;
      }

      var absoluteProposed = proposedLoc;
      var isItCurrentLocation = false;

      if (backupName == 'CurrentLocation') {
        final locStatus = await isLocationSafe(localizations);
        if (locStatus == 'enabled') {
          Position position;
          try {
            position = await Geolocator.getCurrentPosition(
              locationSettings: AndroidSettings(
                accuracy: LocationAccuracy.medium,
                timeLimit: const Duration(seconds: 3),
              ),
            );
          } on TimeoutException {
            try {
              position = (await Geolocator.getLastKnownPosition())!;
            } on Error {
              return ErrorPage(
                errorMessage: localizations.unableToLocateDevice,
                updateLocation: updateLocation,
                icon: Icons.gps_off,
                place: backupName,
                settings: settings,
                provider: weatherProvider,
                latlng: absoluteProposed,
              );
            }
          } on LocationServiceDisabledException {
            return ErrorPage(
              errorMessage: localizations.locationServicesAreDisabled,
              updateLocation: updateLocation,
              icon: Icons.gps_off,
              place: backupName,
              settings: settings,
              provider: weatherProvider,
              latlng: absoluteProposed,
            );
          }

          isItCurrentLocation = true;

          try {
            final placemarks = await placemarkFromCoordinates(
              position.latitude,
              position.longitude,
            ).timeout(const Duration(seconds: 3));
            final place = placemarks[0];

            backupName =
                place.locality ??
                place.subLocality ??
                place.thoroughfare ??
                place.subThoroughfare ??
                '';
            absoluteProposed = '${position.latitude}, ${position.longitude}';

            //update the last known position for the home screen widgets
            await setLastKnownLocation(backupName, absoluteProposed);
          } on Error {
            backupName =
                '${position.latitude.toStringAsFixed(2)}, ${position.longitude.toStringAsFixed(2)}';
          }
        } else {
          return ErrorPage(
            errorMessage: locStatus,
            updateLocation: updateLocation,
            icon: Icons.gps_off,
            place: backupName,
            settings: settings,
            provider: weatherProvider,
            latlng: absoluteProposed,
          );
        }
      }

      if (proposedLoc == 'query') {
        final List<dynamic> suggestedLocations =
            await LocationService.getRecommendation(
              backupName,
              settings['Search provider'],
              settings,
            );
        if (suggestedLocations.isNotEmpty) {
          final split = json.decode(suggestedLocations[0] as String);
          absoluteProposed = "${split["lat"]},${split["lon"]}";
          backupName = split['name'] as String;
        } else {
          return ErrorPage(
            errorMessage: '${localizations.placeNotFound}: \n $backupName',
            updateLocation: updateLocation,
            icon: Icons.location_disabled,
            key: Key(backupName),
            place: backupName,
            settings: settings,
            provider: weatherProvider,
            latlng: absoluteProposed,
          );
        }
      }

      final RealName = backupName;
      if (isItCurrentLocation) {
        backupName = 'CurrentLocation';
      }

      WeatherData weatherData;

      try {
        weatherData = await WeatherData.getFullData(
          settings,
          RealName,
          backupName,
          absoluteProposed,
          weatherProvider,
          localizations,
        );
      } on TimeoutException {
        return ErrorPage(
          errorMessage: localizations.weakOrNoWifiConnection,
          updateLocation: updateLocation,
          icon: Icons.wifi_off,
          key: Key(backupName),
          place: backupName,
          settings: settings,
          provider: weatherProvider,
          latlng: absoluteProposed,
        );
      } on HttpExceptionWithStatus catch (hihi) {
        return ErrorPage(
          errorMessage: 'general error at place 1: $hihi',
          updateLocation: updateLocation,
          icon: Icons.bug_report,
          place: backupName,
          settings: settings,
          provider: weatherProvider,
          latlng: absoluteProposed,
          shouldAdd: 'Please try another weather provider!',
        );
      } on SocketException {
        return ErrorPage(
          errorMessage: localizations.notConnectedToTheInternet,
          updateLocation: updateLocation,
          icon: Icons.wifi_off,
          key: Key(backupName),
          place: backupName,
          settings: settings,
          provider: weatherProvider,
          latlng: absoluteProposed,
        );
      } catch (e, stacktrace) {
        if (kDebugMode) {
          debugPrint('Stack trace: $stacktrace');
        }
        return ErrorPage(
          errorMessage: 'general error at place 1: $e',
          updateLocation: updateLocation,
          icon: Icons.bug_report,
          place: backupName,
          settings: settings,
          provider: weatherProvider,
          latlng: absoluteProposed,
          shouldAdd: 'Please try another weather provider!',
        );
      }

      await setLastPlace(
        backupName,
        absoluteProposed,
      ); // if the code didn't fail
      // then this will be the new startup place

      //WidgetService.saveData('counter', weatherData.current.temp);
      //WidgetService.reloadWidget();

      return WeatherPage(data: weatherData, updateLocation: updateLocation);
    } catch (e, stacktrace) {
      final settings = await getSettingsUsed();
      final weatherProvider = await getWeatherProvider();

      if (kDebugMode) {
        debugPrint('Error fetching weather data: $e');
        debugPrint('Stack trace: $stacktrace');
      }

      await cacheManager2.emptyCache();

      if (recall) {
        return ErrorPage(
          errorMessage: 'An error occurred while fetching data',
          updateLocation: updateLocation,
          icon: Icons.bug_report,
          place: backupName,
          settings: settings,
          provider: weatherProvider,
          latlng: 'query',
          shouldAdd: 'Please try another weather provider!',
        );
      } else {
        //retry after clearing cache
        return getDays(true, proposedLoc, backupName, startup);
      }
    }
  }

  Widget w1 = Container();
  bool isLoading = false;
  bool startup2 = false;

  @override
  void initState() {
    super.initState();

    //defaults to new york when no previous location was found
    updateLocation(
      '40.7128, -74.0060',
      'New York',
      time: 300,
      startup: true,
    ); //just for testing
  }

  Future<void> updateLocation(
    String proposedLoc,
    String backupName, {
    int time = 0,
    bool startup = false,
  }) async {
    setState(() {
      HapticFeedback.lightImpact();
      if (startup) {
        startup2 = true;
      }
      isLoading = true;
    });

    await Future<void>.delayed(Duration(milliseconds: time));

    if (!mounted) return;

    try {
      final screen = await getDays(false, proposedLoc, backupName, startup);

      setState(() {
        w1 = screen;
        if (!mounted) return;
        if (startup) {
          startup2 = false;
        }
      });

      setState(() {
        isLoading = false;
      });
    } catch (error, s) {
      if (kDebugMode) {
        print((error, s));
      }

      setState(() {
        isLoading = false;
      });
    }

    if (startup) {
      startup2 = false;
    }
  }

  List<Color> colors = getStartBackColor();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kWhite,
      body: Stack(
        children: [
          w1,
          if (isLoading)
            ColoredBox(
              color: startup2 ? colors[0] : const Color.fromRGBO(0, 0, 0, 0.7),
              child: Center(
                child: LoadingAnimationWidget.staggeredDotsWave(
                  color: startup2 ? colors[1] : kWhite,
                  size: 40,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

List<Color> getStartBackColor() {
  final brightness =
      SchedulerBinding.instance.platformDispatcher.platformBrightness;
  final isDarkMode = brightness == Brightness.dark;
  final back = isDarkMode ? kBlack : kWhite;
  final front = isDarkMode
      ? const Color.fromRGBO(250, 250, 250, 0.7)
      : const Color.fromRGBO(0, 0, 0, 0.3);
  return [back, front];
}
