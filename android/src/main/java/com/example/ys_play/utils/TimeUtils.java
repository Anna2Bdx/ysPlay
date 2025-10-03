package com.example.ys_play.utils;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.TimeZone;

public class TimeUtils {
    public static String dateFormat_day = "HH:mm";
    public static String dateFormat_month = "MM-dd";

    /**
     * Convertir le temps en chaîne de caractères, par défaut "yyyy-MM-dd HH:mm:ss"
     *
     * @param time temps
     */
    public static String dateToString(long time) {
        return dateToString(time, "yyyy-MM-dd HH:mm:ss");
    }

    /**
     * Convertir le temps en chaîne de caractères, format spécifié
     *
     * @param time   temps
     * @param format format de temps
     */
    public static String dateToString(long time, String format) {
        Date date = new Date(time);
        SimpleDateFormat simpleDateFormat = new SimpleDateFormat(format);
        return simpleDateFormat.format(date);
    }

    public static Date parseServerTime(String serverTime, String format) {
        if (format == null || format.isEmpty()) {
            format = "yyyy-MM-dd HH:mm:ss";
        }
        SimpleDateFormat sdf = new SimpleDateFormat(format, Locale.CHINESE);
        sdf.setTimeZone(TimeZone.getTimeZone("GMT+8:00"));
        Date date = null;
        try {
            date = sdf.parse(serverTime);
        } catch (Exception e) {
        }
        return date;
    }



    /**
     * Obtenir le timestamp actuel
     *
     * @return
     */
    public static long getTimeStame() {
        // Obtenir la valeur en millisecondes actuelle
        long time = System.currentTimeMillis();
        // Convertir la valeur en millisecondes en données de type String
        long time_stamp = time;
        // Retourner
        return time_stamp;
    }
}
