package com.example.myapplication.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.myapplication.ar.ARState

@Composable
fun GuideCard(
    state: ARState,
    alignmentPointCount: Int,
    modifier: Modifier = Modifier
) {
    val (stepNumber, instruction) = when (state) {
        ARState.COACHING -> 1 to "Scan the floor slowly to detect surfaces"
        ARState.ALIGNING -> 2 to "Tap two points on the floor edge to align the room ($alignmentPointCount/2)"
        ARState.CALIBRATING -> 3 to "Rotate with two fingers to fine-tune alignment"
        ARState.LOADING -> 4 to "Loading IFC model..."
        ARState.PREVIEWING -> 5 to "Move the phone to position the room, then tap Place"
        ARState.ROOM_PLACED -> 6 to "Room placed. Select fixtures or draw walls. Tap elements to edit."
        ARState.WALL_START -> 6 to "Tap the first point of the wall on the floor"
        ARState.WALL_END -> 6 to "Tap the second point to finish the wall"
        ARState.WALL_ADJUST -> 6 to "Adjust wall height and thickness, then confirm"
        ARState.ELEMENT_MOVING -> 6 to "Tap a new position on the floor to move the element"
        ARState.FIXTURE_PREVIEWING -> 6 to "Move phone to position the fixture, then tap to place"
    }

    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier
            .clip(RoundedCornerShape(12.dp))
            .background(Color.Black.copy(alpha = 0.65f))
            .padding(horizontal = 14.dp, vertical = 10.dp)
    ) {
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier
                .size(28.dp)
                .clip(CircleShape)
                .background(MaterialTheme.colorScheme.primary)
        ) {
            Text(
                text = stepNumber.toString(),
                color = Color.White,
                fontSize = 13.sp,
                fontWeight = FontWeight.Bold
            )
        }
        Spacer(Modifier.width(10.dp))
        Text(
            text = instruction,
            color = Color.White,
            fontSize = 14.sp,
            fontWeight = FontWeight.Medium
        )
    }
}
