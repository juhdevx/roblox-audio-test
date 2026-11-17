package com.voiceshift.bridge.usb

/**
 * The reproducible Quest 3S / Roblox verification procedure, as structured steps the UI can show
 * and the user can mark. Each stage is recorded separately so "the Quest lists a microphone" is
 * never confused with "Roblox actually transmits my processed voice".
 *
 * Results are entered by the person running the test; the app never marks hardware steps passed.
 */
object QuestValidationProcedure {

    enum class Stage(val title: String) {
        PHONE_ROUTE("1. Phone output"),
        QUEST_SYSTEM("2. Quest recognises an external microphone"),
        QUEST_SIGNAL("3. Signal reaches the Quest"),
        ROBLOX_IN_GAME("4. Roblox in-game capture"),
    }

    data class Step(val id: String, val stage: Stage, val title: String, val instructions: String)

    val steps: List<Step> = listOf(
        Step(
            "phone.tone", Stage.PHONE_ROUTE, "Test tone on the external output",
            "Devices tab: select the USB/wired output, start the engine and enable the 1 kHz test tone at -18 dBFS. " +
                "Route checks must show the output routed to the cable with a healthy level.",
        ),
        Step(
            "phone.voice", Stage.PHONE_ROUTE, "Processed voice on the external output",
            "Disable the tone, speak, and confirm the output meter moves. Use headphones on a second output or " +
                "listen on the far end; never monitor through the phone speaker next to the microphone.",
        ),
        Step(
            "quest.listed", Stage.QUEST_SYSTEM, "Quest lists the USB input",
            "On the headset, enable the experimental external-microphone option if your Horizon OS version has one " +
                "(location changes between releases), plug in the USB audio input device, and note whether it is " +
                "listed or selected. Record the Horizon OS version in the note.",
        ),
        Step(
            "quest.probe", Stage.QUEST_SIGNAL, "Quest probe detects the tone",
            "Install VoiceShift Quest Lab on the headset, open 'USB mic probe', select the USB input and confirm the " +
                "1 kHz tone is detected. This proves audio arrives at Android's audio layer on the Quest.",
        ),
        Step(
            "roblox.settings", Stage.ROBLOX_IN_GAME, "Roblox voice is enabled for the account",
            "Voice chat must already be enabled and allowed for the account in Roblox settings (age/eligibility rules " +
                "are Roblox's). VoiceShift does not modify or bypass Roblox eligibility.",
        ),
        Step(
            "roblox.capture", Stage.ROBLOX_IN_GAME, "Another player hears the processed voice",
            "Join a voice-enabled experience with a second account or a friend, speak, and have them confirm they " +
                "hear the processed voice (not the headset's built-in microphone). Only this step proves in-game capture.",
        ),
    )
}
