# ysPlay

Plugin Flutter pour streaming en direct EZVIZ Cloud, compatible Android et iOS

## Fonctionnalités
1. Intégration de compte (connexion autorisée)  
2. Streaming en direct (avec réglage de résolution)  
3. Lecture différée  
4. Enregistrement pendant le streaming direct et la lecture différée  
5. Capture d'écran pendant le streaming direct et la lecture différée  
6. Contrôle PTZ  
7. Configuration réseau  
8. Interphone (half-duplex et full-duplex)  

## Préparation
Avant l'intégration, il est recommandé de lire la [documentation officielle](http://open.ys7.com/help/36).

## Installation
    dependencies: 
        ys_play: ^0.0.6

## Configuration du projet
### Côté Android  
Ajouter dans le fichier AndroidMainfest.xml :
```       
```       
<!-- Permissions requises pour les fonctionnalités de base -->
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.READ_PHONE_STATE" />
<!-- Permissions requises pour la configuration réseau -->
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.CHANGE_NETWORK_STATE" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
<uses-permission android:name="android.permission.CHANGE_WIFI_STATE" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />
<!-- Permission de lecture - sélection de l'album local -->
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
<!-- Permission d'écriture - stockage des photos ou vidéos capturées -->
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.WAKE_LOCK"/>
<!-- Géolocalisation réseau -->
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<!-- Permissions microphone -->
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS"/>
```
```       

Ajouter dans le répertoire app du projet :

    defaultConfig {
       ...
        ndk {
            abiFilters "armeabi-v7a", "arm64-v8a"
        }
    }

     sourceSets {
        main {
            jniLibs.srcDirs = ['libs']
        }
    }

Obfuscation du code :

    #========Interface externe du SDK=======#
    -keep class com.ezviz.opensdk.** { *;}

    #========Bibliothèques HIK suivantes=======#
    -dontwarn com.ezviz.**
    -keep class com.ezviz.** { *;}

    -dontwarn com.ez.**
    -keep class com.ez.** { *;}

    -dontwarn com.hc.CASClient.**
    -keep class com.hc.CASClient.** { *;}

    -dontwarn com.videogo.**
    -keep class com.videogo.** { *;}

    -dontwarn com.hik.TTSClient.**
    -keep class com.hik.TTSClient.** { *;}

    -dontwarn com.hik.stunclient.**
    -keep class com.hik.stunclient.** { *;}

    -dontwarn com.hik.streamclient.**
    -keep class com.hik.streamclient.** { *;}

    -dontwarn com.hikvision.sadp.**
    -keep class com.hikvision.sadp.** { *;}

    -dontwarn com.hikvision.netsdk.**
    -keep class com.hikvision.netsdk.** { *;}

    -dontwarn com.neutral.netsdk.**
    -keep class com.neutral.netsdk.** { *;}

    -dontwarn com.hikvision.audio.**
    -keep class com.hikvision.audio.** { *;}

    -dontwarn com.mediaplayer.audio.**
    -keep class com.mediaplayer.audio.** { *;}

    -dontwarn com.hikvision.wifi.**
    -keep class com.hikvision.wifi.** { *;}

    -dontwarn com.hikvision.keyprotect.**
    -keep class com.hikvision.keyprotect.** { *;}

    -dontwarn com.hikvision.audio.**
    -keep class com.hikvision.audio.** { *;}

    -dontwarn org.MediaPlayer.PlayM4.**
    -keep class org.MediaPlayer.PlayM4.** { *;}
    #========Fin des bibliothèques HIK=======#

    #========Bibliothèques open source tierces suivantes=======#
    # JNA
    -dontwarn com.sun.jna.**
    -keep class com.sun.jna.** { *;}

    # Gson
    -keepattributes *Annotation*
    -keep class sun.misc.Unsafe { *; }
    -keep class com.idea.fifaalarmclock.entity.***
    -keep class com.google.gson.stream.** { *; }

    # OkHttp
    # JSR 305 annotations are for embedding nullability information.
    -dontwarn javax.annotation.**
    # A resource is loaded with a relative path so the package of this class must be preserved.
    -keepnames class okhttp3.internal.publicsuffix.PublicSuffixDatabase
    # Animal Sniffer compileOnly dependency to ensure APIs are compatible with older versions of Java.
    -dontwarn org.codehaus.mojo.animal_sniffer.*
    # OkHttp platform used only on JVM and when Conscrypt dependency is available.
    -dontwarn okhttp3.internal.platform.ConscryptPlatform
    # Doit être ajouté, sinon la compilation échouera
    -dontwarn okio.**
    #========Fin des bibliothèques open source tierces=======#


### Côté iOS
## Ajouter dans info.plist :  

1. Permission d'accès aux photos : Si vous devez utiliser les fonctions d'enregistrement et de capture d'écran du lecteur de la plateforme ouverte avec sauvegarde, vous devez configurer les permissions d'accès aux photos.   
```              
<key>NSPhotoLibraryAddUsageDescription</key>  
<string>$(PRODUCT_NAME) doit accéder à l'album photo</string>  
<key>NSPhotoLibraryUsageDescription</key>  
<string>$(PRODUCT_NAME) doit accéder à l'album photo</string>  
```

2. Permission microphone : Si vous devez utiliser la fonction d'interphone de l'appareil, vous devez configurer les permissions microphone. Il est impératif de demander les permissions microphone au système iOS avant d'initier l'interphone, sinon cela causera des dysfonctionnements.        
```
<key>NSMicrophoneUsageDescription</key>    
<string>$(PRODUCT_NAME) doit accéder au microphone</string>
```

3. Permission caméra : Si vous devez implémenter la fonction de scan de code pour ajouter des appareils comme dans la démo, vous devez configurer les permissions caméra. 
```
<key>NSCameraUsageDescription</key>    
<string>$(PRODUCT_NAME) doit accéder à la caméra</string>
```

4. Permissions de configuration réseau : Si vous devez utiliser la configuration réseau des appareils EZVIZ Cloud, vous devez configurer les permissions de configuration réseau  
 ```       
<key>NSLocalNetworkUsageDescription</key>  
<string>$(PRODUCT_NAME) doit accéder au réseau local pour la configuration WiFi</string>  
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>  
<string>$(PRODUCT_NAME) doit accéder à la localisation pour la configuration WiFi</string>  
<key>NSLocationAlwaysUsageDescription</key>
<string>$(PRODUCT_NAME) doit accéder à la localisation pour la configuration WiFi</string>  
<key>NSLocationWhenInUseUsageDescription</key>  
<string>$(PRODUCT_NAME) doit accéder à la localisation pour la configuration WiFi</string>  
```

## Configuration dans Xcode
Dans Xcode -> Runner -> Target -> Target-Signing & Capabilities, ajouter les 2 capacités suivantes :
1. Access WiFi Information (obtenir le nom du WiFi connecté, nécessaire pour la configuration réseau) ;
2. Hotspot Configuration (connexion à un WiFi spécifique, nécessaire pour la configuration réseau).
Note : Ces 2 capacités doivent également être ajoutées dans les certificats sur le site officiel de l'App Store.


   
	

	




