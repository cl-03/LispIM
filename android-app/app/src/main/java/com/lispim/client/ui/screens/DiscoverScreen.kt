package com.lispim.client.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp

data class FeatureItem(
    val name: String,
    val description: String,
    val icon: ImageVector,
    val color: Long
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DiscoverScreen() {
    val features = remember {
        listOf(
            FeatureItem("朋友圈", "分享生活点滴", Icons.Filled.PhotoLibrary, 0xFF4CAF50),
            FeatureItem("视频号", "探索精彩视频", Icons.Filled.Videocam, 0xFF9C27B0),
            FeatureItem("扫一扫", "扫描二维码", Icons.Filled.QrCodeScanner, 0xFF2196F3),
            FeatureItem("摇一摇", "认识新朋友", Icons.Filled.PhoneAndroid, 0xFFF44336)
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("发现") }
            )
        }
    ) { paddingValues ->
        LazyVerticalGrid(
            columns = GridCells.Fixed(2),
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues),
            contentPadding = PaddingValues(16.dp),
            horizontalArrangement = Arrangement.spacedBy(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            items(features) { feature ->
                FeatureCard(feature = feature)
            }
        }
    }
}

@Composable
fun FeatureCard(feature: FeatureItem) {
    Card(
        modifier = Modifier
            .aspectRatio(1f)
            .clickable { },
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            Icon(
                imageVector = feature.icon,
                contentDescription = feature.name,
                modifier = Modifier.size(48.dp),
                tint = androidx.compose.ui.graphics.Color(feature.color)
            )
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = feature.name,
                style = MaterialTheme.typography.titleMedium
            )
            Text(
                text = feature.description,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}
