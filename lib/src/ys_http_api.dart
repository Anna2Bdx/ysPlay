import 'package:dio/dio.dart';
import 'package:ys_play/src/entity/capacity_response_entity.dart';
import 'package:ys_play/src/entity/ys_request_entity.dart';

import 'entity/ys_response_entity.dart';

class YsHttpApi {
  /// Démarrer le contrôle PTZ
  static const String ptzStart =
      "https://ieuopen.ezvizlife.com/api/lapp/device/ptz/start";

  /// Arrêter le contrôle PTZ
  static const String ptzStop = "https://ieuopen.ezvizlife.com/api/lapp/device/ptz/stop";

  /// Retournement miroir
  static const String ptzMirror =
      "https://ieuopen.ezvizlife.com/api/lapp/device/ptz/mirror";

  /// Ensemble de capacités du périphérique
  static const String devCapacity =
      "https://ieuopen.ezvizlife.com/api/lapp/device/capacity";


  /// Démarrer le contrôle PTZ
  static Future<YsResponseEntity> devPtzStart({
    required String accessToken,
    required String deviceSerial,
    required int channelNo,
    required int direction,
    int? speed,
  }) async {
    FormData formData = FormData.fromMap({
      "accessToken": accessToken,
      "deviceSerial": deviceSerial,
      "channelNo": channelNo,
      "direction": direction,
      "speed": speed ?? 1,
    });

    try {
      Response response = await Dio().post(ptzStart, data: formData);
      if (response.statusCode == 200) {
        YsResponseEntity responseData =
            YsResponseEntity.fromJson(response.data);
        return responseData;
      } else {
        // Échec
        return YsResponseEntity.fromJson({
          "code": response.statusCode,
          "msg": response.statusMessage,
        });
      }
    } catch (e) {
      throw ("Erreur de requête: ${e.toString()}");
    }
  }

  /// Arrêter le contrôle PTZ
  static Future<YsResponseEntity> devPtzStop({
    required String accessToken,
    required String deviceSerial,
    required int channelNo,
    int? direction,
  }) async {
    FormData formData = FormData.fromMap({
      "accessToken": accessToken,
      "deviceSerial": deviceSerial,
      "channelNo": channelNo,
      "direction": direction,
    });
    try {
      Response response = await Dio().post(ptzStop, data: formData);
      if (response.statusCode == 200) {
        YsResponseEntity responseData =
            YsResponseEntity.fromJson(response.data);
        return responseData;
      } else {
        // Échec
        return YsResponseEntity.fromJson({
          "code": response.statusCode,
          "msg": response.statusMessage,
        });
      }
    } catch (e) {
      throw ("Erreur de requête: ${e.toString()}");
    }
  }

  /// Retournement miroir
  static Future<YsResponseEntity> devPtzMirror(
      YsRequestEntity requestEntity) async {
    FormData formData = FormData.fromMap({
      "accessToken": requestEntity.accessToken,
      "deviceSerial": requestEntity.deviceSerial,
      "channelNo": requestEntity.channelNo,
      "command": requestEntity.command,
    });

    try {
      Response response = await Dio().post(ptzMirror, data: formData);
      if (response.statusCode == 200) {
        YsResponseEntity responseData =
            YsResponseEntity.fromJson(response.data);
        return responseData;
      } else {
        // Échec
        return YsResponseEntity.fromJson({
          "code": response.statusCode,
          "msg": response.statusMessage,
        });
      }
    } catch (e) {
      throw ("Erreur de requête: ${e.toString()}");
    }
  }

  /// Ensemble de capacités du périphérique
  static Future<CapacityResponseEntity> getDevCapacity({
    required String accessToken,
    required String deviceSerial,
  }) async {
    FormData formData = FormData.fromMap({
      "accessToken": accessToken,
      "deviceSerial": deviceSerial,
    });

    try {
      Response response = await Dio().post(devCapacity, data: formData);
      if (response.statusCode == 200) {
        CapacityResponseEntity responseData =
            CapacityResponseEntity.fromJson(response.data);
        return responseData;
      } else {
        // Échec
        return CapacityResponseEntity.fromJson({
          "code": response.statusCode,
          "msg": response.statusMessage,
        });
      }
    } catch (e) {
      throw ("Erreur de requête: ${e.toString()}");
    }
  }
}
