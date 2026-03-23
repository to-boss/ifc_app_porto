package com.example.myapplication.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.myapplication.ar.ARViewModel

@Composable
fun FixturePicker(
    viewModel: ARViewModel,
    modifier: Modifier = Modifier
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
        modifier = modifier
            .clip(RoundedCornerShape(topStart = 16.dp, bottomStart = 16.dp))
            .background(Color.Black.copy(alpha = 0.70f))
            .padding(8.dp)
    ) {
        FixtureButton(
            emoji = "\uD83D\uDEBD",
            label = "WC",
            onClick = { viewModel.selectFixture("Toilet", "Objekt_WC.ifc") }
        )
        FixtureButton(
            emoji = "\uD83E\uDEA3",
            label = "Sink",
            onClick = { viewModel.selectFixture("Sink", "Objekt_Waschbecken.ifc") }
        )
        FixtureButton(
            emoji = "\u267F",
            label = "WC Acc.",
            onClick = { viewModel.selectFixture("WC Accessible", "Objekt_WC_Beh_.ifc") }
        )
        FixtureButton(
            emoji = "\uD83D\uDCD0",
            label = "Wall",
            onClick = { viewModel.selectFixture("Wall", "Wall") }
        )

        Spacer(Modifier.height(4.dp))

        Button(
            onClick = { viewModel.dismissFixturePicker() },
            colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF444444)),
            modifier = Modifier
                .width(60.dp)
                .height(36.dp),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(0.dp)
        ) {
            Text(
                text = "\u2715",
                color = Color.White,
                fontSize = 16.sp,
                fontWeight = FontWeight.Bold
            )
        }
    }
}

@Composable
private fun FixtureButton(
    emoji: String,
    label: String,
    onClick: () -> Unit
) {
    Button(
        onClick = onClick,
        colors = ButtonDefaults.buttonColors(
            containerColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.85f)
        ),
        modifier = Modifier
            .size(60.dp),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(4.dp),
        shape = RoundedCornerShape(12.dp)
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            Text(text = emoji, fontSize = 20.sp)
            Text(
                text = label,
                color = Color.White,
                fontSize = 9.sp,
                fontWeight = FontWeight.Medium,
                textAlign = TextAlign.Center
            )
        }
    }
}
