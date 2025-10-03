import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:ys_play/src/entity/capacity_response_entity.dart';
import 'package:ys_play/src/entity/ys_player_status.dart';
import 'package:ys_play/src/entity/ys_pw_result.dart';
import 'package:ys_play/src/entity/ys_request_entity.dart';
import 'package:ys_play/src/entity/ys_response_entity.dart';
import 'package:ys_play/src/ys_http_api.dart';

enum YsMediaType {
  playback, //Lecture différée
  real, //Direct
}

/// État de lecture
enum YsPlayStatus {
  onPrepareing,
  onPlaying,
  onStop,
  onError;
}

class YsPlay {
  /// Canal de communication de la plateforme
  static const _channel = MethodChannel("com.example.ys_play");

  /// Canal d'état de lecture
  static const BasicMessageChannel<dynamic> _playerStatus = BasicMessageChannel(
      "com.example.ys_play/player_status", StandardMessageCodec());

  /// Canal de résultats de configuration réseau
  static const BasicMessageChannel<dynamic> _pwResultChannel =
      BasicMessageChannel(
          "com.example.ys_play/pei_wang", StandardMessageCodec());

  /// Écoute de l'état de lecture
  static void onResultListener({
    required Function() onSuccess,
    required Function(String errorInfo) onPlayError,
    required Function(String errorInfo) onTalkError,
  }) {
    _playerStatus.setMessageHandler((message) async {
      if (message != null && message is String && message.isNotEmpty) {
        Map<String, dynamic> map = json.decode(message);
        YsPlayerStatus status = YsPlayerStatus.fromJson(map);
        if (status.isSuccess == true) {
          onSuccess();
        } else if (status.playErrorInfo != null) {
          onPlayError(status.playErrorInfo!);
        } else if (status.talkErrorInfo != null) {
          onTalkError(status.talkErrorInfo!);
        }
      }
    });
  }

  /// Écoute des résultats de configuration réseau
  static void peiwangResultListener(Function(YsPwResult) onResult) {
    _pwResultChannel.setMessageHandler((message) async {
      if (message != null && message is String && message.isNotEmpty) {
        Map<String, dynamic> msg = json.decode(message);
        onResult(YsPwResult.fromJson(msg));
      }
    });
  }

  /// Initialiser le SDK EZVIZ
  /// Seul paramètre obligatoire :`appKey`. Généré après création de l'application sur la plateforme officielle du SDK EZVIZ.
  static Future<bool> initSdk(String appKey) async {
    bool result = await _channel.invokeMethod("init_sdk", {'appKey': appKey});
    return result;
  }

  /// Définir l'`accessToken`
  /// Jeton d'accès retourné par le serveur au client pour l'authentification.
  static Future<bool> setAccessToken(String accessToken) async {
    bool result = await _channel
        .invokeMethod("set_access_token", {'accessToken': accessToken});
    return result;
  }

  /// Démarrer la lecture différée
  ///
  /// A 5 paramètres d'entrée :
  /// * Dont 3 paramètres obligatoires :
  ///   1.`deviceSerial`:numéro de série de l'appareil, généralement obtenu en scannant le QR code de l'appareil, obligatoire;
  ///   2.`startTime`:heure de début;
  ///   3.`endTime`:heure de fin.
  /// * 2 paramètres optionnels :
  ///   1.`verifyCode`:si la vidéo nécessite un chiffrement, peut être transmis; par défaut le code de vérification à 6 chiffres de l'appareil;
  ///   2.`cameraNo`:numéro de canal de l'appareil, par défaut 1, peut être omis.
  static Future<bool> startPlayback({
    required String deviceSerial,
    required int startTime,
    required int endTime,
    String? verifyCode,
    int? cameraNo,
  }) async {
    bool result = await _channel.invokeMethod("startPlayback", {
      'deviceSerial': deviceSerial,
      'startTime': startTime,
      'endTime': endTime,
      'verifyCode': verifyCode,
      'cameraNo': cameraNo,
    });
    return result;
  }

  /// Arrêter la lecture différée
  static Future<bool> stopPlayback() async {
    await _channel.invokeMethod("stopPlayback");
    return true;
  }

  /// Pause de la lecture différée
  static Future<bool> pausePlayback() async {
    bool result = await _channel.invokeMethod("pause_play_back");
    return result;
  }

  /// Reprendre la lecture différée
  static Future<bool> resumePlayback() async {
    bool result = await _channel.invokeMethod("resume_play_back");
    return result;
  }

  /// Démarrer le direct
  ///
  /// A 3 paramètres d'entrée :
  /// Dont `deviceSerial` est obligatoire, `verifyCode` et `cameraNo` sont optionnels.
  static Future<bool> startRealPlay({
    required String deviceSerial,
    String? verifyCode,
    int? cameraNo,
  }) async {
    return await _channel.invokeMethod("startRealPlay", {
      'deviceSerial': deviceSerial,
      'verifyCode': verifyCode,
      'cameraNo': cameraNo,
    });
  }

  /// Arrêter le direct
  static Future<bool> stopRealPlay() async {
    await _channel.invokeMethod("stopRealPlay");
    return true;
  }

  /// Activer le son
  static Future<bool> openSound() async {
    bool result = await _channel.invokeMethod("openSound");
    return result;
  }

  /// Désactiver le son
  static Future<bool> closeSound() async {
    bool result = await _channel.invokeMethod("closeSound");
    return result;
  }

  /// Capture d'écran
  static Future capturePicture() async {
    var result = await _channel.invokeMethod("capturePicture");
    return result;
  }

  /// Démarrer l'enregistrement
  static Future<bool> startRecordWithFile() async {
    return await _channel.invokeMethod('start_record');
  }

  /// Arrêter l'enregistrement
  static Future<bool> stopRecordWithFile() async {
    return await _channel.invokeMethod('stop_record');
  }

  /// Définir la qualité vidéo
  ///
  /// `deviceSerial`:numéro de série de l'appareil, généralement obtenu en scannant le QR code de l'appareil, obligatoire;
  /// `cameraNo`:numéro de canal de l'appareil, par défaut 1, peut être omis;
  /// `videoLevel`:  0-fluide 1-équilibré 2-haute qualité, par défaut 2.
  static Future<bool> setVideoLevel({
    required String deviceSerial,
    int cameraNo = 1,
    int videoLevel = 2,
  }) async {
    var result = await _channel.invokeMethod(
      "set_video_level",
      {
        "deviceSerial": deviceSerial,
        "cameraNo": cameraNo,
        "videoLevel": videoLevel,
      },
    );
    return result;
  }

  static Future<bool> startPTZ({
    required String deviceSerial,
    required int cameraNo,
    required String command, // "UP","DOWN","LEFT","RIGHT","ZOOM_IN","ZOOM_OUT"
    int speed = 0,          // 0 = lent, 1 = moyen, 2 = rapide
  }) =>
      _channel.invokeMethod<bool>('ptz', {
        'deviceSerial': deviceSerial,
        'cameraNo': cameraNo,
        'command': command,
        'action': 'START',
        'speed': speed,
      }).then((v) => v ?? false);

  static Future<bool> stopPTZ({
    required String deviceSerial,
    required int cameraNo,
    required String command,
  }) =>
      _channel.invokeMethod<bool>('ptz', {
        'deviceSerial': deviceSerial,
        'cameraNo': cameraNo,
        'command': command,
        'action': 'STOP',
        'speed': 0, // valeur numérique entre 0 et 7
      }).then((v) => v ?? false);

  /// Contrôle PTZ - démarrage
  ///
  /// `accessToken`:jeton d'accès retourné par le serveur au client pour l'authentification;
  /// `deviceSerial`:numéro de série de l'appareil, généralement obtenu en scannant le QR code de l'appareil, obligatoire;
  /// `cameraNo`:numéro de canal de l'appareil, par défaut 1, peut être omis;
  /// `direction`:0-haut, 1-bas, 2-gauche, 3-droite, 4-haut-gauche, 5-bas-gauche, 6-haut-droite, 7-bas-droite, 8-zoom avant, 9-zoom arrière,
  ///            10-mise au point proche, 11-mise au point éloignée;
  /// `speed`:0-lent, 1-modéré, 2-rapide, pour les appareils Hikvision le paramètre ne peut pas être 0. Par défaut 1.
  static Future<YsResponseEntity> ptzStart({
    required String accessToken,
    required String deviceSerial,
    required int channelNo,
    required int direction,
    int? speed,
  }) async {
    return await YsHttpApi.devPtzStart(
      accessToken: accessToken,
      deviceSerial: deviceSerial,
      channelNo: channelNo,
      direction: direction,
      speed: speed,
    );
  }

  /// Contrôle PTZ - arrêt
  static Future<YsResponseEntity> ptzStop({
    required String accessToken,
    required String deviceSerial,
    required int channelNo,
    int? direction,
  }) async {
    return await YsHttpApi.devPtzStop(
      accessToken: accessToken,
      deviceSerial: deviceSerial,
      channelNo: channelNo,
      direction: direction,
    );
  }

  /// Obtenir les capacités de l'appareil
  static Future<CapacityResponseEntity> getDevCapacity({
    required String accessToken,
    required String deviceSerial,
  }) async {
    return await YsHttpApi.getDevCapacity(
      accessToken: accessToken,
      deviceSerial: deviceSerial,
    );
  }

  /// Miroir/Rotation
  static Future<YsResponseEntity> ptzMirror(
      YsRequestEntity requestEntity) async {
    return await YsHttpApi.devPtzMirror(requestEntity);
  }

  /// Libérer les ressources
  static Future<void> dispose() async {
    await _channel.invokeMethod("dispose");
  }

  /// Mode de configuration réseau sans fil
  /// mode: wifi-configuration wifi, wave-configuration par onde sonore
  static Future<void> startConfigWifi({
    required String deviceSerial,
    required String ssid,
    String? password,
    String? mode,
  }) async {
    await _channel.invokeMethod(
      "start_config_wifi",
      {
        'deviceSerial': deviceSerial,
        'ssid': ssid,
        'password': password,
        'mode': mode,
      },
    );
  }

  /// Mode de configuration par point d'accès
  static Future<void> startConfigAP({
    required String deviceSerial,
    required String ssid,
    String? password,
    String? verifyCode,
    String? routerName,
  }) async {
    await _channel.invokeMethod(
      "start_config_ap",
      {
        'deviceSerial': deviceSerial,
        'ssid': ssid,
        'password': password,
        'verifyCode': verifyCode,
        'routerName': routerName,
      },
    );
  }

  /// Arrêter la configuration réseau
  static Future<bool> stopConfigPw({required String mode}) async {
    bool result = await _channel.invokeMethod('stop_config', {'mode': mode});
    return result;
  }

  /// Démarrer l'interphone
  static Future<bool> startVoiceTalk({
    required String deviceSerial,
    String? verifyCode,
    int cameraNo = 1,
    int isPhone2Dev = 1, //1-téléphone parle appareil écoute 0-téléphone écoute appareil parle
    int supportTalk = 1, //1-full duplex 3-half duplex
  }) async {
    Map<String, dynamic> argsParam = {
      "deviceSerial": deviceSerial,
      "verifyCode": verifyCode,
      "cameraNo": cameraNo,
      "isPhone2Dev": isPhone2Dev,
      "supportTalk": supportTalk,
    };
    bool result = await _channel.invokeMethod("start_voice_talk", argsParam);
    return result;
  }

  /// Arrêter l'interphone
  static Future<bool> stopVoiceTalk() async {
    bool result = await _channel.invokeMethod("stop_voice_talk");
    return result;
  }

  /// Obtenir l'état du support de stockage (comme l'initialisation, le progrès du formatage, etc.)
  static Future getStorageStatus({required String deviceSerial}) async {
    return await _channel
        .invokeMethod("get_storage_status", {'deviceSerial': deviceSerial});
  }

  /// Formater selon le numéro de partition
  static Future formatStorage({
    required String deviceSerial,
    int? index,
  }) async {
    return await _channel.invokeMethod("format_storage", {
      'deviceSerial': deviceSerial,
      'partitionIndex': index,
    });
  }
}
