package com.example.ys_play;

import android.os.Handler;
import android.os.Message;

import androidx.annotation.NonNull;

import com.example.ys_play.Interface.YsResultListener;
import com.example.ys_play.utils.LogUtils;
import com.videogo.errorlayer.ErrorInfo;
import com.videogo.exception.ErrorCode;
import com.videogo.openapi.EZConstants;

class YsPlayViewHandler extends Handler {
    private final YsResultListener ysResult;

    public YsPlayViewHandler(YsResultListener ysResult){
        this.ysResult = ysResult;
    }

    @Override
    public void handleMessage(@NonNull Message msg) {
        ErrorInfo errorinfo = new ErrorInfo();
        if(msg.obj!=null && msg.obj.getClass() == ErrorInfo.class){
            errorinfo = (ErrorInfo) msg.obj;
        }
        switch (msg.what) {
            case EZConstants.EZPlaybackConstants.MSG_REMOTEPLAYBACK_PLAY_SUCCUSS:
                LogUtils.d("Lecture en différé réussie");
                ysResult.onPlaySuccess();
                break;
            case EZConstants.EZPlaybackConstants.MSG_REMOTEPLAYBACK_PLAY_FAIL:
            case EZConstants.EZRealPlayConstants.MSG_REALPLAY_PLAY_FAIL:
                // Obtenir la description de l'échec de lecture
                String description = errorinfo.description;
                // Callback d'informations d'erreur
                ysResult.onPlayError(description);
                break;
            case EZConstants.MSG_VIDEO_SIZE_CHANGED:
                // Callback de résolution d'écran vidéo analysée
                break;
            case EZConstants.EZRealPlayConstants.MSG_REALPLAY_PLAY_SUCCESS:
                LogUtils.d("Lecture en direct réussie");
                ysResult.onPlaySuccess();
                break;
            case EZConstants.EZRealPlayConstants.MSG_REALPLAY_VOICETALK_FAIL:
                handleVoiceTalkFailed(errorinfo);
                break;
            case EZConstants.EZRealPlayConstants.MSG_REALPLAY_VOICETALK_SUCCESS:
                LogUtils.d("Interphone réussi");
                ysResult.onTalkSuccess();
                break;
            default:
                break;
        }
    }

    /**
     * Échec de l'interphone
     * @param errorInfo: informations d'erreur
     */
    private void handleVoiceTalkFailed(ErrorInfo errorInfo) {
        String errorDes = "";
        switch (errorInfo.errorCode) {
            case ErrorCode.ERROR_TRANSF_DEVICE_TALKING:
                errorDes = "Une seule conversation avec un périphérique à la fois, veuillez arrêter les autres conversations avant de réessayer";
                break;
            case ErrorCode.ERROR_TRANSF_DEVICE_PRIVACYON:
                errorDes = "Impossible de parler en mode protection de la vie privée";
                break;
            case ErrorCode.ERROR_TRANSF_DEVICE_OFFLINE:
                errorDes = "Périphérique hors ligne";
                break;
            case ErrorCode.ERROR_TTS_MSG_REQ_TIMEOUT:
            case ErrorCode.ERROR_TTS_MSG_SVR_HANDLE_TIMEOUT:
            case ErrorCode.ERROR_TTS_WAIT_TIMEOUT:
            case ErrorCode.ERROR_TTS_HNADLE_TIMEOUT:
                errorDes="Timeout de la requête, interphone fermé";
                break;
            case ErrorCode.ERROR_CAS_AUDIO_SOCKET_ERROR:
            case ErrorCode.ERROR_CAS_AUDIO_RECV_ERROR:
            case ErrorCode.ERROR_CAS_AUDIO_SEND_ERROR:
                errorDes="Anomalie réseau, interphone fermé";
                break;
            case ErrorCode.ERROR_INNER_STREAM_TIMEOUT:
                errorDes="Timeout du flux, actualiser et réessayer";
                break;
            case 110031:// Sous-compte ou utilisateur EZVIZ sans autorisation
                break;
            default:
                errorDes = "" + errorInfo.errorCode;
                break;
        }
        ysResult.onTalkError(errorDes);
    }



}
