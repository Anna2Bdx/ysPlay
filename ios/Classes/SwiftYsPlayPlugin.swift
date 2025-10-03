
//
//  SwiftYsPlayPlugin.swift
//  ys_play
//
//  Created by 潇洒的然然 on 2022/9/6.
import Flutter
import UIKit
import EZOpenSDKFramework
import Photos

public class SwiftYsPlayPlugin: NSObject, FlutterPlugin,EZPlayerDelegate{
    

    let TAG = "EzVizSDK=======>"
    
    var playerView:UIView? // Vue de lecture

    var pwResult:FlutterBasicMessageChannel? // Canal de configuration réseau
    var ysResult:FlutterBasicMessageChannel? // Canal direct et lecture

    var ezPlayer:EZPlayer? // Lecteur direct et lecture
    var _talkPlayer:EZPlayer? // Interphone

    private var supportTalk:Int = 0 // Capacité d'interphone 0 non supporté 1 full duplex 3 half duplex
    private var isPhone2Dev:Int = 1 // 1 téléphone parle périphérique écoute 0 téléphone écoute périphérique parle
    private var videoPath:String? // Adresse de sauvegarde vidéo
    
    // variables utilisées pour piloter finement le PanTiltZoom
    private let ptzQueue = DispatchQueue(label: "fr.skywave.maison.ptz.queue")  // série
    private var ptzEpoch: Int = 0                                               // token d'intention
    private var currentCmd: EZPTZCommand? = nil

    /**
     * Initialisation
     * Appelé lors de l'enregistrement du plugin, comme la méthode register(), exécuté une seule fois
     */
    init(messenger:FlutterBinaryMessenger){
        super.init()

        /// Instanciation des canaux
        pwResult = FlutterBasicMessageChannel(name: Constants.PEI_WANG_CHANNEL, binaryMessenger: messenger,
                                            codec:FlutterStandardMessageCodec.sharedInstance())
        ysResult = FlutterBasicMessageChannel(name: Constants.PLAYER_STATUS_CHANNEL, binaryMessenger: messenger, codec:
          FlutterStandardMessageCodec.sharedInstance() )
        
        /// Recevoir les notifications envoyées depuis [YsPlayView] et obtenir l'uiView
        NotificationCenter.default.addObserver(self, selector: #selector(notificationAction), name: Notification.Name.init("video_view"), object: nil)
        
    }
    
    deinit {
       /// Supprimer les notifications
       NotificationCenter.default.removeObserver(self)
    }
    
    /// Callback de méthode après réception de la notification
    @objc private func notificationAction(notification: Notification) {
        if notification.object != nil {
            playerView = notification.object as? UIView
        }
    }
    
    
    /**
     * Enregistrer le plugin
     * Appelé lors de l'exécution du programme, et exécuté une seule fois pendant le cycle de vie du projet
     */
    public static func register(with registrar: FlutterPluginRegistrar) {

        let factory = YsPlayViewFactory()
        registrar.register(factory, withId: Constants.CHANNEL)
        
        let channel = FlutterMethodChannel(name: Constants.CHANNEL, binaryMessenger: registrar.messenger())
        let instance = SwiftYsPlayPlugin(messenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        print("SwiftYsPlayPlugin: handle() called with method: \(call.method)")
        if call.method == "init_sdk" {
            /// Initialiser le SDK EZVIZ
            let data:Optional<Dictionary> = call.arguments as? Dictionary<String, String>
            if data != nil && data!["appKey"] != nil {
                let isSuccess:Bool = EZGlobalSDK.initLib(withAppKey: data!["appKey"]!)
                print("\(TAG) Initialisation SDK \(isSuccess ? "réussie" : "échouée")")
                result(isSuccess)
            } else {
                result(false)
            }
        } else if call.method == "set_access_token" {
            /// Autorisation de connexion
            let data:Optional<Dictionary> = call.arguments as? Dictionary<String, String>
            if data != nil && data!["accessToken"] != nil {
                EZGlobalSDK.setAccessToken(data!["accessToken"]!)
                print("\(TAG)accessToken configuré avec succès")
                result(true)
            }else{
                result(false)
            }
        } else if call.method == "startPlayback" {
            /// Démarrer la lecture
            if ezPlayer != nil {
                ezPlayer!.stopPlayback()
                ezPlayer = nil
            }
            let data:Optional<Dictionary> = call.arguments as? Dictionary<String, Any>
            let deviceSerial = data?["deviceSerial"] as? String // Numéro de série du périphérique
            let cameraNo = data?["cameraNo"] as? Int
            let verifyCode = data?["verifyCode"] as? String
            let startTime = data?["startTime"] as? Int
            let endTime = data?["endTime"] as? Int
            
            if deviceSerial == nil || startTime == nil || endTime == nil {
                result(false)
                return
            }
            // 注册播放器
            ezPlayer = createEzPlayer(deviceSerial: deviceSerial!, cameraNo: cameraNo, verifyCode: verifyCode)
            
            let recordFile = EZDeviceRecordFile()
            recordFile.type = 1;
            recordFile.channelType = "D";
            let zone = NSTimeZone.system
            let interval = zone.secondsFromGMT()
            let startDate = Date(timeIntervalSince1970: TimeInterval(startTime!)/1000).addingTimeInterval(TimeInterval(interval))
            recordFile.startTime = startDate
            
            let endDate = Date(timeIntervalSince1970: TimeInterval(endTime!)/1000).addingTimeInterval(TimeInterval(interval))
            recordFile.stopTime = endDate
            
            let bool = ezPlayer!.startPlayback(fromDevice: recordFile)
            print("\(TAG)Démarrage de la lecture \(bool ? "réussi" : "échoué")")
            result(bool)
        } else if call.method == "pause_play_back"{
            /// Pause de la lecture
            if ezPlayer == nil {
                result(false)
                return
            }
            let bool = ezPlayer!.pausePlayback()
            print("\(TAG)Pause de la lecture \(bool ? "réussie" : "échouée")")
            result(bool)
        } else if call.method == "resume_play_back"{
            /// Reprendre la lecture
            if ezPlayer == nil {
                result(false)
                return
            }
            let bool = ezPlayer!.resumePlayback()
            print("\(TAG)Reprise de la lecture \(bool ? "réussie" : "échouée")")
            result(bool)
        } else if call.method == "stopPlayback" {
            /// Arrêter la lecture
            if ezPlayer == nil {
                result(false)
                return
            }
            let bool = ezPlayer!.stopPlayback()
            print("\(TAG)Arrêt de la lecture \(bool ? "réussi" : "échoué")")
            result(bool)
        } else if call.method == "startRealPlay" {
            /// Démarrer le direct
            if(ezPlayer != nil){
                // Arrêter d'abord
                ezPlayer!.stopRealPlay();
                ezPlayer = nil;
            }
            
            let data:Optional<Dictionary> = call.arguments as? Dictionary<String, Any>
            let deviceSerial = data?["deviceSerial"] as? String // Numéro de série du périphérique
            let cameraNo = data?["cameraNo"] as? Int
            let verifyCode = data?["verifyCode"] as? String
            
            if deviceSerial == nil {
                result(false)
                return
            }
            // Enregistrer le lecteur
            ezPlayer = createEzPlayer(deviceSerial: deviceSerial!, cameraNo: cameraNo, verifyCode: verifyCode)

            let isSuccess = ezPlayer!.startRealPlay()
            print("\(TAG) Démarrage du direct \(isSuccess ? "réussi" : "échoué")")
            result(isSuccess)
        } else if call.method == "stopRealPlay" {
            /// Arrêter le direct
            if ezPlayer == nil {
                result(false)
                return
            }
            let isSuccess = ezPlayer!.stopRealPlay()
            print("\(TAG) Arrêt du direct \(isSuccess ? "réussi" : "échoué")")
            result(isSuccess)
        }  else if call.method == "openSound"{
            /// Activer le son
            if ezPlayer == nil {
                result(false)
                return
            }
            let bool = ezPlayer!.openSound()
            print("\(TAG)Activation du son \(bool ? "réussie" : "échouée")")
            result(bool)
        } else if call.method == "closeSound"{
            /// Désactiver le son
            if ezPlayer == nil {
                result(false)
                return
            }
            let bool = ezPlayer!.closeSound()
            print("\(TAG)Désactivation du son \(bool ? "réussie" : "échouée")")
            result(bool)
        } else if call.method == "capturePicture"{
            /// Capture d'écran
            if ezPlayer == nil {
                result(false)
                return
            }
            let image =  ezPlayer!.capturePicture(10)
            if image != nil {
                saveImage2Library(image: image!,callback:  {isSuccess in
                    print("\(self.TAG)Capture d'écran \(isSuccess ? "réussie" : "échouée")")
                    result(isSuccess)
                })
            } else {
                result(false)
            }
        } else if call.method == "start_record" {
            /// Démarrer l'enregistrement
            print("enregistrement demandé")
            if ezPlayer == nil {
                result(false)
                return
            }
            print("on a un ezPlayer")
            // Avant l'enregistrement d'écran, terminer d'abord l'enregistrement précédent
            let documentDir = NSSearchPathForDirectoriesInDomains(FileManager.SearchPathDirectory.documentDirectory,
                                                                                  FileManager.SearchPathDomainMask.userDomainMask, true).first
            let date = String(DateUtil.getCurrentTimeStamp())
            self.videoPath = "\(documentDir ?? "")/\(date).mp4"
            print("\(self.TAG)chemin du record:\(self.videoPath)")
            let isSuccess = self.ezPlayer!.startLocalRecord(withPathExt: self.videoPath)
            print("\(self.TAG)Enregistrement d'écran \(isSuccess ? "réussi": "échoué")")
            result(isSuccess)

        } else if call.method == "ptz" {
            guard let args = call.arguments as? [String: Any],
                  let deviceSerial = args["deviceSerial"] as? String,
                  let cameraNo = args["cameraNo"] as? Int,
                  let actionStr = args["action"] as? String
            else { result(FlutterError(code:"PTZ_BAD_ARGS", message:"Missing args", details:nil)); return }

            let cmdStr = args["command"] as? String
            let speed  = (args["speed"] as? Int) ?? 0

            // Map String -> EZPTZCommand (ou nil si STOP)
            var mapped: EZPTZCommand?
            if let c = cmdStr {
                switch c {
                case "UP":       mapped = .up
                case "DOWN":     mapped = .down
                case "LEFT":     mapped = .left
                case "RIGHT":    mapped = .right
                case "ZOOM_IN":  mapped = .zoomIn
                case "ZOOM_OUT": mapped = .zoomOut
                default:
                  result(FlutterError(code:"PTZ_BAD_COMMAND", message:"Unknown command \(c)", details:nil))
                  return
                }
            }
            let intention: EZPTZCommand? = (actionStr.uppercased() == "START") ? mapped : nil
            ptzSwitch(deviceSerial: deviceSerial, cameraNo: cameraNo, newCmd: intention, speed: speed, flutterResult: result)

        } else if call.method == "stop_record"{
            /// Arrêter l'enregistrement
            if ezPlayer == nil {
                result(false)
                return
            }
            ezPlayer!.stopLocalRecordExt({(isSuccess : Bool) in
                print("\(self.TAG)Arrêt de l'enregistrement d'écran \(isSuccess ? "réussi": "échoué")")
                if self.videoPath != nil {
                    self.saveVideo2Library(path: self.videoPath!, callback: {success in
                        result(success)
                    })
                }else {
                    result(false)
                }
             })
        } else if call.method == "set_video_level"{
            /// Définir la qualité vidéo
            /// videoLevel: 0 fluide, 1 équilibré, 2 haute définition, 3 ultra haute définition. Par défaut haute définition
            let data:Optional<Dictionary> = call.arguments as? Dictionary<String, Any>
            let deviceSerial:String? = data?["deviceSerial"] as? String
            var cameraNo:Int? = data?["cameraNo"] as? Int
            var videoLevel:Int? = data?["videoLevel"] as? Int
            
            if cameraNo == nil {
                cameraNo = 1
            }
            if(videoLevel == nil){
                videoLevel = 2
            }
            if deviceSerial == nil{
                result(false)
                return
            }
            let videoLevelType = getVideoLevelType(videoLevel: videoLevel!)
          
            EZGlobalSDK.setVideoLevel(deviceSerial!, cameraNo: cameraNo!, videoLevel: videoLevelType, completion: { error in
                result(false)
            })
            result(true)
        } else if call.method == "start_config_ap" {
            /// Interface de configuration AP (configuration par point d'accès)
            let data:Optional<Dictionary> = call.arguments as? Dictionary<String, Any>
            let deviceSerial:String? = data?["deviceSerial"] as? String
            let ssid:String? = data?["ssid"] as? String
            let password:String? = data?["password"] as? String
            let verifyCode:String? = data?["verifyCode"] as? String

//            EZOpenSDK.startAPConfigWifi(withSsid: ssid ?? "", password: password ?? "",
//                                        deviceSerial: deviceSerial ?? "", verifyCode: verifyCode ?? "", deviceStatus: wifiConfigStatus)

            EZGlobalSDK.startAPConfigWifi(withSsid: ssid ?? "", password: password ?? "",
                                        deviceSerial: deviceSerial ?? "", verifyCode: verifyCode ?? "", result: apWifiConfigResult)
            
        } else if call.method == "start_config_wifi" {
            /// SmartConfig et configuration par ondes sonores
            let data:Optional<Dictionary> = call.arguments as? Dictionary<String, Any>
            let deviceSerial:String? = data?["deviceSerial"] as? String
            let ssid:String? = data?["ssid"] as? String
            let password:String? = data?["password"] as? String
            let mode:String? = data?["mode"] as? String

            var configMode = EZWiFiConfigMode.smart // Configuration WiFi par défaut
            if mode == "wave"{
                // Configuration par ondes sonores
                configMode = .wave
            }
            EZGlobalSDK.startConfigWifi(ssid ?? "", password: password ?? "", deviceSerial:deviceSerial ?? "",
                                      mode: configMode.rawValue,deviceStatus: wifiConfigStatus)
        } else if call.method == "stop_config" {
            /// Arrêter la configuration réseau
            let data:Optional<Dictionary> = call.arguments as? Dictionary<String, Any>
            var mode:String? = data?["mode"] as? String
            if mode == nil {
                mode = "wifi"
            }
            if mode == "wave" || mode == "wifi" {
                let isSuccess:Bool = EZGlobalSDK.stopConfigWifi()
                print("\(TAG)Arrêt de la configuration réseau \(isSuccess ? "réussi" : "échoué")")
                result(isSuccess)
            } else if mode == "ap" {
                EZGlobalSDK.stopAPConfigWifi()
                result(true)
            } else {
                result(false)
            }
        }  else if call.method == "start_voice_talk"{
            /// Démarrer l'interphone
            if ezPlayer != nil {
                ezPlayer!.closeSound() // Fermer le son de lecture vidéo
            }
            // Obtenir les paramètres
            let data:Optional<Dictionary> = call.arguments as? Dictionary<String, Any>
            let deviceSerial:String? = data?["deviceSerial"] as? String
            let cameraNo:Int? = data?["cameraNo"] as? Int
            let verifyCode:String? = data?["verifyCode"] as? String
            if data?["supportTalk"] != nil {
                supportTalk = (data!["supportTalk"] as! Int)
            }
            if data?["isPhone2Dev"] != nil {
                isPhone2Dev = (data!["isPhone2Dev"] as! Int)
            }
            if _talkPlayer == nil {
                // Créer l'interphone
                _talkPlayer = EZGlobalSDK.createPlayer(withDeviceSerial: deviceSerial!, cameraNo: cameraNo ?? 1)
                _talkPlayer!.setPlayVerifyCode(verifyCode)
                _talkPlayer!.delegate = self
            }else{
                _talkPlayer!.stopVoiceTalk()
            }
            // Démarrer l'interphone
            _talkPlayer!.startVoiceTalk()
        } else if call.method == "stop_voice_talk" {
            /// Arrêter l'interphone
            var isSuccess : Bool = true
            if _talkPlayer != nil {
                isSuccess = _talkPlayer!.stopVoiceTalk()
                print("\(self.TAG)Fin de l'interphone \(isSuccess ? "réussie": "échouée")")
                _talkPlayer!.delegate = nil
                _talkPlayer!.destoryPlayer()
                _talkPlayer = nil
            }
            result(isSuccess)
        } else if call.method == "get_storage_status"{
            /// Obtenir l'état du support de stockage (comme l'initialisation, le progrès du formatage, etc.) Cette interface est une opération chronophage, doit être appelée dans un thread
            let data:Optional<Dictionary> = call.arguments as? Dictionary<String, Any>
            let deviceSerial:String? = data?["deviceSerial"] as? String
            EZGlobalSDK.getStorageStatus(deviceSerial!, completion: { info ,error in
                if let infoList = info as? [EZStorageInfo] {
                    var mapList = Array<Dictionary<String, Any>>()
                    // Parcourir le tableau, convertir le tableau EZStorageInfo en tableau de dictionnaires
                    infoList.forEach { e in
                        var map = ["formatRate":e.formatRate,"index":e.index,"name":e.name ?? "","status":e.status] as [String : Any]
                        mapList.append(map)
                    }
                    let jsonString = self.convertDictionaryArrayToJson(mapList)
                    result(jsonString)
                } else {
                    result(nil)
                }
                
            })
            
        } else if call.method == "format_storage" {
            /// Formater la partition
            let data:Optional<Dictionary> = call.arguments as? Dictionary<String, Any>
            let deviceSerial:String? = data?["deviceSerial"] as? String
            var partitionIndex:Int? = data?["partitionIndex"] as? Int
            if partitionIndex == nil {
                partitionIndex = -1
            }
            
            EZGlobalSDK.formatStorage(deviceSerial!, storageIndex: partitionIndex!) { error in
                result(error == nil)
            }
           

            
        } else if call.method == "dispose" {
            if ezPlayer != nil {
                ezPlayer!.destoryPlayer()
                ezPlayer = nil
            }
            if _talkPlayer != nil {
                _talkPlayer!.destoryPlayer()
                _talkPlayer = nil
            }
        } else {
            result(FlutterMethodNotImplemented)
        }
    }
    
    /**
     * Callback d'erreur pour direct, lecture et interphone
     */
    public func player(_ player: EZPlayer!, didPlayFailed error: Error!) {

        let entity:YsPlayerStatusEntity = YsPlayerStatusEntity()
        entity.isSuccess = false
        if player.isEqual(_talkPlayer) {
            entity.talkErrorInfo = error.localizedDescription
        }else if player.isEqual(ezPlayer) {
            entity.playErrorInfo = error.localizedDescription
        }
        ysResult?.sendMessage(entity.getString())
    }
    
    /**
     * Codes d'état reçus après le succès du direct, de la lecture et de l'interphone
     */
    public func player(_ player: EZPlayer!, didReceivedMessage messageCode: Int) {
        var dict = [String:Any]()
        switch messageCode {
        case 1:
            print("\(TAG)Démarrage du direct")
            dict.updateValue(true, forKey: "isSuccess")
            break
        case 11:
            print("\(TAG)Démarrage de la lecture")
            dict.updateValue(true, forKey: "isSuccess")
            break
        case 4:
            print("\(TAG)Démarrage de l'interphone")
            if _talkPlayer != nil {
                // Les périphériques half-duplex nécessitent une configuration
                if supportTalk == 3{
                    if isPhone2Dev == 0 {
                        // Téléphone écoute, périphérique parle
                        _talkPlayer!.audioTalkPressed(false)
                    } else if isPhone2Dev == 1{
                        // Téléphone parle, périphérique écoute
                        _talkPlayer!.audioTalkPressed(true)
                    }
                }
            }
            dict.updateValue(true, forKey: "isSuccess")
            break
        case 5:
            print("\(TAG)Fin de l'interphone")
            dict.updateValue(true, forKey: "isSuccess")
            break
        default: break
        }
        let message = convertDictionaryToJson(dict: dict)
        ysResult?.sendMessage(message)
    }
    
    /**
     * Dictionnaire vers JSON
     */
    func convertDictionaryToJson(dict : Dictionary<String,Any>) -> String {
        let data = try? JSONSerialization.data(withJSONObject: dict,options: JSONSerialization.WritingOptions.init(rawValue: 0))
        let jsonStr = NSString(data: data!, encoding:String.Encoding.utf8.rawValue)
        return jsonStr! as String
    }
    
    /**
     * Tableau de dictionnaires vers JSON
     */
    func convertDictionaryArrayToJson(_ data: Any) -> String? {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: data, options: [])
            return String(data: jsonData, encoding: .utf8)
        } catch {
            print("Error converting to JSON: \(error.localizedDescription)")
            return nil
        }
    }
    
    /**
     * Sauvegarder l'image dans la galerie
     */
    private func saveImage2Library(image:UIImage,callback:@escaping(_ result:Bool)->Void ) {
        PHPhotoLibrary.shared().performChanges(
            {PHAssetChangeRequest.creationRequestForAsset(from: image)},
            completionHandler:{(isSuccess,error) in
                DispatchQueue.main.async {
                    callback(isSuccess)
            }
        })
    }
    
    
    /**
     * Sauvegarder la vidéo dans la galerie
     */
    private func saveVideo2Library(path:String, callback:@escaping(_ result:Bool)->Void ) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: URL(fileURLWithPath: path))
        }){(success,error) in
            DispatchQueue.main.async {
                if !success {
                    print(">>>>>>>>>Sauvegarde dans la galerie échouée: \(String(describing: error))")
                }
                callback(success)
            }
        }
    }
    
    /*
     * Retourner EZVideoLevelType selon videoLevel
     */
    private func getVideoLevelType (videoLevel:Int) -> EZVideoLevelType {
        var videolevelType:EZVideoLevelType = EZVideoLevelType.levelHigh /* was high */
        switch videoLevel {
        case 0:
            videolevelType = EZVideoLevelType.levelLow /* was low */
        case 1:
            videolevelType = EZVideoLevelType.levelMiddle /* was middle */
        case 2:
            videolevelType = EZVideoLevelType.levelHigh /* was high */
        case 3:
            videolevelType = EZVideoLevelType.levelSuperHigh /* was superHigh */
        default:
            break
        }
        return videolevelType
    }
    
    /// Enregistrer le lecteur
    private func createEzPlayer(deviceSerial:String,cameraNo:Int?,verifyCode:String?) -> EZPlayer {
        let player = EZGlobalSDK.createPlayer(withDeviceSerial: deviceSerial, cameraNo: cameraNo ?? 1)
        if verifyCode != nil {
            player.setPlayVerifyCode(verifyCode)
        }
        player.delegate = self
        player.setPlayerView(self.playerView)
        print("\(TAG)Enregistrement du lecteur réussi")
        return player
    }
    
    /**
     * Callback de configuration AP (point d'accès)
     */
    lazy var apWifiConfigResult = { (isSuccess:Bool) in
        let entity:PeiwangResultEntity = PeiwangResultEntity()
        entity.isSuccess = isSuccess
        entity.msg = isSuccess ? "Configuration AP réussie" : "Configuration AP échouée"
        self.pwResult?.sendMessage(entity.getString())
        EZGlobalSDK.stopConfigWifi()
    }
    
    /**
     * Callback de configuration réseau
     * En raison de l'absence de callback d'échec dans la version 4.20.1, l'utilisateur doit configurer lui-même dans le projet, par exemple en définissant un compte à rebours.
     */
    lazy var wifiConfigStatus = { (status:EZWifiConfigStatus,result:String?)  in
        let entity:PeiwangResultEntity = PeiwangResultEntity()

        switch(status){
        case .DEVICE_PLATFORM_REGISTED:
            print("\(self.TAG)Enregistrement du périphérique sur la plateforme réussi")
            entity.isSuccess = true
            entity.msg = "Enregistrement sur la plateforme réussi"
            self.pwResult?.sendMessage(entity.getString())
            EZGlobalSDK.stopConfigWifi()
            break
        case .DEVICE_WIFI_CONNECTING:
            print("\(self.TAG)Périphérique en cours de connexion au WiFi...")
            break
        case .DEVICE_WIFI_CONNECTED:
            print("\(self.TAG)Connexion Wi-Fi réussie")
            break
         case .DEVICE_ACCOUNT_BINDED:
             print("\(self.TAG)Périphérique déjà lié")
             break
//         case .DEVICE_WIFI_SENT_SUCCESS:
//             print("\(self.TAG)向设备发送WiFi信息成功")
//             break
//         case .DEVICE_WIFI_SENT_FAILED:
//             print("\(self.TAG)向设备发送WiFi信息失败")
//             entity.isSuccess = false
//             entity.msg = "向设备发送WiFi信息失败"
//             self.pwResult?.sendMessage(entity.getString())
//             break
//        case .DEVICE_PLATFORM_REGIST_FAILED:
//            entity.isSuccess = false
//            entity.msg = "注册平台失败"
//            self.pwResult?.sendMessage(entity.getString())
//            break
        default:
            break
        }
    }
    
   private func ptzSwitch(deviceSerial: String,
                            cameraNo: Int,
                            newCmd: EZPTZCommand?,   // nil => STOP
                            speed: Int,              // 0..2 (classique) ou 0..7 (Mix)
                            flutterResult: @escaping FlutterResult) {

       // Nouvelle intention -> nouveau token
       ptzEpoch &+= 1
       let myEpoch = ptzEpoch

       ptzQueue.async { [weak self] in
         guard let self = self else { return }

         // 1) Si une direction est active et change (ou STOP), on envoie d'abord un STOP
         if let prev = self.currentCmd, (newCmd == nil || newCmd != prev) {
           _ = self.controlPTZSync(deviceSerial: deviceSerial,
                                   cameraNo: cameraNo,
                                   cmd: prev,
                                   action: .stop,
                                   speed: 0,
                                   timeout: 3.0)
           // petite barrière pour laisser l'ordre s'appliquer côté device
           usleep(120_000) // 120 ms
         }

         // Intention périmée ?
         guard self.ptzEpoch == myEpoch else { flutterResult(false); return }

         // 2) Démarrer la nouvelle direction si demandé
         if let dir = newCmd {
           // Vérif AVANT envoi (cas tap<600ms)
           guard self.ptzEpoch == myEpoch else { flutterResult(false); return }

           let okStart = self.controlPTZSync(deviceSerial: deviceSerial,
                                             cameraNo: cameraNo,
                                             cmd: dir,
                                             action: .start,
                                             speed: speed,
                                             timeout: 5.0)
           // Pendant le START, l'intention a changé ? -> STOP immédiat pour annuler
           if self.ptzEpoch != myEpoch {
             _ = self.controlPTZSync(deviceSerial: deviceSerial,
                                     cameraNo: cameraNo,
                                     cmd: dir,
                                     action: .stop,
                                     speed: 0,
                                     timeout: 3.0)
             flutterResult(false)
             return
           }

           if okStart { self.currentCmd = dir }
           flutterResult(okStart)
         } else {
           // Intention = STOP
           self.currentCmd = nil
           flutterResult(true)
         }
       }
     }

     /// Appelle controlPTZMix si dispo (vitesse fine 0..7), sinon fallback controlPTZ (0..2).
     /// On l’exécute de façon "synchrone" sur ptzQueue via un sémaphore (pas le main thread).
     private func controlPTZSync(deviceSerial: String,
                                 cameraNo: Int,
                                 cmd: EZPTZCommand,
                                 action: EZPTZAction,
                                 speed: Int,
                                 timeout: TimeInterval) -> Bool {
       let sem = DispatchSemaphore(value: 1)
       _ = sem.wait(timeout: .now()) // prendre le jeton
       var ok = false

       EZGlobalSDK.controlPTZ(deviceSerial, cameraNo: cameraNo, command: cmd, action: action, speed: min(speed, 2)) { error in
                  ok = (error == nil)
                  sem.signal()
                }

       _ = sem.wait(timeout: .now() + timeout)
       sem.signal()
       return ok
     }


}

