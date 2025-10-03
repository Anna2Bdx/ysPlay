package com.example.ys_play;

import android.app.Application;
import android.content.Intent;
import android.graphics.SurfaceTexture;
import android.net.Uri;
import android.os.Environment;
import android.os.Handler;
import android.os.Looper;
import android.view.TextureView;
import android.widget.Toast;
import android.media.MediaScannerConnection;
import android.content.Context;
import android.content.ContentResolver;
import android.content.ContentValues;
import android.provider.MediaStore;
import android.util.Log;


import androidx.annotation.NonNull;

import com.example.ys_play.Entity.PeiwangResultEntity;
import com.example.ys_play.Entity.YsPlayerStatusEntity;
import com.example.ys_play.Interface.YsResultListener;
import com.example.ys_play.utils.LogUtils;
import com.example.ys_play.utils.TimeUtils;
import com.ezviz.sdk.configwifi.EZConfigWifiErrorEnum;
import com.ezviz.sdk.configwifi.EZConfigWifiInfoEnum;
import com.google.gson.Gson;
import com.videogo.exception.BaseException;
import com.videogo.openapi.EZConstants;
import com.videogo.openapi.EZGlobalSDK;
import com.videogo.openapi.EZOpenSDKListener;
import com.videogo.openapi.EZPlayer;
import com.videogo.openapi.bean.EZStorageStatus;
import com.videogo.wificonfig.APWifiConfig;

import java.util.Calendar;
import java.util.List;
import java.util.Objects;
import java.io.File;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.FileInputStream;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import io.flutter.BuildConfig;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.BasicMessageChannel;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.StandardMessageCodec;

public class YsPlayPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler,TextureView.SurfaceTextureListener{

    private Application application;
    private EZPlayer ezPlayer; // Lecteur vidéo
    private EZPlayer talkPlayer; // Lecteur interphone

    private TextureView textureView; // Vue de lecture
    BasicMessageChannel<Object> ysResult; // Canal de résultats pour la lecture, le direct et l'interphone
    BasicMessageChannel<Object> pwResult; // Canal de résultats pour la configuration réseau

    private Integer supportTalk; // 0-non supporté 1-full duplex 3-half duplex
    private Integer isPhone2Dev; // 0-périphérique parle, téléphone écoute; 1-téléphone parle, périphérique écoute;

    private Integer partitionIndex; // Numéro de partition de la caméra

    private File lastRecordFile;

    private ExecutorService network;
    private Handler main;

    private final java.util.concurrent.atomic.AtomicInteger ptzEpoch = new java.util.concurrent.atomic.AtomicInteger(0);
    private volatile EZConstants.EZPTZCommand currentCmd = null;


    /**
     * Initialisation du plugin
     * Exécuté uniquement lorsque l'application démarre, après l'enregistrement du plugin.
     * @param binding: permet d'obtenir le contenu du contexte, messenger, etc.
     */

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        application = (Application) binding.getApplicationContext();
        BinaryMessenger messenger = binding.getBinaryMessenger();
        /// Enregistrer la vue de lecture
        binding.getPlatformViewRegistry().registerViewFactory(
                Constants.CHANNEL,
                new YsPlayViewFactory((textureView) -> {
                    LogUtils.d(""+this.textureView);
                    this.textureView = textureView;
                    // Définir la Surface d'affichage du lecteur
                    textureView.setSurfaceTextureListener(this);
                })
        );

        network = Executors.newSingleThreadExecutor();          // pour les appels réseau SDK
        main = new Handler(Looper.getMainLooper());             // pour renvoyer result.* au thread UI


        /// Établir le canal de communication entre Flutter et Android
        new MethodChannel(messenger, Constants.CHANNEL).setMethodCallHandler(this);

        /// Transmettre des messages au côté Flutter lorsque l'état du lecteur change
        ysResult =  new BasicMessageChannel<>(messenger, Constants.PLAYER_STATUS_CHANNEL, new StandardMessageCodec());

        /// Transmettre des messages au côté Flutter lorsque les résultats de configuration réseau changent
        pwResult =  new BasicMessageChannel<>(messenger, Constants.PEI_WANG_CHANNEL, new StandardMessageCodec());

    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    }

    private void waitForFileStable(File f, int sleepMs, int maxTries) {
        long last = -1;
        int stableHits = 0;
        for (int i = 0; i < maxTries; i++) {
            long len = f.length();
            if (len > 0 && len == last) {
                stableHits++;
                if (stableHits >= 2) return; // taille stable 2 fois d'affilée
            } else {
                stableHits = 0;
            }
            last = len;
            try { Thread.sleep(sleepMs); } catch (InterruptedException ignore) {}
        }
    }

    private Uri moveVideoToMediaStore(File source) {
        if (source == null || !source.exists()) return null;
        try {
            ContentResolver resolver = application.getContentResolver();
            ContentValues values = new ContentValues();
            values.put(MediaStore.Video.Media.DISPLAY_NAME, source.getName());
            values.put(MediaStore.Video.Media.MIME_TYPE, "video/mp4");
            if (android.os.Build.VERSION.SDK_INT >= 29) {
                values.put(MediaStore.Video.Media.RELATIVE_PATH,
                        Environment.DIRECTORY_DCIM + "/EZVIZ");
                values.put(MediaStore.Video.Media.IS_PENDING, 1);
            }
            Uri uri = resolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values);
            if (uri == null) return null;

            try (java.io.InputStream in = new java.io.FileInputStream(source);
                 java.io.OutputStream out = resolver.openOutputStream(uri)) {
                byte[] buf = new byte[8192];
                int n;
                while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
                out.flush();
            }
            if (android.os.Build.VERSION.SDK_INT >= 29) {
                ContentValues publish = new ContentValues();
                publish.put(MediaStore.Video.Media.IS_PENDING, 0);
                resolver.update(uri, publish, null, null);
            } else {
                MediaScannerConnection.scanFile(
                        application, new String[]{ source.getAbsolutePath() },
                        new String[]{ "video/mp4" }, null
                );
            }
            return uri;
        } catch (Exception e) {
            android.util.Log.w("EZVIZ", "Move to MediaStore failed", e);
            return null;
        }
    }

    private File waitForFinalOrTemp(File finalFile, long timeoutMs) {
        File tempFile = new File(finalFile.getAbsolutePath() + "_temp");
        long end = System.currentTimeMillis() + timeoutMs;
        long lastLenFinal = -1, lastLenTemp = -1, stable = 0;

        while (System.currentTimeMillis() < end) {
            boolean hasFinal = finalFile.exists() && finalFile.length() > 0;
            boolean hasTemp  = tempFile.exists()  && tempFile.length()  > 0;

            if (hasFinal) return finalFile;

            // si le temp grossit encore, on attend
            long lenFinal = finalFile.exists() ? finalFile.length() : -1;
            long lenTemp  = tempFile.exists()  ? tempFile.length()  : -1;

            if (lenFinal == lastLenFinal && lenTemp == lastLenTemp && (hasFinal || hasTemp)) {
                stable++;
                if (stable >= 2) break; // 2 mesures stables consécutives
            } else {
                stable = 0;
            }

            lastLenFinal = lenFinal;
            lastLenTemp  = lenTemp;

            try { Thread.sleep(200); } catch (InterruptedException ignore) {}
        }

        // Si le final n’existe pas mais le temp est non-vide: essayer de renommer
        File tempFile2 = new File(finalFile.getAbsolutePath() + "_temp");
        if (!finalFile.exists() && tempFile2.exists() && tempFile2.length() > 0) {
            // tentative de rename -> finalise “manuellement”
            // noinspection ResultOfMethodCallIgnored
            tempFile2.renameTo(finalFile);
            if (finalFile.exists() && finalFile.length() > 0) return finalFile;
            return tempFile2; // fallback: publier tel quel
        }

        return finalFile.exists() ? finalFile : null;
    }

    // Appel unique pour exprimer l’INTENTION courante (null = STOP)
    private void ptzSwitch(final String deviceSerial,
                           final int cameraNo,
                           final EZConstants.EZPTZCommand newCmd, // null => STOP
                           final int speed,
                           final MethodChannel.Result result) {

        final int myEpoch = ptzEpoch.incrementAndGet();

        network.execute(() -> {
            try {
                boolean ok = true;

                // 1) Si on change de direction ou on s'arrête, STOP d'abord la cmd active
                if (currentCmd != null && (newCmd == null || newCmd != currentCmd)) {
                    ok = EZGlobalSDK.getInstance().controlPTZ(
                            deviceSerial, cameraNo, currentCmd,
                            EZConstants.EZPTZAction.EZPTZActionSTOP, 0
                    );
                    // petite barrière pour éviter l'emballement côté device/cloud
                    try { Thread.sleep(120); } catch (InterruptedException ignored) {}
                }

                // Si entre-temps une nouvelle intention est arrivée, on abandonne
                if (ptzEpoch.get() != myEpoch) return;

                // 2) Démarrer la nouvelle direction si demandée
                if (newCmd != null) {
                    ok = EZGlobalSDK.getInstance().controlPTZ(
                            deviceSerial, cameraNo, newCmd,
                            EZConstants.EZPTZAction.EZPTZActionSTART, speed
                    );
                    if (ok) currentCmd = newCmd;
                } else {
                    currentCmd = null;
                }

                final boolean res = ok;
                main.post(() -> result.success(res));

            } catch (Throwable t) {
                main.post(() -> result.error("PTZ_ERROR", String.valueOf(t.getMessage()), null));
            }
        });
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            /// Initialiser le SDK EZVIZ
            case "init_sdk":
                EZGlobalSDK.showSDKLog(BuildConfig.DEBUG);
                String appKey = call.argument("appKey");
                boolean initResult = EZGlobalSDK.initLib(this.application, appKey);
                LogUtils.d("Initialisation du SDK EZVIZ "+(initResult?"réussie":"échouée"));
                result.success(initResult);
                break;
            /// Définir l'accessToken
            case "set_access_token":
                String accessToken = call.argument("accessToken");
                EZGlobalSDK.getInstance().setAccessToken(accessToken);
                LogUtils.d("Token configuré avec succès");
                result.success(true);
                break;
            /// Démarrer la lecture
            case "startPlayback":
                if(ezPlayer != null){
                    // Arrêter d'abord
                    ezPlayer.stopPlayback();
                    ezPlayer = null;
                }
                // Paramètres transmis depuis Flutter
                String deviceSerial = call.argument("deviceSerial");
                String verifyCode = call.argument("verifyCode");
                Integer cameraNo = call.argument("cameraNo");
                Long startTime = call.argument("startTime");
                Long endTime = call.argument("endTime");

                // Initialiser le lecteur
                ezPlayer = initEzPlayer(deviceSerial,verifyCode,cameraNo);

                if(startTime != null && endTime != null){
                    final Calendar startCalendar = Calendar.getInstance();
                    startCalendar.setTimeInMillis(startTime);
                    final Calendar endCalendar = Calendar.getInstance();
                    endCalendar.setTimeInMillis(endTime);
                    boolean isSuccess = ezPlayer.startPlayback(startCalendar, endCalendar);
                    LogUtils.d("Démarrage de la lecture "+(isSuccess?"réussi":"échoué"));
                    result.success(isSuccess);
                }else{
                    LogUtils.d("startTime et endTime ne peuvent pas être vides");
                    result.success(false);
                }
                break;
            /// Pause de la lecture
            case "pause_play_back":
                if(ezPlayer != null){
                    boolean isPause = ezPlayer.pausePlayback();
                    LogUtils.d("Pause de la lecture "+(isPause?"réussie":"échouée"));
                    result.success(isPause);
                }else {
                    result.success(false);
                }
                break;
            /// Reprendre la lecture
            case "resume_play_back":
                if(ezPlayer != null){
                    boolean isResume = ezPlayer.resumePlayback();
                    LogUtils.d("Reprise de la lecture "+(isResume?"réussie":"échouée"));
                    result.success(isResume);
                }else {
                    result.success(false);
                }
                break;
            /// Arrêter la lecture
            case "stopPlayback":
                if(ezPlayer != null){
                    boolean isSuccess = ezPlayer.stopPlayback();
                    LogUtils.d("Arrêt de la lecture "+(isSuccess?"réussi":"échoué"));
                    result.success(isSuccess);
                } else {
                    result.success(false);
                }
                 break;
            /// Démarrer le direct
            case "startRealPlay":
                if(ezPlayer != null){
                    // Arrêter d'abord
                    ezPlayer.stopRealPlay();
                    ezPlayer = null;
                }
                // Paramètres transmis depuis Flutter
                deviceSerial = call.argument("deviceSerial");
                verifyCode = call.argument("verifyCode");
                cameraNo = call.argument("cameraNo");

                // Enregistrer le lecteur
                ezPlayer = initEzPlayer(deviceSerial,verifyCode,cameraNo);

                boolean realResult = ezPlayer.startRealPlay();
                LogUtils.d("Démarrage du direct "+(realResult?"réussi":"échoué"));
                result.success(realResult);
                break;
            /// Arrêter le direct
            case "stopRealPlay":
                if(ezPlayer != null){
                    boolean stopRealResult = ezPlayer.stopRealPlay();
                    LogUtils.d("Arrêt du direct "+(stopRealResult?"réussi":"échoué"));
                    result.success(stopRealResult);
                } else {
                    result.success(false);
                }
                break;
            /// Activer le son
            case "openSound":
                if(ezPlayer==null) return;
                boolean openResult = ezPlayer.openSound();
                result.success(openResult);
                break;
            /// Désactiver le son
            case "closeSound":
                if(ezPlayer==null) return;
                boolean closeResult = ezPlayer.closeSound();
                result.success(closeResult);
                break;
            /// Capture d'écran
            case "capturePicture":
                if(ezPlayer==null) return;
                new Thread(() -> {
                    // Chemin de sauvegarde de l'image
                    String filePath = Environment.getExternalStorageDirectory().getPath() + "/DCIM/" +
                            TimeUtils.dateToString(TimeUtils.getTimeStame(), "yyyyMMddHHmmss") + ".png";
                    int captureResult = ezPlayer.capturePicture(filePath);
                    if(captureResult==0){
                        // Actualiser la galerie
                        application.sendBroadcast(new Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE, Uri.parse("file://" + filePath)));
                    }
                    result.success(captureResult==0);
                }).start();
                break;
            case "ptz": {
                final String deviceSerialPTZ = call.argument("deviceSerial");
                final Integer cameraNoPTZ  = call.argument("cameraNo");
                final String cmdStr        = call.argument("command"); // "UP","DOWN","LEFT","RIGHT","ZOOM_IN","ZOOM_OUT"
                final String actStr        = call.argument("action");  // "START" | "STOP"
                final Integer speedObj     = call.argument("speed");   // 0..2 (ou 0..7)
                final int speed = (speedObj != null) ? speedObj : 0;

                if (deviceSerialPTZ == null || cameraNoPTZ == null || cmdStr == null || actStr == null) {
                    result.error("PTZ_BAD_ARGS", "Missing deviceSerial/cameraNo/command/action", null);
                    break;
                }

                EZConstants.EZPTZCommand mapped = null;
                if (cmdStr != null) {
                    switch (cmdStr) {
                        case "UP":       mapped = EZConstants.EZPTZCommand.EZPTZCommandUp; break;
                        case "DOWN":     mapped = EZConstants.EZPTZCommand.EZPTZCommandDown; break;
                        case "LEFT":     mapped = EZConstants.EZPTZCommand.EZPTZCommandLeft; break;
                        case "RIGHT":    mapped = EZConstants.EZPTZCommand.EZPTZCommandRight; break;
                        case "ZOOM_IN":  mapped = EZConstants.EZPTZCommand.EZPTZCommandZoomIn; break;
                        case "ZOOM_OUT": mapped = EZConstants.EZPTZCommand.EZPTZCommandZoomOut; break;
                        default: result.error("PTZ_BAD_COMMAND", "Unknown: "+cmdStr, null); return;
                    }
                }

                // START => intention = mapped ; STOP => intention = null
                final EZConstants.EZPTZCommand intention =
                        "START".equalsIgnoreCase(actStr) ? mapped : null;

                // lance le séquenceur (barrière STOP incluse)
                ptzSwitch(deviceSerialPTZ, cameraNoPTZ, intention, speed, result);

                return;
            }
            /// Démarrer l'enregistrement
            case "start_record":
                if(ezPlayer==null) return;
                // Arrêter d'abord l'enregistrement du flux en direct local
                ezPlayer.stopLocalRecord();

                // Chemin de sauvegarde vidéo
                //String recordFile = Environment.getExternalStorageDirectory().getPath()
                //        + "/DCIM/" + TimeUtils.dateToString(TimeUtils.getTimeStame(), "yyyyMMddHHmmss") + ".mp4";

                File moviesDir = application.getExternalFilesDir(Environment.DIRECTORY_MOVIES); // app-specific
                if (moviesDir != null && !moviesDir.exists()) moviesDir.mkdirs();

                String fileName = new SimpleDateFormat("yyyyMMddHHmmss", Locale.US)
                        .format(new Date()) + ".mp4";
                File out = new File(moviesDir, fileName);
                lastRecordFile = out;

                ezPlayer.setStreamDownloadCallback(new EZOpenSDKListener.EZStreamDownloadCallback() {
                    @Override public void onSuccess(String filepath) {
                        LogUtils.d("onSuccess du démarrage terminé");
                        // Rendre visible dans la galerie
                        //File src = (filepath != null && !filepath.isEmpty()) ? new File(filepath) : out;
                        //if (!src.exists()) src = out;

                        // 2) attendre que la taille soit stable
                        //waitForFileStable(src, 200, 15); // ~3s max
                        //android.util.Log.d("EZVIZ", "final file size=" + src.length());

                        // 3) publier dans MediaStore (DCIM/EZVIZ)
                        //Uri uri = moveVideoToMediaStore(src);
                        //android.util.Log.d("EZVIZ", "published uri=" + uri);

                        // 4) (optionnel) supprimer la source app-specific pour éviter les doublons
                        // // noinspection ResultOfMethodCallIgnored
                        // src.delete();

                    }
                    @Override public void onError(EZOpenSDKListener.EZStreamDownloadError code) {
                        LogUtils.d("Ezviz - Record callback error: " + code);
                    }
                });

                boolean recordResult = ezPlayer.startLocalRecordWithFile(out.getAbsolutePath());
                result.success(recordResult);
                break;
            /// Arrêter l'enregistrement
            case "stop_record":
                if(ezPlayer==null) { result.success(false); break; }
                boolean stopped = ezPlayer.stopLocalRecord();
                new Thread(() -> {
                    try {
                        if (lastRecordFile != null) {
                            File src = waitForFinalOrTemp(lastRecordFile, 6000); // jusqu’à ~6s
                            if (src != null && src.exists() && src.length() > 0) {
                                Uri uri = moveVideoToMediaStore(src);
                                Log.d("EZVIZ", "publish uri=" + uri + " len=" + src.length());
                            } else {
                                Log.w("EZVIZ", "finalize timeout: final=" +
                                        (lastRecordFile.exists()? lastRecordFile.length(): -1) +
                                        " temp=" + new File(lastRecordFile.getAbsolutePath()+"_temp").length());
                            }
                        }
                    } catch (Exception e) {
                        Log.w("EZVIZ", "stop->publish failed", e);
                    }
                }).start();
                result.success(stopped);
                break;
            /// Définir la qualité vidéo
            /// videoLevel: 0-fluide 1-équilibré 2-haute qualité
            case "set_video_level":
                deviceSerial = call.argument("deviceSerial");
                cameraNo = call.argument("cameraNo");
                Integer videoLevel = call.argument("videoLevel");
                if(cameraNo==null) cameraNo=1;
                if(videoLevel==null) videoLevel=2;

                Integer finalCameraNo = cameraNo;
                Integer finalVideoLevel = videoLevel;
                new Thread(){
                    public void run(){
                        Looper.prepare();
                        new Handler().post(() -> {
                            try {
                                boolean vlResult =  EZGlobalSDK.getInstance().setVideoLevel(deviceSerial, finalCameraNo, finalVideoLevel);
                                result.success(vlResult);
                            } catch ( BaseException e) {
                                LogUtils.d(""+e);
                                Toast.makeText(application, e.toString(), Toast.LENGTH_SHORT).show();
                                result.success(false);
                            }
                        });
                        Looper.loop();
                    }
                }.start();
                break;
            /*
             * Démarrer la configuration WiFi
             * @since 4.8.3
             * @param context  contexte de l'activité de l'application
             * @param deviceSerial   numéro de série du périphérique à configurer
             * @param ssid  SSID du WiFi à connecter
             * @param password  mot de passe du WiFi à connecter
             * @param mode      mode de configuration réseau, toute combinaison des modes énumérés dans EZWiFiConfigMode
             *                  EZWiFiConfigMode.EZWiFiConfigSmart: configuration réseau normale (WiFi);
             *                  EZWiFiConfigMode.EZWiFiConfigWave: configuration réseau par ondes sonores (Wave)
             * @param back     callback de configuration
             */
            case "start_config_wifi":
                deviceSerial = call.argument("deviceSerial");
                String ssid = call.argument("ssid");
                String password = call.argument("password");
                String mode = call.argument("mode");
                int configMode=EZConstants.EZWiFiConfigMode.EZWiFiConfigSmart;// Configuration WiFi par défaut
                if(Objects.equals(mode,"wave")){
                    // Configuration par ondes sonores
                    configMode = EZConstants.EZWiFiConfigMode.EZWiFiConfigWave;
                }
                EZGlobalSDK.getInstance().startConfigWifi(
                        application.getApplicationContext(),
                        deviceSerial,
                        ssid,
                        password,
                        configMode,
                        mEZStartConfigWifiCallback
                );
                break;
            /*
             * Interface de configuration AP (configuration par point d'accès)
             * @param ssid SSID du WiFi
             * @param password mot de passe du WiFi
             * @param deviceSerial numéro de série du périphérique
             * @param verifyCode code de vérification du périphérique
             * @param routerName nom du point d'accès du périphérique, peut être vide, par défaut "EZVIZ_"+numéro de série du périphérique
             * @param routerPassword mot de passe du point d'accès du périphérique, peut être vide, par défaut "EZVIZ_"+code de vérification du périphérique
             * @param isAutoConnectDeviceHotSpot s'il faut se connecter automatiquement au point d'accès du périphérique, nécessite l'autorisation de scanner le WiFi; si le développeur a confirmé que le téléphone est connecté au point d'accès du périphérique, passer false
             * @param apConfigCallback callback de résultat
             */
            case "start_config_ap":
                ssid = call.argument("ssid");
                password = call.argument("password");
                deviceSerial = call.argument("deviceSerial");
                verifyCode = call.argument("verifyCode");

                EZGlobalSDK.getInstance().startAPConfigWifiWithSsid(
                        ssid,
                        password,
                        deviceSerial,
                        verifyCode,
                        "EZVIZ_"+ deviceSerial,
                "EZVIZ_"+ verifyCode,
                 true,
                        apConfigCallback
                );
                break;

            /// Arrêter la configuration réseau
            case "stop_config":
                mode = call.argument("mode");
                if(Objects.equals(mode, "wave") || Objects.equals(mode, "wifi")){
                  boolean stopConfigResult =  EZGlobalSDK.getInstance().stopConfigWiFi();
                    LogUtils.d("Arrêt de la configuration réseau: "+(stopConfigResult?"réussi":"échoué"));
                    result.success(stopConfigResult);
                }else if(Objects.equals(mode,"ap")){
                    // Point d'accès
                    EZGlobalSDK.getInstance().stopAPConfigWifiWithSsid();
                    LogUtils.d("Arrêt de la configuration réseau: réussi");
                    result.success(true);
                }else{
                    result.success(false);
                }
                break;

            /// Démarrer l'interphone
            case "start_voice_talk":
                // Fermer le son du lecteur
                if(ezPlayer!=null) ezPlayer.closeSound();
                // Obtenir les paramètres d'interphone
                deviceSerial = call.argument("deviceSerial");
                verifyCode = call.argument("verifyCode");
                cameraNo = call.argument("cameraNo");
                supportTalk = call.argument("supportTalk");
                isPhone2Dev = call.argument("isPhone2Dev");
                if(cameraNo ==null) cameraNo =1;
                if(supportTalk==null) supportTalk = 0;
                if(isPhone2Dev==null) isPhone2Dev = 1;

                if(talkPlayer == null) {
                    talkPlayer = EZGlobalSDK.getInstance().createPlayer(deviceSerial, cameraNo);
                    // Définir le Handler, ce handler sera utilisé pour transmettre les messages du lecteur vers le handler
                    talkPlayer.setHandler(new YsPlayViewHandler(ysResultListener));
                    // Les périphériques cryptés nécessitent un mot de passe
                    talkPlayer.setPlayVerifyCode(verifyCode);
                }else{
                    talkPlayer.stopVoiceTalk();
                }
                // Démarrer l'interphone
                talkPlayer.startVoiceTalk();
                break;
            /// Arrêter l'interphone
            case "stop_voice_talk":
               boolean isSuccess = true;
                if(talkPlayer != null){
                    isSuccess = talkPlayer.stopVoiceTalk();
                    LogUtils.d("Arrêt de l'interphone "+(isSuccess?"réussi":"échoué"));
                    talkPlayer.release();
                    talkPlayer = null;
                }
                result.success(isSuccess);
                break;
            /// Obtenir l'état du support de stockage (comme l'initialisation, le progrès du formatage, etc.) Cette interface est une opération chronophage, doit être appelée dans un thread
            case "get_storage_status":
                deviceSerial = call.argument("deviceSerial");
                new Thread() {
                    @Override
                    public void run() {
                        Looper.prepare();
                        try {
                           List<EZStorageStatus> statusList = EZGlobalSDK.getInstance().getStorageStatus(deviceSerial);
                           result.success(new Gson().toJson(statusList));
                        } catch (BaseException e) {
                            e.printStackTrace();
                            LogUtils.d(e.toString());
                            result.success(null);
                        }
                        Looper.loop();
                    }
                }.start();
                break;

            /// Formater la partition
            case "format_storage":
                deviceSerial = call.argument("deviceSerial");
                partitionIndex = call.argument("partitionIndex");
                if(partitionIndex==null) partitionIndex = -1;

                new Thread() {
                    @Override
                    public void run() {
                        Looper.prepare();
                        try {
                           boolean formatResult = EZGlobalSDK.getInstance().formatStorage(deviceSerial,partitionIndex);
                           result.success(formatResult);
                        } catch (BaseException e) {
                            e.printStackTrace();
                            result.success(false);
                        }
                        Looper.loop();
                    }
                }.start();
                break;
            /// Libérer les ressources
            case "dispose":
                if(ezPlayer!=null){
                    ezPlayer.setSurfaceHold(null);
                    ezPlayer.release();
                }
                if(talkPlayer != null){
                    talkPlayer.release();
                }
                break;
            default:
                result.notImplemented();
                break;
        }
    }

    /**
     * Enregistrer le lecteur
     * @param deviceSerial : numéro de série, généralement obtenu en scannant le QR code du périphérique, obligatoire.
     * @param verifyCode : mot de passe de cryptage vidéo, par défaut le code de vérification à 6 chiffres du périphérique, optionnel.
     * @param cameraNo : numéro de canal, par défaut 1, optionnel.
     * @return : composant de lecture
     */
    private EZPlayer initEzPlayer(String deviceSerial,String verifyCode,Integer cameraNo){
        int cNo = 1;
        if(cameraNo != null) cNo = cameraNo;

        EZPlayer player = EZGlobalSDK.getInstance().createPlayer(deviceSerial, cNo);
        // Définir le Handler, ce handler sera utilisé pour transmettre les messages du lecteur vers le handler
        player.setHandler(new YsPlayViewHandler(ysResultListener));
        // Définir la Surface d'affichage du lecteur
        player.setSurfaceEx(textureView.getSurfaceTexture());

        if(verifyCode != null){
            player.setPlayVerifyCode(verifyCode);
        }
        LogUtils.d("Initialisation du lecteur réussie");
        return player;
    }

    /**
     * Callback d'écoute de l'état du lecteur
     */
    YsResultListener ysResultListener = new YsResultListener() {
        @Override
        public void onPlaySuccess() {
            LogUtils.d("onPlaySuccess");
            YsPlayerStatusEntity entity = new YsPlayerStatusEntity();
            entity.setIsSuccess(true);
            ysResult.send(new Gson().toJson(entity));
        }

        @Override
        public void onTalkSuccess() {
            if(talkPlayer!=null) {
                // Half duplex
                if(supportTalk != null && supportTalk == 3){
                    // isPhone2Dev:
                    // 0-téléphone écoute, périphérique parle. Activer le haut-parleur
                    // 1-téléphone parle, périphérique écoute. Désactiver le haut-parleur
                    talkPlayer.setVoiceTalkStatus(isPhone2Dev==1);
                    talkPlayer.setSpeakerphoneOn(isPhone2Dev==0);
                }
            }
        }

        @Override
        public void onPlayError(String errorInfo) {
            YsPlayerStatusEntity entity = new YsPlayerStatusEntity();
            entity.setIsSuccess(false);
            entity.setPlayErrorInfo(errorInfo);
            ysResult.send(new Gson().toJson(entity));
        }

        @Override
        public void onTalkError(String errorInfo) {
            YsPlayerStatusEntity entity = new YsPlayerStatusEntity();
            entity.setIsSuccess(false);
            entity.setTalkErrorInfo(errorInfo);
            ysResult.send(new Gson().toJson(entity));
        }
    };

    /**
     * Callback de configuration réseau smartConfig
     */
    EZOpenSDKListener.EZStartConfigWifiCallback mEZStartConfigWifiCallback =
            new EZOpenSDKListener.EZStartConfigWifiCallback() {
                @Override
                public void onStartConfigWifiCallback(String deviceSerial, EZConstants.EZWifiConfigStatus status) {
                    new Thread(){
                        public void run(){
                            new Handler(Looper.getMainLooper()).post(() -> {
                                PeiwangResultEntity entity = new PeiwangResultEntity();
                                if (status == EZConstants.EZWifiConfigStatus.DEVICE_WIFI_CONNECTED) {
                                    // Connexion WiFi du périphérique réussie
                                    // Arrêter la configuration WiFi
                                    LogUtils.d("smart config — Connexion WiFi du périphérique réussie");
                                } else if (status == EZConstants.EZWifiConfigStatus.DEVICE_PLATFORM_REGISTED) {
                                    // Arrêter la configuration WiFi
                                    // Enregistrement du périphérique sur la plateforme réussi, peut appeler l'interface d'ajout de périphérique pour ajouter le périphérique
                                    entity.setIsSuccess(true);
                                    entity.setMsg("Configuration réseau du périphérique réussie");
                                    LogUtils.d("smart config — Enregistrement du périphérique réussi");
                                    pwResult.send(new Gson().toJson(entity));
                                } else {
                                    // Callback d'erreur
                                    if(status.code== EZConfigWifiErrorEnum.CONFIG_TIMEOUT.code){
                                        status.description = "Timeout de configuration réseau";
                                    }
                                    entity.setIsSuccess(false);
                                    entity.setMsg(status.description);
                                    pwResult.send(new Gson().toJson(entity));
                                }
                                EZGlobalSDK.getInstance().stopConfigWiFi();
                            });
                        }
                    }.start();
                }
            };

    /// Callback de résultats de configuration réseau AP
    APWifiConfig.APConfigCallback apConfigCallback = new APWifiConfig.APConfigCallback() {
        @Override
        public void onSuccess() {
            new Thread(){
                public void run(){
                    new Handler(Looper.getMainLooper()).post(() -> LogUtils.d("onSuccess"));
                }
            }.start();
        }

        @Override
        public void onInfo(int code, String message) {
            new Thread(){
                public void run(){
                    new Handler(Looper.getMainLooper()).post(() -> {
                        LogUtils.d("code:"+code);
                        if (code == EZConfigWifiInfoEnum.CONNECTED_TO_PLATFORM.code) {
                            PeiwangResultEntity entity = new PeiwangResultEntity();
                            entity.setIsSuccess(true);
                            entity.setMsg("Configuration réseau par point d'accès réussie");
                            LogUtils.d("CONNECTED_TO_PLATFORM");
                            pwResult.send(new Gson().toJson(entity));
                            EZGlobalSDK.getInstance().stopAPConfigWifiWithSsid();
                        }
                    });
                }
            }.start();
        }

        @Override
        public void OnError(int code) {
            new Thread(){
                public void run(){
                    new Handler(Looper.getMainLooper()).post(() -> {
                        LogUtils.d("Échec de la configuration réseau");
                        PeiwangResultEntity entity = new PeiwangResultEntity();
                        entity.setIsSuccess(false);
                        switch (code) {
                            case 15:
                                entity.setMsg("Timeout de configuration réseau");
                                break;
                            case 1:
                                entity.setMsg("Erreur de paramètres");
                                break;
                            case 2:
                                entity.setMsg("Mot de passe du point d'accès AP du périphérique incorrect");
                                break;
                            case 3:
                                entity.setMsg("Anomalie de connexion au point d'accès AP");
                                break;
                            case 4:
                                entity.setMsg("Erreur de recherche de point d'accès WiFi");
                                break;
                            case 506:
                                entity.setMsg("Utilisateur a annulé activement la configuration réseau par point d'accès");
                                break;
                            default:
                                entity.setMsg("Erreur inconnue: "+code);
                                // Pour plus de codes d'erreur, voir la description relative de la classe d'énumération EZConfigWifiErrorEnum
                                break;
                        }
                        pwResult.send(new Gson().toJson(entity));
                        EZGlobalSDK.getInstance().stopAPConfigWifiWithSsid();
                    });
                }
            }.start();
        }
    };

    @Override
    public void onSurfaceTextureAvailable(SurfaceTexture surface, int width, int height) {
        if (ezPlayer != null) {
            ezPlayer.setSurfaceEx(surface);
        }
    }

    @Override
    public void onSurfaceTextureSizeChanged(SurfaceTexture surface, int width, int height) {
        if (ezPlayer != null) {
            ezPlayer.setSurfaceEx(surface);
        }

    }

    @Override
    public boolean onSurfaceTextureDestroyed(SurfaceTexture surface) {
        if (ezPlayer != null) {
            ezPlayer.setSurfaceEx(null);
        }

        return false;
    }

    @Override
    public void onSurfaceTextureUpdated(SurfaceTexture surface) {

    }
}
