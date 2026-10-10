package it.agendanails.agenda_nails

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Widget "Agenda di oggi". L'app salva i testi dei prossimi 7 giorni (chiave = data):
 * il widget sceglie quello di oggi, quindi resta giusto anche senza aprire l'app.
 * Si aggiorna quando cambiano i dati e ogni 30 minuti.
 */
class WidgetOggi : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val oggi = SimpleDateFormat("yyyy-MM-dd", Locale.ITALY).format(Date())
        var titolo = "Agenda"
        var sottotitolo = "Apri l'app per aggiornare"
        val righe = ArrayList<String>()
        try {
            val giorni = JSONObject(widgetData.getString("giorni", null) ?: "{}")
            val g = giorni.optJSONObject(oggi)
            if (g != null) {
                titolo = g.optString("titolo", titolo)
                sottotitolo = g.optString("sottotitolo", "")
                val elenco = g.optJSONArray("righe")
                if (elenco != null) {
                    for (i in 0 until elenco.length()) righe.add(elenco.optString(i))
                }
            }
        } catch (e: Exception) {
            // dati non leggibili: si mostra il testo predefinito
        }
        val idRighe = intArrayOf(R.id.riga1, R.id.riga2, R.id.riga3, R.id.riga4, R.id.riga5)
        for (id in appWidgetIds) {
            val v = RemoteViews(context.packageName, R.layout.widget_oggi)
            v.setTextViewText(R.id.titolo, titolo)
            v.setTextViewText(R.id.sottotitolo, sottotitolo)
            for (i in idRighe.indices) {
                if (i < righe.size) {
                    v.setTextViewText(idRighe[i], righe[i])
                    v.setViewVisibility(idRighe[i], View.VISIBLE)
                } else {
                    v.setViewVisibility(idRighe[i], View.GONE)
                }
            }
            v.setOnClickPendingIntent(R.id.radice, HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java))
            appWidgetManager.updateAppWidget(id, v)
        }
    }
}
