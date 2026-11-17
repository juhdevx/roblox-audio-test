package com.voiceshift.vr

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import dagger.hilt.android.testing.HiltAndroidRule
import dagger.hilt.android.testing.HiltAndroidTest
import dagger.hilt.android.testing.HiltTestApplication
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/**
 * Launches the real MainActivity with the production Hilt graph on the JVM (Robolectric) and walks
 * through every tab. The native .so cannot load on the JVM, which also exercises the "engine
 * unavailable" path that must not crash the app.
 */
@HiltAndroidTest
@RunWith(AndroidJUnit4::class)
@Config(sdk = [35], application = HiltTestApplication::class)
class AppSmokeTest {

    @get:Rule(order = 0)
    val hilt = HiltAndroidRule(this)

    @get:Rule(order = 1)
    val compose = createAndroidComposeRule<MainActivity>()

    @Test
    fun launchesAndNavigatesAllTabs() {
        compose.onNodeWithText("VoiceShift VR").assertIsDisplayed()
        compose.onNodeWithText("Start voice").assertIsDisplayed()
        // Without the native library the app explains the problem instead of crashing.
        assertTrue(
            compose.onAllNodesWithText("native audio engine could not be loaded", substring = true)
                .fetchSemanticsNodes().isNotEmpty(),
        )

        compose.onNodeWithText("Voice").performClick()
        compose.onNodeWithText("Save as preset", substring = true).assertIsDisplayed()
        compose.onNodeWithText("Soft feminine").assertIsDisplayed()

        compose.onNodeWithText("Models").performClick()
        compose.onNodeWithText("Voice models").assertIsDisplayed()
        compose.onNodeWithText("Import .onnx file", substring = true).assertIsDisplayed()

        compose.onNodeWithText("Devices").performClick()
        compose.onNodeWithText("Devices & routing").assertIsDisplayed()

        compose.onNodeWithText("Settings").performClick()
        compose.onNodeWithText("DSP quality").assertIsDisplayed()

        compose.onNodeWithText("Home").performClick()
        compose.onNodeWithText("Start voice").assertIsDisplayed()
    }
}
