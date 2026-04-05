import React from 'react'
import { Friend } from '@/utils/api-client'

interface ContactStarModalProps {
  onClose: () => void
  friends: Friend[]
}

const ContactStarModal: React.FC<ContactStarModalProps> = ({ onClose, friends }) => {
  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center" style={{ zIndex: 10000 }}>
      <div className="bg-white rounded-lg w-full max-w-md p-6 relative max-h-[80vh] overflow-y-auto" style={{ zIndex: 10001 }}>
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-lg font-semibold text-gray-900">星标联系人</h2>
          <button onClick={onClose} className="text-gray-500 hover:text-gray-700">
            <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {/* Info */}
        <div className="mb-4 p-3 bg-yellow-50 rounded-lg">
          <div className="text-sm text-yellow-700">
            星标联系人会显示在联系人列表顶部，方便快速找到重要的人
          </div>
        </div>

        {/* Star Contacts */}
        {friends.length === 0 ? (
          <div className="text-center py-8 text-gray-500">
            <svg className="w-16 h-16 mx-auto text-gray-300 mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M11.049 2.927c.3-.921 1.603-.921 1.902 0l1.519 4.674a1 1 0 00.95.69h4.915c.969 0 1.371 1.24.588 1.81l-3.976 2.888a1 1 0 00-.363 1.118l1.518 4.674c.3.922-.755 1.688-1.538 1.118l-3.976-2.888a1 1 0 00-1.176 0l-3.976 2.888c-.783.57-1.838-.197-1.538-1.118l1.518-4.674a1 1 0 00-.363-1.118l-3.976-2.888c-.784-.57-.38-1.81.588-1.81h4.914a1 1 0 00.951-.69l1.519-4.674z" />
            </svg>
            <p>暂无星标联系人</p>
            <p className="text-xs mt-2">在联系人列表中点击星号图标添加</p>
          </div>
        ) : (
          <div className="space-y-2">
            {friends.map(friend => (
              <div
                key={friend.id}
                className="flex items-center gap-3 p-3 bg-gray-50 rounded-lg"
              >
                <div className="w-10 h-10 rounded-full bg-blue-500 flex items-center justify-center text-white font-medium flex-shrink-0 relative">
                  {friend.avatarUrl ? (
                    <img src={friend.avatarUrl} alt={friend.displayName} className="w-10 h-10 rounded-full object-cover" />
                  ) : (
                    (friend.displayName || friend.username).charAt(0).toUpperCase()
                  )}
                  <div className="absolute -top-0.5 -right-0.5">
                    <svg className="w-4 h-4 text-yellow-400" fill="currentColor" viewBox="0 0 20 20">
                      <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
                    </svg>
                  </div>
                </div>
                <div className="flex-1 min-w-0">
                  <div className="font-medium text-gray-900">{friend.displayName || friend.username}</div>
                  <div className="text-sm text-gray-500">@{friend.username}</div>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}

export default ContactStarModal
