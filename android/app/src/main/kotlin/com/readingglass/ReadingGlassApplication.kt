package com.readingglass

import android.app.Application
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader

class ReadingGlassApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        PDFBoxResourceLoader.init(applicationContext)
    }
}
