package com.familyguard.child

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import kotlin.math.PI
import kotlin.math.sin

/** Generates a very quiet two-note ambient pad without shipping a large file. */
class CalmTonePlayer {
    @Volatile
    private var running = false
    private var track: AudioTrack? = null
    private var thread: Thread? = null

    @Synchronized
    fun start(preset: String = "meadow") {
        stop()
        running = true
        val sampleRate = 44100
        val minBuffer = AudioTrack.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        ).coerceAtLeast(2048)
        track = if (android.os.Build.VERSION.SDK_INT >= 23) {
            AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build(),
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setSampleRate(sampleRate)
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build(),
                )
                .setBufferSizeInBytes(minBuffer * 2)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()
        } else {
            @Suppress("DEPRECATION")
            AudioTrack(
                AudioManager.STREAM_MUSIC,
                sampleRate,
                AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                minBuffer * 2,
                AudioTrack.MODE_STREAM,
            )
        }
        track?.play()
        thread = Thread {
            val buffer = ShortArray(2048)
            var phaseA = 0.0
            var phaseB = 0.0
            val notes = when (preset) {
                "moonlight" -> doubleArrayOf(174.61, 220.0, 261.63, 349.23)
                "ocean" -> doubleArrayOf(146.83, 196.0, 220.0, 293.66)
                else -> doubleArrayOf(220.0, 261.63, 329.63, 392.0)
            }
            var sampleIndex = 0L
            while (running) {
                for (i in buffer.indices) {
                    val time = sampleIndex.toDouble() / sampleRate
                    val note = notes[((time / 3.0).toInt()) % notes.size]
                    val pulse = 0.55 + 0.45 * sin(PI * (time % 3.0) / 3.0)
                    val swell = if (preset == "ocean") 0.7 + 0.3 * sin(time * 0.5) else 1.0
                    val fadeIn = (time / 1.2).coerceIn(0.0, 1.0)
                    val sample = (sin(phaseA) * 0.045 + sin(phaseB) * 0.025 * pulse) * swell * fadeIn
                    buffer[i] = (sample * Short.MAX_VALUE).toInt().toShort()
                    phaseA = (phaseA + 2.0 * PI * notes[0] / sampleRate) % (2.0 * PI)
                    phaseB = (phaseB + 2.0 * PI * note * 2 / sampleRate) % (2.0 * PI)
                    sampleIndex++
                }
                try {
                    track?.write(buffer, 0, buffer.size)
                } catch (_: IllegalStateException) {
                    break
                }
            }
        }.also { it.start() }
    }

    @Synchronized
    fun stop() {
        running = false
        try {
            thread?.join(250)
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        }
        thread = null
        track?.run {
            try {
                stop()
            } catch (_: IllegalStateException) {
            }
            release()
        }
        track = null
    }
}
