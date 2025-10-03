package com.example.ys_play;

import android.content.Context;

import androidx.annotation.NonNull;

import com.example.ys_play.Interface.OnPlatformViewCreated;

import io.flutter.plugin.common.StandardMessageCodec;
import io.flutter.plugin.platform.PlatformView;
import io.flutter.plugin.platform.PlatformViewFactory;

public class YsPlayViewFactory extends PlatformViewFactory {

    private final OnPlatformViewCreated onViewCreated;

    /// Au démarrage de l'application, appelé 1 fois via la méthode registerViewFactory
    public YsPlayViewFactory(OnPlatformViewCreated onViewCreated) {
        super(StandardMessageCodec.INSTANCE);
        this.onViewCreated = onViewCreated;
    }

    /// Créer la vue
    /// Exécuté 1 fois à chaque appel d'androidView côté Flutter
    @NonNull
    @Override
    public PlatformView create(Context context, int id, Object args) {
        return new YsPlayView(context,onViewCreated);
    }
}
