import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:mvc_pattern/mvc_pattern.dart';

import '../helper/log_print.dart';
import '../helper/secrets.dart';
import 'dart:math' show cos, sqrt, asin;

class HomeController extends ControllerMVC {
  CameraPosition initialLocation = CameraPosition(target: LatLng(0.0, 0.0));
  late GoogleMapController mapController;
  late Position currentPosition;
  String currentAddress = '';
  final startAddressController = TextEditingController();
  final destinationAddressController = TextEditingController();
  final startAddressFocusNode = FocusNode();
  final desrinationAddressFocusNode = FocusNode();
  String startAddress = '';
  String destinationAddress = '';
  String? placeDistance;

  Set<Marker> markers = {};
  late PolylinePoints polylinePoints;
  Map<PolylineId, Polyline> polylines = {};
  List<LatLng> polylineCoordinates = [];

  final scaffoldKey = GlobalKey<ScaffoldState>();
  late String startCoordinatesString;
  late String destinationCoordinatesString;
  late Marker startMarker;
  late Marker destinationMarker;

  late Marker carMarker;
  int animationCounter = 0;

  getCurrentLocation() async {
    await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high)
        .then((Position position) async {
      setState(() {
        currentPosition = position;
        logPrint('CURRENT POS: ${currentPosition}');
        mapController.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(position.latitude, position.longitude),
              zoom: 18.0,
            ),
          ),
        );
      });
      await getAddress();
      notifyListeners();
    }).catchError((e) {
      print(e);
    });
  }

  getAddress() async {
    try {
      List<Placemark> p = await placemarkFromCoordinates(
          currentPosition.latitude, currentPosition.longitude);

      Placemark place = p[0];

      setState(() {
        currentAddress =
            "${place.name}, ${place.locality}, ${place.postalCode}, ${place.country}";
        startAddressController.text = currentAddress;
        startAddress = currentAddress;
        logPrint('startAddress---> ${startAddress}');
        notifyListeners();
      });
    } catch (e) {
      logPrint('exe---> ${e}');
    }
  }

  Future<bool> calculateDistance() async {
    try {
      List<Location> startPlacemark = await locationFromAddress(startAddress);
      List<Location> destinationPlacemark =
          await locationFromAddress(destinationAddress);

      double startLatitude = startAddress == currentAddress
          ? currentPosition.latitude
          : startPlacemark[0].latitude;

      double startLongitude = startAddress == currentAddress
          ? currentPosition.longitude
          : startPlacemark[0].longitude;

      double destinationLatitude = destinationPlacemark[0].latitude;
      double destinationLongitude = destinationPlacemark[0].longitude;

      startCoordinatesString = '($startLatitude, $startLongitude)';
      destinationCoordinatesString =
          '($destinationLatitude, $destinationLongitude)';
      final Uint8List markerIcon =
          await getBytesFromAsset('assets/img/car.png', 120);

      startMarker = Marker(
        markerId: MarkerId(startCoordinatesString),
        position: LatLng(startLatitude, startLongitude),
        infoWindow: InfoWindow(
          title: 'Current  ${startCoordinatesString}',
          snippet: startAddress,
        ),
        //icon: BitmapDescriptor.defaultMarker,
        icon: BitmapDescriptor.fromBytes(markerIcon),
      );

      destinationMarker = Marker(
        markerId: MarkerId(destinationCoordinatesString),
        position: LatLng(destinationLatitude, destinationLongitude),
        infoWindow: InfoWindow(
          title: 'Destination ${destinationCoordinatesString}',
          snippet: destinationAddress,
        ),
        icon: BitmapDescriptor.defaultMarker,
      );

      markers.add(startMarker);
      markers.add(destinationMarker);

      logPrint(
        'START COORDINATES: ($startLatitude, $startLongitude)',
      );
      logPrint(
        'DESTINATION COORDINATES: ($destinationLatitude, $destinationLongitude)',
      );

      double miny = (startLatitude <= destinationLatitude)
          ? startLatitude
          : destinationLatitude;
      double minx = (startLongitude <= destinationLongitude)
          ? startLongitude
          : destinationLongitude;
      double maxy = (startLatitude <= destinationLatitude)
          ? destinationLatitude
          : startLatitude;
      double maxx = (startLongitude <= destinationLongitude)
          ? destinationLongitude
          : startLongitude;

      double southWestLatitude = miny;
      double southWestLongitude = minx;

      double northEastLatitude = maxy;
      double northEastLongitude = maxx;

      mapController.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            northeast: LatLng(northEastLatitude, northEastLongitude),
            southwest: LatLng(southWestLatitude, southWestLongitude),
          ),
          100.0,
        ),
      );

      await createPolylines(startLatitude, startLongitude, destinationLatitude,
          destinationLongitude);

      double totalDistance = 0.0;

      for (var i = 0; i < polylineCoordinates.length - 1; i++) {
        totalDistance += coordinateDistance(
          polylineCoordinates[i].latitude,
          polylineCoordinates[i].longitude,
          polylineCoordinates[i + 1].latitude,
          polylineCoordinates[i + 1].longitude,
        );
        // distance += Geolocator.distanceBetween(
        //     polylineCoordinates[i].latitude,
        //     polylineCoordinates[i].longitude,
        //     polylineCoordinates[i + 1].latitude,
        //     polylineCoordinates[i + 1].longitude);
        // totalDistance = double.parse((distance / 1000).toStringAsFixed(3));
      }

      setState(() {
        placeDistance = totalDistance.toStringAsFixed(2);
        logPrint('distance----> ${placeDistance} km');
      });
      notifyListeners();

      return true;
    } catch (e) {
      logPrint('exe---> ${e}');
    }
    return false;
  }

  createPolylines(
    double startLatitude,
    double startLongitude,
    double destinationLatitude,
    double destinationLongitude,
  ) async {
    polylinePoints = PolylinePoints();
    PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
      Secrets.API_KEY,
      PointLatLng(startLatitude, startLongitude),
      PointLatLng(destinationLatitude, destinationLongitude),
      travelMode: TravelMode.transit,
    );

    // setState(() {
    //   markers.add(startMarker);
    // });

    if (result.points.isNotEmpty) {
      // polylineCoordinates.clear();
      // result.points.forEach((PointLatLng point) {
      //   polylineCoordinates.add(LatLng(point.latitude, point.longitude));
      // });

      final Uint8List markerIcon =
      await getBytesFromAsset('assets/img/car.png', 120);

      for (PointLatLng point in result.points){
        polylineCoordinates.add(LatLng(point.latitude, point.longitude));
        // carMarker = Marker(
        //   markerId: MarkerId("car"),
        //   position: LatLng(point.latitude, point.longitude),
        //   icon: BitmapDescriptor.fromBytes(markerIcon),
        // );

         carMarker = Marker(
          markerId: MarkerId("car"),
          position: LatLng(point.latitude, point.longitude),
          icon: BitmapDescriptor.fromBytes(markerIcon),
        );
        markers.add(carMarker);

        animationCounter++;
        notifyListeners();
        await Future.delayed(const Duration(milliseconds: 100));
      }

    }

    logPrint('points----> ${result.points}');
    logPrint('errorMessage----> ${result.errorMessage}');

    PolylineId id = PolylineId('poly');
    Polyline polyline = Polyline(
      polylineId: id,
      color: Colors.blue,
      points: polylineCoordinates,
      width: 3,
    );
    polylines[id] = polyline;
    notifyListeners();
  }

  double coordinateDistance(lat1, lon1, lat2, lon2) {
    var p = 0.017453292519943295;
    var c = cos;
    var a = 0.5 -
        c((lat2 - lat1) * p) / 2 +
        c(lat1 * p) * c(lat2 * p) * (1 - c((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a));
  }

  Future<Uint8List> getBytesFromAsset(String path, int width) async {
    ByteData data = await rootBundle.load(path);
    ui.Codec codec = await ui.instantiateImageCodec(data.buffer.asUint8List(),
        targetWidth: width);
    ui.FrameInfo fi = await codec.getNextFrame();
    return (await fi.image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
  }
}
