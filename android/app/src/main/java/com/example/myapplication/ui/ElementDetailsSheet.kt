package com.example.myapplication.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Divider
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.myapplication.ar.ARViewModel
import com.example.myapplication.ar.SelectedElement
import com.example.myapplication.ffi.IfcProperty
import com.example.myapplication.ffi.IfcQuantity

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ElementDetailsSheet(
    element: SelectedElement,
    viewModel: ARViewModel
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false)

    ModalBottomSheet(
        onDismissRequest = { viewModel.dismissDetails() },
        sheetState = sheetState
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 8.dp)
        ) {
            // Header
            Text(
                text = element.ifcType,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.primary
            )
            Text(
                text = element.name.ifBlank { "(unnamed)" },
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold
            )
            if (!element.globalId.isNullOrBlank()) {
                Text(
                    text = "GUID: ${element.globalId}",
                    style = MaterialTheme.typography.bodySmall,
                    color = Color.Gray
                )
            }

            Spacer(Modifier.height(16.dp))

            // Properties grouped by property set
            if (element.properties.isNotEmpty()) {
                Text(
                    text = "Properties",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold
                )
                Spacer(Modifier.height(8.dp))

                val grouped = element.properties.groupBy { it.propertySet ?: "General" }
                grouped.forEach { (setName, props) ->
                    PropertySetSection(setName = setName, properties = props)
                    Spacer(Modifier.height(8.dp))
                }
            }

            // Quantities grouped by quantity set
            if (element.quantities.isNotEmpty()) {
                Spacer(Modifier.height(8.dp))
                Text(
                    text = "Quantities",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold
                )
                Spacer(Modifier.height(8.dp))

                val grouped = element.quantities.groupBy { it.quantitySet ?: "General" }
                grouped.forEach { (setName, quantities) ->
                    QuantitySetSection(setName = setName, quantities = quantities)
                    Spacer(Modifier.height(8.dp))
                }
            }

            Spacer(Modifier.height(32.dp))
        }
    }
}

@Composable
private fun PropertySetSection(setName: String, properties: List<IfcProperty>) {
    Column(modifier = Modifier.fillMaxWidth()) {
        Text(
            text = setName,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.secondary,
            fontWeight = FontWeight.SemiBold
        )
        Divider(modifier = Modifier.padding(vertical = 4.dp))
        properties.forEach { prop ->
            PropertyRow(name = prop.name, value = prop.value)
        }
    }
}

@Composable
private fun QuantitySetSection(setName: String, quantities: List<IfcQuantity>) {
    Column(modifier = Modifier.fillMaxWidth()) {
        Text(
            text = setName,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.secondary,
            fontWeight = FontWeight.SemiBold
        )
        Divider(modifier = Modifier.padding(vertical = 4.dp))
        quantities.forEach { qty ->
            val formatted = "%.3f %s".format(qty.value, qty.quantityType)
            PropertyRow(name = qty.name, value = formatted)
        }
    }
}

@Composable
private fun PropertyRow(name: String, value: String) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp)
    ) {
        Text(
            text = name,
            style = MaterialTheme.typography.bodySmall,
            color = Color.Gray
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Normal
        )
    }
}
