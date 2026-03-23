package com.example.myapplication.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.example.myapplication.ar.ARViewModel
import com.example.myapplication.ar.BcfIssue
import java.util.UUID

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BcfFormSheet(
    viewModel: ARViewModel,
    elementGlobalId: String? = null,
    cameraX: Float = 0f,
    cameraY: Float = 0f,
    cameraZ: Float = 0f,
    dirX: Float = 0f,
    dirY: Float = 0f,
    dirZ: Float = -1f,
    fovDegrees: Float = 60f
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false)

    var title by remember { mutableStateOf("") }
    var description by remember { mutableStateOf("") }
    var assignee by remember { mutableStateOf("") }
    var priority by remember { mutableStateOf("Normal") }
    var status by remember { mutableStateOf("Open") }

    val priorities = listOf("Critical", "Major", "Normal", "Minor")
    val statuses = listOf("Open", "InProgress", "Resolved", "Closed")

    ModalBottomSheet(
        onDismissRequest = { viewModel.dismissBcfForm() },
        sheetState = sheetState
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 8.dp)
        ) {
            Text(
                text = "Report Issue",
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold
            )
            Spacer(Modifier.height(16.dp))

            OutlinedTextField(
                value = title,
                onValueChange = { title = it },
                label = { Text("Title") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true
            )
            Spacer(Modifier.height(10.dp))

            OutlinedTextField(
                value = description,
                onValueChange = { description = it },
                label = { Text("Description") },
                modifier = Modifier.fillMaxWidth(),
                minLines = 3,
                maxLines = 5
            )
            Spacer(Modifier.height(10.dp))

            OutlinedTextField(
                value = assignee,
                onValueChange = { assignee = it },
                label = { Text("Assignee") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true
            )
            Spacer(Modifier.height(10.dp))

            DropdownSelector(
                label = "Priority",
                options = priorities,
                selected = priority,
                onSelected = { priority = it }
            )
            Spacer(Modifier.height(10.dp))

            DropdownSelector(
                label = "Status",
                options = statuses,
                selected = status,
                onSelected = { status = it }
            )
            Spacer(Modifier.height(20.dp))

            Button(
                onClick = {
                    val issue = BcfIssue(
                        id = UUID.randomUUID().toString(),
                        title = title.trim(),
                        description = description.trim(),
                        priority = priority,
                        status = status,
                        assignee = assignee.trim(),
                        cameraX = cameraX,
                        cameraY = cameraY,
                        cameraZ = cameraZ,
                        dirX = dirX,
                        dirY = dirY,
                        dirZ = dirZ,
                        fovDegrees = fovDegrees,
                        elementGlobalId = elementGlobalId,
                        snapshotBytes = null
                    )
                    viewModel.addBcfIssue(issue)
                },
                modifier = Modifier.fillMaxWidth(),
                enabled = title.isNotBlank()
            ) {
                Text("Submit Issue")
            }

            Spacer(Modifier.height(32.dp))
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DropdownSelector(
    label: String,
    options: List<String>,
    selected: String,
    onSelected: (String) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }

    ExposedDropdownMenuBox(
        expanded = expanded,
        onExpandedChange = { expanded = !expanded }
    ) {
        OutlinedTextField(
            value = selected,
            onValueChange = {},
            readOnly = true,
            label = { Text(label) },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            modifier = Modifier
                .fillMaxWidth()
                .menuAnchor()
        )
        ExposedDropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false }
        ) {
            options.forEach { option ->
                DropdownMenuItem(
                    text = { Text(option) },
                    onClick = {
                        onSelected(option)
                        expanded = false
                    }
                )
            }
        }
    }
}
