package com.lilru.liftr.ui.segment

import java.util.UUID

/** El servidor rechazó crear un segmento porque ya hay uno publicado muy similar (ver `duplicate_segment`). */
class SegmentDuplicateException(val existingSegmentId: UUID) : Exception("duplicate_segment")
