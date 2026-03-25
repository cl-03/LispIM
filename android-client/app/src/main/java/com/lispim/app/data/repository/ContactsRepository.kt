package com.lispim.app.data.repository

import com.lispim.app.data.api.LispIMApiService
import com.lispim.app.data.model.*
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Contacts Repository - Handles friend list and friend requests
 */
@Singleton
class ContactsRepository @Inject constructor(
    private val apiService: LispIMApiService
) {
    private val _friends = MutableStateFlow<List<Friend>>(emptyList())
    val friends: StateFlow<List<Friend>> = _friends.asStateFlow()

    private val _friendRequests = MutableStateFlow<List<FriendRequest>>(emptyList())
    val friendRequests: StateFlow<List<FriendRequest>> = _friendRequests.asStateFlow()

    private val _searchResults = MutableStateFlow<List<User>>(emptyList())
    val searchResults: StateFlow<List<User>> = _searchResults.asStateFlow()

    /**
     * Get friends list from server
     */
    suspend fun loadFriends(token: String): Result<List<Friend>> {
        return try {
            val response = apiService.getFriends("Bearer $token")
            if (response.isSuccessful && response.body() != null) {
                val body = response.body()!!
                if (body.success && body.data != null) {
                    _friends.value = body.data
                    Result.success(body.data)
                } else {
                    Result.failure(Exception(body.error?.message ?: "Failed to load friends"))
                }
            } else {
                Result.failure(Exception("Failed to load friends: ${response.code()}"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    /**
     * Get friend requests from server
     */
    suspend fun loadFriendRequests(token: String): Result<List<FriendRequest>> {
        return try {
            val response = apiService.getFriendRequests("Bearer $token")
            if (response.isSuccessful && response.body() != null) {
                val body = response.body()!!
                if (body.success && body.data != null) {
                    _friendRequests.value = body.data.requests
                    Result.success(body.data.requests)
                } else {
                    Result.failure(Exception(body.error?.message ?: "Failed to load friend requests"))
                }
            } else {
                Result.failure(Exception("Failed to load friend requests: ${response.code()}"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    /**
     * Send friend request
     */
    suspend fun sendFriendRequest(token: String, friendId: String, message: String? = null): Result<Unit> {
        return try {
            val response = apiService.addFriend("Bearer $token", AddFriendRequest(friendId, message))
            if (response.isSuccessful && response.body() != null) {
                val body = response.body()!!
                if (body.success) {
                    Result.success(Unit)
                } else {
                    Result.failure(Exception(body.error?.message ?: "Failed to send friend request"))
                }
            } else {
                Result.failure(Exception("Failed to send friend request: ${response.code()}"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    /**
     * Accept friend request
     */
    suspend fun acceptFriendRequest(token: String, requestId: String): Result<Unit> {
        return try {
            val response = apiService.acceptFriendRequest("Bearer $token", AcceptFriendRequest(requestId))
            if (response.isSuccessful && response.body() != null) {
                val body = response.body()!!
                if (body.success) {
                    // Refresh friends and requests
                    loadFriends(token)
                    loadFriendRequests(token)
                    Result.success(Unit)
                } else {
                    Result.failure(Exception(body.error?.message ?: "Failed to accept friend request"))
                }
            } else {
                Result.failure(Exception("Failed to accept friend request: ${response.code()}"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    /**
     * Reject friend request
     */
    suspend fun rejectFriendRequest(token: String, requestId: String): Result<Unit> {
        return try {
            val response = apiService.rejectFriendRequest("Bearer $token", AcceptFriendRequest(requestId))
            if (response.isSuccessful && response.body() != null) {
                val body = response.body()!!
                if (body.success) {
                    // Refresh requests
                    loadFriendRequests(token)
                    Result.success(Unit)
                } else {
                    Result.failure(Exception(body.error?.message ?: "Failed to reject friend request"))
                }
            } else {
                Result.failure(Exception("Failed to reject friend request: ${response.code()}"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    /**
     * Delete friend
     */
    suspend fun deleteFriend(token: String, friendId: String): Result<Unit> {
        return try {
            val response = apiService.deleteFriend("Bearer $token", AddFriendRequest(friendId, null))
            if (response.isSuccessful && response.body() != null) {
                val body = response.body()!!
                if (body.success) {
                    // Refresh friends
                    loadFriends(token)
                    Result.success(Unit)
                } else {
                    Result.failure(Exception(body.error?.message ?: "Failed to delete friend"))
                }
            } else {
                Result.failure(Exception("Failed to delete friend: ${response.code()}"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    /**
     * Search users
     */
    suspend fun searchUsers(token: String, query: String, limit: Int = 20): Result<List<User>> {
        return try {
            val response = apiService.searchUsers("Bearer $token", query, limit)
            if (response.isSuccessful && response.body() != null) {
                val body = response.body()!!
                if (body.success && body.data != null) {
                    _searchResults.value = body.data
                    Result.success(body.data)
                } else {
                    Result.failure(Exception(body.error?.message ?: "Search failed"))
                }
            } else {
                Result.failure(Exception("Search failed: ${response.code()}"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    /**
     * Clear search results
     */
    fun clearSearchResults() {
        _searchResults.value = emptyList()
    }
}
