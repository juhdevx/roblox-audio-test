package com.ninodebolso.app

import android.app.Activity
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Bundle

/** Invisible screen that asks Android for permission to capture the screen, then hands it to the pet. */
class CaptureActivity : Activity() {
    private val req = 41

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState != null) return
        try {
            val mpm = getSystemService(MediaProjectionManager::class.java)
            startActivityForResult(mpm.createScreenCaptureIntent(), req)
        } catch (e: Exception) {
            finish()
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != req) return
        if (resultCode == RESULT_OK && data != null) {
            Store.petActive = true
            Store.changed()
            val look = intent.getBooleanExtra("look", false)
            PetService.start(this, PetService.ACT_EYES) {
                it.putExtra("code", resultCode)
                it.putExtra("data", data)
                it.putExtra("look", look)
            }
        } else {
            PetService.instance?.say("Tudo bem, não vou olhar sua tela.", "feliz")
        }
        finish()
    }
}
