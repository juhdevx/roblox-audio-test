package com.voiceshift.bridge.usb

import android.content.Context
import android.content.pm.PackageManager
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager

/**
 * Lists USB devices attached in host mode and identifies USB Audio Class interfaces. Reading
 * descriptors does not require USB permission; opening a device would, and is never done.
 */
class UsbAudioInspector(context: Context) {
    private val appContext = context.applicationContext
    private val usbManager: UsbManager? = appContext.getSystemService(UsbManager::class.java)

    val usbHostSupported: Boolean
        get() = appContext.packageManager.hasSystemFeature(PackageManager.FEATURE_USB_HOST)

    fun attachedDevices(): List<UsbDeviceSummary> =
        usbManager?.deviceList?.values?.map { it.toSummary() }.orEmpty()

    private fun UsbDevice.toSummary(): UsbDeviceSummary {
        val classes = mutableListOf<Int>()
        var streaming = 0
        for (i in 0 until interfaceCount) {
            val itf = getInterface(i)
            classes += itf.interfaceClass
            if (itf.interfaceClass == UsbDeviceSummary.USB_CLASS_AUDIO &&
                itf.interfaceSubclass == UsbDeviceSummary.USB_SUBCLASS_AUDIOSTREAMING
            ) {
                streaming++
            }
        }
        return UsbDeviceSummary(
            deviceName = deviceName,
            vendorId = vendorId,
            productId = productId,
            productName = runCatching { productName }.getOrNull(),
            manufacturerName = runCatching { manufacturerName }.getOrNull(),
            interfaceClasses = classes.distinct(),
            audioStreamingInterfaces = streaming,
        )
    }
}
