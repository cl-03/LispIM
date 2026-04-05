import React, { useState, useEffect, useRef } from 'react'
import { getApiClient, Moment } from '@/utils/api-client'
import { useAppStore } from '@/store/appStore'

interface MomentsFeedProps {
  onBack?: () => void
}

interface MomentFormData {
  content: string
  photos: string[]
  location: string
  visibility: 'public' | 'friends' | 'private'
}

const MomentsFeed: React.FC<MomentsFeedProps> = ({ onBack }) => {
  const { user } = useAppStore()
  const [moments, setMoments] = useState<Moment[]>([])
  const [loading, setLoading] = useState(true)
  const [page, setPage] = useState(1)
  const [hasMore, setHasMore] = useState(true)
  const [showPostModal, setShowPostModal] = useState(false)
  const feedRef = useRef<HTMLDivElement>(null)

  const loadMoments = async (reset = false) => {
    if (reset) {
      setLoading(true)
      setPage(1)
    }

    try {
      const api = getApiClient()
      const response = await api.getMoments({
        page: reset ? 1 : page,
        page_size: 20
      })

      if (response.success && response.data) {
        const newMoments = response.data.moments || []
        if (reset) {
          setMoments(newMoments)
        } else {
          setMoments(prev => [...prev, ...newMoments])
        }
        setHasMore(response.data.has_more)
        setPage(prev => prev + 1)
      }
    } catch (error) {
      console.error('Load moments error:', error)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    loadMoments(true)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const handleLoadMore = () => {
    if (hasMore && !loading) {
      loadMoments(false)
    }
  }

  const handlePostSuccess = () => {
    setShowPostModal(false)
    loadMoments(true)
  }

  const handleLike = async (postId: number, isLiked: boolean) => {
    try {
      const api = getApiClient()
      await api.likeMoment(postId, isLiked ? 'unlike' : 'like')
      // Refresh the moment
      loadMoments(true)
    } catch (error) {
      console.error('Like error:', error)
    }
  }

  const handleComment = async (postId: number, content: string, replyTo?: { userId: string; username: string }) => {
    try {
      const api = getApiClient()
      await api.commentMoment(postId, {
        content,
        reply_to_user_id: replyTo?.userId,
        reply_to_username: replyTo?.username
      })
      loadMoments(true)
    } catch (error) {
      console.error('Comment error:', error)
    }
  }

  const handleDeleteComment = async (postId: number, commentId: number) => {
    if (!confirm('确定要删除这条评论吗？')) return
    try {
      const api = getApiClient()
      await api.deleteComment(postId, commentId)
      loadMoments(true)
    } catch (error) {
      console.error('Delete comment error:', error)
    }
  }

  const handleDeleteMoment = async (postId: number) => {
    if (!confirm('确定要删除这条动态吗？')) return
    try {
      const api = getApiClient()
      await api.deleteMoment(postId)
      loadMoments(true)
    } catch (error) {
      console.error('Delete moment error:', error)
    }
  }

  const formatTimeAgo = (timestamp: number) => {
    const seconds = Math.floor((Date.now() / 1000) - timestamp)
    if (seconds < 60) return '刚刚'
    if (seconds < 3600) return `${Math.floor(seconds / 60)}分钟前`
    if (seconds < 86400) return `${Math.floor(seconds / 3600)}小时前`
    if (seconds < 604800) return `${Math.floor(seconds / 86400)}天前`
    return new Date(timestamp * 1000).toLocaleDateString('zh-CN')
  }

  if (loading && moments.length === 0) {
    return (
      <div className="h-screen flex flex-col bg-gray-900">
        <div className="flex items-center justify-between p-4 border-b border-gray-700">
          <button onClick={onBack} className="text-gray-400 hover:text-white">
            <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
            </svg>
          </button>
          <h1 className="text-xl font-semibold text-white">朋友圈</h1>
          <div className="w-6" />
        </div>
        <div className="flex-1 flex items-center justify-center">
          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-500" />
        </div>
      </div>
    )
  }

  return (
    <div className="h-screen flex flex-col bg-gray-900" ref={feedRef}>
      {/* Header */}
      <div className="flex items-center justify-between p-4 border-b border-gray-700 bg-gray-800">
        <button onClick={onBack} className="text-gray-400 hover:text-white">
          <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
          </svg>
        </button>
        <h1 className="text-xl font-semibold text-white">朋友圈</h1>
        <button onClick={() => setShowPostModal(true)} className="text-blue-500 hover:text-blue-400">
          <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" />
          </svg>
        </button>
      </div>

      {/* Moments List */}
      <div className="flex-1 overflow-y-auto">
        {moments.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-20 text-gray-500">
            <svg className="w-16 h-16 mb-4 opacity-50" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" />
            </svg>
            <p>还没有动态</p>
          </div>
        ) : (
          <div className="divide-y divide-gray-700">
            {moments.map((moment) => (
              <MomentItem
                key={moment.id}
                moment={moment}
                currentUserId={user?.id || ''}
                onLike={handleLike}
                onComment={handleComment}
                onDeleteComment={handleDeleteComment}
                onDeleteMoment={handleDeleteMoment}
                formatTimeAgo={formatTimeAgo}
              />
            ))}
          </div>
        )}

        {/* Load More */}
        {hasMore && (
          <div className="p-4 text-center">
            <button
              onClick={handleLoadMore}
              disabled={loading}
              className="text-blue-500 hover:text-blue-400 disabled:opacity-50"
            >
              {loading ? '加载中...' : '加载更多'}
            </button>
          </div>
        )}
      </div>

      {/* Post Modal */}
      {showPostModal && (
        <PostMomentModal
          onClose={() => setShowPostModal(false)}
          onPostSuccess={handlePostSuccess}
        />
      )}
    </div>
  )
}

// Moment Item Component
const MomentItem: React.FC<{
  moment: Moment
  currentUserId: string
  onLike: (postId: number, isLiked: boolean) => void
  onComment: (postId: number, content: string, replyTo?: { userId: string; username: string }) => Promise<void>
  onDeleteComment: (postId: number, commentId: number) => void
  onDeleteMoment: (postId: number) => void
  formatTimeAgo: (timestamp: number) => string
}> = ({ moment, currentUserId, onLike, onComment, onDeleteComment, onDeleteMoment, formatTimeAgo }) => {
  const [showComments, setShowComments] = useState(false)
  const [commentText, setCommentText] = useState('')
  const [replyTo, setReplyTo] = useState<{ userId: string; username: string } | null>(null)
  const isLiked = moment.liked_by.includes(currentUserId)
  const isOwner = moment.user_id === currentUserId

  const handleSubmitComment = async () => {
    if (!commentText.trim()) return
    await onComment(moment.id, commentText, replyTo || undefined)
    setCommentText('')
    setReplyTo(null)
  }

  return (
    <div className="p-4 bg-gray-800">
      {/* User Info */}
      <div className="flex items-center justify-between mb-3">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-full bg-blue-500 flex items-center justify-center text-white font-medium flex-shrink-0">
            {moment.avatar ? (
              <img src={moment.avatar} alt={moment.display_name} className="w-10 h-10 rounded-full object-cover" />
            ) : (
              moment.display_name.charAt(0).toUpperCase()
            )}
          </div>
          <div>
            <div className="text-white font-medium">{moment.display_name || moment.username}</div>
            <div className="text-gray-500 text-xs">{formatTimeAgo(moment.created_at)}</div>
          </div>
        </div>
        {isOwner && (
          <button
            onClick={() => onDeleteMoment(moment.id)}
            className="text-gray-500 hover:text-red-500 p-2"
            title="删除动态"
          >
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
            </svg>
          </button>
        )}
      </div>

      {/* Content */}
      {moment.content && (
        <div className="text-gray-200 mb-3 whitespace-pre-wrap">{moment.content}</div>
      )}

      {/* Photos */}
      {moment.photos && moment.photos.length > 0 && (
        <div className={`grid gap-2 mb-3 ${
          moment.photos.length === 1 ? 'grid-cols-1' :
          moment.photos.length === 2 ? 'grid-cols-2' :
          'grid-cols-3'
        }`}>
          {moment.photos.map((photo, index) => (
            <img
              key={index}
              src={photo}
              alt=""
              className="w-full aspect-square object-cover rounded-lg"
            />
          ))}
        </div>
      )}

      {/* Location */}
      {moment.location && (
        <div className="text-gray-500 text-xs mb-3 flex items-center gap-1">
          <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
          </svg>
          {moment.location}
        </div>
      )}

      {/* Actions */}
      <div className="flex items-center justify-between py-2 border-t border-gray-700">
        <button
          onClick={() => onLike(moment.id, isLiked)}
          className={`flex items-center gap-1 ${isLiked ? 'text-red-500' : 'text-gray-400 hover:text-red-500'}`}
        >
          <svg className="w-5 h-5" fill={isLiked ? 'currentColor' : 'none'} stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4.318 6.318a4.5 4.5 0 000 6.364L12 20.364l7.682-7.682a4.5 4.5 0 00-6.364-6.364L12 7.636l-1.318-1.318a4.5 4.5 0 00-6.364 0z" />
          </svg>
          <span className="text-sm">{moment.likes_count}</span>
        </button>
        <button
          onClick={() => setShowComments(!showComments)}
          className="flex items-center gap-1 text-gray-400 hover:text-blue-500"
        >
          <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z" />
          </svg>
          <span className="text-sm">{moment.comments_count}</span>
        </button>
      </div>

      {/* Likes List */}
      {moment.likes_count > 0 && (
        <div className="py-2 text-sm text-gray-400">
          <span className="text-red-500">❤️</span> {moment.likes_count} 人点赞
        </div>
      )}

      {/* Comments */}
      {showComments && (
        <div className="mt-2 space-y-2 bg-gray-700/50 rounded-lg p-3">
          {moment.comments.map((comment) => (
            <div key={comment.id} className="text-sm">
              <span className="text-blue-400">{comment.display_name || comment.username}</span>
              {comment.reply_to_username && (
                <span className="text-gray-500"> 回复 </span>
              )}
              {comment.reply_to_username && (
                <span className="text-blue-400">@{comment.reply_to_username}</span>
              )}
              <span className="text-gray-200">: {comment.content}</span>
              {comment.user_id === currentUserId && (
                <button
                  onClick={() => onDeleteComment(moment.id, comment.id)}
                  className="ml-2 text-gray-500 hover:text-red-500 text-xs"
                >
                  删除
                </button>
              )}
            </div>
          ))}

          {/* Comment Input */}
          <div className="flex items-center gap-2 mt-2">
            <input
              type="text"
              value={commentText}
              onChange={(e) => setCommentText(e.target.value)}
              placeholder={replyTo ? `回复 @${replyTo.username}` : '写下评论...'}
              className="flex-1 bg-gray-600 text-white text-sm rounded px-3 py-2 focus:outline-none focus:ring-1 focus:ring-blue-500"
            />
            {replyTo && (
              <button
                onClick={() => setReplyTo(null)}
                className="text-gray-400 hover:text-white text-sm"
              >
                取消
              </button>
            )}
            <button
              onClick={handleSubmitComment}
              disabled={!commentText.trim()}
              className="text-blue-500 hover:text-blue-400 disabled:opacity-50 text-sm font-medium"
            >
              评论
            </button>
          </div>

          {/* Reply Suggestions */}
          {moment.comments.map((comment) => (
            <button
              key={comment.id}
              onClick={() => setReplyTo({ userId: comment.user_id, username: comment.username })}
              className="text-xs text-gray-500 hover:text-blue-400 mr-2"
            >
              @{comment.username}
            </button>
          ))}
        </div>
      )}
    </div>
  )
}

// Post Moment Modal
const PostMomentModal: React.FC<{
  onClose: () => void
  onPostSuccess: () => void
}> = ({ onClose, onPostSuccess }) => {
  const [formData, setFormData] = useState<MomentFormData>({
    content: '',
    photos: [],
    location: '',
    visibility: 'public'
  })
  const [posting, setPosting] = useState(false)
  const [uploading, setUploading] = useState(false)
  const fileInputRef = useRef<HTMLInputElement>(null)

  const handlePhotoUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = e.target.files
    if (!files || files.length === 0) return

    setUploading(true)
    try {
      const api = getApiClient()
      const uploadPromises = Array.from(files).map(async (file) => {
        const response = await api.uploadFile(file, file.name)
        if (response.success && response.data) {
          return response.data.url
        }
        return null
      })

      const urls = await Promise.all(uploadPromises)
      const validUrls = urls.filter((url): url is string => url !== null)

      setFormData((prev) => ({
        ...prev,
        photos: [...prev.photos, ...validUrls].slice(0, 9)
      }))
    } catch (error) {
      console.error('Upload error:', error)
      alert('图片上传失败')
    } finally {
      setUploading(false)
      // Reset file input
      if (fileInputRef.current) {
        fileInputRef.current.value = ''
      }
    }
  }

  const removePhoto = (index: number) => {
    setFormData({
      ...formData,
      photos: formData.photos.filter((_, i) => i !== index)
    })
  }

  const handleSubmit = async () => {
    if (!formData.content.trim() && formData.photos.length === 0) {
      return
    }

    setPosting(true)
    try {
      const api = getApiClient()
      const response = await api.createMoment(formData)

      if (response.success) {
        onPostSuccess()
      } else {
        alert(response.message || '发布失败')
      }
    } catch (error) {
      console.error('Post moment error:', error)
      alert('发布失败')
    } finally {
      setPosting(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
      <div className="bg-gray-800 rounded-xl w-full max-w-md mx-4">
        {/* Header */}
        <div className="flex items-center justify-between p-4 border-b border-gray-700">
          <h2 className="text-lg font-semibold text-white">发朋友圈</h2>
          <button onClick={onClose} className="text-gray-400 hover:text-white">
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {/* Content */}
        <div className="p-4">
          <textarea
            value={formData.content}
            onChange={(e) => setFormData({ ...formData, content: e.target.value })}
            placeholder="分享你的生活瞬间..."
            className="w-full h-32 bg-gray-700 text-white rounded-lg p-3 focus:outline-none focus:ring-1 focus:ring-blue-500 resize-none"
          />

          {/* Photos */}
          {formData.photos.length > 0 && (
            <div className="grid grid-cols-3 gap-2 mt-3">
              {formData.photos.map((photo, index) => (
                <div key={index} className="relative aspect-square">
                  <img src={photo} alt="" className="w-full h-full object-cover rounded-lg" />
                  <button
                    onClick={() => removePhoto(index)}
                    className="absolute top-1 right-1 bg-gray-900 rounded-full p-1 text-white hover:bg-red-500"
                  >
                    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                    </svg>
                  </button>
                </div>
              ))}
            </div>
          )}

          {/* Add Photo Button */}
          {formData.photos.length < 9 && (
            <div>
              <input
                ref={fileInputRef}
                type="file"
                accept="image/*"
                multiple
                onChange={handlePhotoUpload}
                className="hidden"
                disabled={uploading}
              />
              <button
                onClick={() => fileInputRef.current?.click()}
                disabled={uploading}
                className="mt-3 w-full py-2 border border-gray-600 border-dashed rounded-lg text-gray-400 hover:border-blue-500 hover:text-blue-500 disabled:opacity-50"
              >
                {uploading ? (
                  <span className="flex items-center justify-center gap-2">
                    <svg className="animate-spin h-4 w-4" fill="none" viewBox="0 0 24 24">
                      <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                      <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
                    </svg>
                    上传中...
                  </span>
                ) : (
                  <span className="flex items-center justify-center gap-2">
                    <svg className="w-6 h-6 mx-auto mb-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" />
                    </svg>
                    添加图片（{formData.photos.length}/9）
                  </span>
                )}
              </button>
            </div>
          )}

          {/* Location */}
          <input
            type="text"
            value={formData.location}
            onChange={(e) => setFormData({ ...formData, location: e.target.value })}
            placeholder="添加位置"
            className="w-full mt-3 bg-gray-700 text-white rounded-lg px-3 py-2 focus:outline-none focus:ring-1 focus:ring-blue-500"
          />

          {/* Visibility */}
          <div className="mt-3 flex gap-2">
            {(['public', 'friends', 'private'] as const).map((vis) => (
              <button
                key={vis}
                onClick={() => setFormData({ ...formData, visibility: vis })}
                className={`flex-1 py-2 rounded-lg text-sm font-medium ${
                  formData.visibility === vis
                    ? 'bg-blue-500 text-white'
                    : 'bg-gray-700 text-gray-400 hover:bg-gray-600'
                }`}
              >
                {vis === 'public' && '公开'}
                {vis === 'friends' && '朋友可见'}
                {vis === 'private' && '私密'}
              </button>
            ))}
          </div>
        </div>

        {/* Actions */}
        <div className="p-4 border-t border-gray-700 flex gap-3">
          <button
            onClick={onClose}
            className="flex-1 py-2.5 bg-gray-700 text-white rounded-lg hover:bg-gray-600"
          >
            取消
          </button>
          <button
            onClick={handleSubmit}
            disabled={posting || (!formData.content.trim() && formData.photos.length === 0)}
            className="flex-1 py-2.5 bg-blue-500 text-white rounded-lg hover:bg-blue-600 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {posting ? '发布中...' : '发布'}
          </button>
        </div>
      </div>
    </div>
  )
}

export default MomentsFeed
