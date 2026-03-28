package com.lispim.app.data.local.dao

import androidx.room.*
import com.lispim.app.data.local.entity.SyncAnchorEntity

/**
 * Sync Anchor Data Access Object
 */
@Dao
interface SyncAnchorDao {

    @Query("SELECT * FROM sync_anchors WHERE userId = :userId")
    suspend fun getAnchor(userId: String): SyncAnchorEntity?

    @Query("SELECT * FROM sync_anchors")
    suspend fun getAllAnchors(): List<SyncAnchorEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(anchor: SyncAnchorEntity)

    @Update
    suspend fun update(anchor: SyncAnchorEntity)

    @Delete
    suspend fun delete(anchor: SyncAnchorEntity)

    @Query("DELETE FROM sync_anchors WHERE userId = :userId")
    suspend fun deleteByUserId(userId: String)

    @Query("DELETE FROM sync_anchors")
    suspend fun deleteAll()

    @Query("SELECT COUNT(*) FROM sync_anchors")
    suspend fun getCount(): Int
}
