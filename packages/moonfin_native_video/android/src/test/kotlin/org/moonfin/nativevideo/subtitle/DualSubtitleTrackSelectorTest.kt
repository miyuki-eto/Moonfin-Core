package org.moonfin.nativevideo.subtitle

import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.Timeline
import androidx.media3.common.TrackGroup
import androidx.media3.common.TrackSelectionParameters
import androidx.media3.exoplayer.RendererCapabilities
import androidx.media3.exoplayer.source.MediaSource.MediaPeriodId
import androidx.media3.exoplayer.source.TrackGroupArray
import androidx.media3.exoplayer.upstream.BandwidthMeter
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE)
class DualSubtitleTrackSelectorTest {
    @Test fun activatedLanguagePreferencesReachThePrimarySelector() {
        val selector = DualSubtitleTrackSelector(RuntimeEnvironment.getApplication())
        val activations = mutableListOf<TrackSelectionParameters?>()
        selector.init({ parameters ->
            activations += parameters
            selector.onParametersActivated(parameters)
        }, BandwidthMeter.NO_OP)
        val english = Format.Builder().setSampleMimeType(MimeTypes.AUDIO_AAC)
            .setLanguage("en").setChannelCount(2).setSelectionFlags(C.SELECTION_FLAG_DEFAULT).build()
        val japanese = english.buildUpon().setLanguage("ja").setSelectionFlags(0).build()
        val groups = TrackGroupArray(TrackGroup("audio", english, japanese))
        val renderers = arrayOf(renderer(C.TRACK_TYPE_AUDIO), renderer(C.TRACK_TYPE_TEXT))
        fun selectedLanguage() = selector.selectTracks(
            renderers, groups, MediaPeriodId("episode"), Timeline.EMPTY,
        ).selections[0]!!.selectedFormat.language

        assertEquals("en", selectedLanguage())
        selector.setParameters(selector.buildUponParameters().setPreferredAudioLanguage("ja"))
        assertEquals("ja", selectedLanguage())

        selector.suspendSecondary(true)
        assertNull(activations.last())
        assertEquals("ja", selectedLanguage())
        selector.release()
    }

    private fun renderer(type: Int) = object : RendererCapabilities {
        override fun getName() = "test"
        override fun getTrackType() = type
        override fun supportsMixedMimeTypeAdaptation() = RendererCapabilities.ADAPTIVE_NOT_SUPPORTED
        override fun supportsFormat(format: Format) = RendererCapabilities.create(
            if (MimeTypes.getTrackType(format.sampleMimeType) == type) C.FORMAT_HANDLED
            else C.FORMAT_UNSUPPORTED_TYPE,
        )
    }
}
