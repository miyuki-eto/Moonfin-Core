package org.moonfin.nativevideo

import androidx.media3.common.DataReader
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.extractor.DefaultExtractorInput
import androidx.media3.extractor.DiscardingTrackOutput
import androidx.media3.extractor.Extractor
import androidx.media3.extractor.ExtractorOutput
import androidx.media3.extractor.PositionHolder
import androidx.media3.extractor.SeekMap
import androidx.media3.extractor.TrackOutput
import androidx.media3.extractor.text.DefaultSubtitleParserFactory
import io.github.peerless2012.ass.media.AssHandler
import io.github.peerless2012.ass.media.type.AssRenderType
import java.io.ByteArrayInputStream
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE)
class MoonfinMatroskaLayoutTest {
    @Test fun editedTracksAfterClustersRemainReadableAndSeekable() {
        // Synthetic MKV: SeekHead, Info, one VP8 sample, Tracks, then Cues.
        // Header-only edits can produce this layout without changing any samples.
        val bytes = javaClass.getResourceAsStream("/mkv/tracks-after-clusters.mkv")!!.readBytes()
        fun inputAt(position: Long): DefaultExtractorInput {
            val stream = ByteArrayInputStream(bytes, position.toInt(), bytes.size - position.toInt())
            return DefaultExtractorInput(
                DataReader { target, offset, length -> stream.read(target, offset, length) },
                position,
                bytes.size.toLong(),
            )
        }
        val extractor = MoonfinMatroskaExtractor(
            DefaultSubtitleParserFactory(), AssHandler(AssRenderType.CUES),
        )
        var seekMap: SeekMap? = null
        var format: Format? = null
        var samples = 0
        extractor.init(object : ExtractorOutput {
            override fun track(id: Int, type: Int): TrackOutput =
                object : TrackOutput by DiscardingTrackOutput() {
                    override fun format(value: Format) { format = value }
                    override fun sampleMetadata(
                        timeUs: Long, flags: Int, size: Int, offset: Int,
                        cryptoData: TrackOutput.CryptoData?,
                    ) { samples++ }
                }
            override fun endTracks() = Unit
            override fun seekMap(value: SeekMap) { seekMap = value }
        })
        var input = inputAt(0)
        val position = PositionHolder()
        var ended = false
        for (attempt in 0 until 100) {
            when (extractor.read(input, position)) {
                Extractor.RESULT_SEEK -> input = inputAt(position.position)
                Extractor.RESULT_END_OF_INPUT -> { ended = true; break }
            }
        }
        extractor.release()

        assertTrue("Extractor did not reach the end", ended)
        assertEquals(MimeTypes.VIDEO_VP8, format?.sampleMimeType)
        assertEquals(1, samples)
        val map = requireNotNull(seekMap)
        assertTrue("Relocated Tracks must retain seeking", map.isSeekable)
        assertTrue(map.getSeekPoints(500_000).first.position in 1 until bytes.size.toLong())
    }
}
