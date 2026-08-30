package com.bashx.app

import android.app.Application
import com.bashx.app.data.Paths
import com.bashx.app.vpn.MihomoBridge

class BashXApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Paths.init(this)
        MihomoBridge.init(this)
    }
}
