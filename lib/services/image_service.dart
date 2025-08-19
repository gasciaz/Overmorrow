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

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:overmorrow/api_key.dart';
import 'package:overmorrow/caching.dart';
import 'package:overmorrow/weather_refact.dart';

String backdropCorrection(String text) {
  return textBackground[text] ?? 'clear_sky3.jpg';
}

List<String> assetImageCredit(String name) {
  return assetPhotoCredits[name] ?? ['', '', ''];
}

class ImageService {
  final Image image;
  final String username;
  final String userlink;
  final String photolink;

  const ImageService(
      {required this.image,
      required this.username,
      required this.userlink,
      required this.photolink});

  static Future<ImageService> getUnsplashCollectionImage(
      String condition, String loc) async {
    final collectionId = conditionToCollection[condition] ?? 'XMGA2-GGjyw';

    final params = {
      'client_id': access_key,
      'collections': collectionId,
      'content_filter': 'high',
      'count': '1',
    };

    final url = Uri.https('api.unsplash.com', 'photos/random', params);

    final file = await XCustomCacheManager.fetchData(
        url.toString(), '$condition $loc unsplash');
    final response2 = await file[0].readAsString();
    final unsplashBody = jsonDecode(response2 as String);

    final String imagePath =
        unsplashBody[0]['urls']['raw'] + '&w=1500' as String;
    final image = Image(
        image: CachedNetworkImageProvider(imagePath),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity);

    final String userLink =
        (unsplashBody[0]['user']['links']['html']) as String? ?? '';
    final String userName = unsplashBody[0]['user']['name'] as String? ?? '';

    final String photoLink = unsplashBody[0]['links']['html'] as String? ?? '';

    return ImageService(
        image: image,
        username: userName,
        userlink: userLink,
        photolink: photoLink);
  }

  static ImageService getAssetImage(String condition) {
    final imagePath = backdropCorrection(condition);
    final image = Image.asset(
      'assets/backdrops/$imagePath',
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
    );
    final credits = assetImageCredit(condition);

    final photoLink = credits[0];
    final userName = credits[1];
    final userLink = credits[2];

    return ImageService(
        image: image,
        username: userName,
        userlink: userLink,
        photolink: photoLink);
  }

  static Future<ImageService> getImageService(
      String condition, String loc, Map<String, String> settings) async {
    if (settings['Image source'] == 'network') {
      try {
        //ImageService i = await getUnsplashImage(condition, loc);
        final i = await getUnsplashCollectionImage(condition, loc);
        return i;
      } catch (e) {
        final error = e.toString().replaceAll(access_key, '<key>');
        if (kDebugMode) {
          print(error);
        }
        return getAssetImage(condition);
      }
    } else {
      return getAssetImage(condition);
    }
  }
}
