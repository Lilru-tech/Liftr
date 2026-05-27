package com.lilru.liftr.territory

import androidx.compose.ui.graphics.Color
import java.util.UUID

object TerritoryOwnerColors {
  private val palette: List<Color> = (0 until 48).map { index ->
    val hue = index / 48f * 360f
    Color.hsv(hue, 0.72f, 0.88f)
  }

  fun color(ownerId: String?): Color {
    return palette[paletteIndex(ownerId)]
  }

  fun fill(ownerId: String?, isMine: Boolean): Color {
    return color(ownerId).copy(alpha = if (isMine) 0.52f else 0.28f)
  }

  fun stroke(ownerId: String?, isMine: Boolean): Color {
    val base = color(ownerId)
    return if (isMine) base else base.copy(alpha = 0.82f)
  }

  fun strokeWidth(isMine: Boolean): Float = if (isMine) 2.5f else 1f

  private fun paletteIndex(ownerId: String?): Int {
    if (ownerId.isNullOrBlank()) return 0
    return runCatching {
      val uuid = UUID.fromString(ownerId)
      val bytes = ByteArray(16)
      val msb = uuid.mostSignificantBits
      val lsb = uuid.leastSignificantBits
      for (i in 0 until 8) {
        bytes[i] = ((msb shr (56 - i * 8)) and 0xff).toByte()
        bytes[i + 8] = ((lsb shr (56 - i * 8)) and 0xff).toByte()
      }
      var hash = 5381
      for (byte in bytes) {
        hash = ((hash shl 5) + hash) + (byte.toInt() and 0xFF)
      }
      var secondary = 0
      for (byte in bytes.reversed()) {
        secondary = ((secondary shl 5) + secondary) + (byte.toInt() and 0xFF)
      }
      kotlin.math.abs(hash + secondary * 17) % palette.size
    }.getOrDefault(ownerId.hashCode().let { if (it < 0) -it else it } % palette.size)
  }
}
