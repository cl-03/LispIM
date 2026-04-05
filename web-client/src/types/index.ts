// LispIM Web Client - Type Definitions

// 认证相关类型
export interface LoginRequest {
  username: string;
  password: string;
}

export interface RegisterRequest {
  method?: 'username' | 'phone' | 'email';
  username?: string;
  password?: string;
  email?: string;
  phone?: string;
  phoneCode?: string;
  emailCode?: string;
  displayName?: string;
  invitationCode?: string;
}

export interface AuthResponse {
  userId: string;
  token: string;
  user?: User;
}

export interface RegisterData {
  method: 'username' | 'phone' | 'email' | 'wechat';
  username?: string;
  password?: string;
  email?: string;
  phone?: string;
  phoneCode?: string;
  emailCode?: string;
  displayName?: string;
  invitationCode?: string;
}

export type RegisterMethod = 'username' | 'phone' | 'email' | 'wechat';

// API 响应类型
export interface ApiSuccessResponse<T = any> {
  success: true;
  data: T;
  message?: string;
}

export interface ApiErrorResponse {
  success: false;
  error: {
    code: string;
    message: string;
    details?: any;
  };
}

export interface User {
  id: string;
  username: string;
  email?: string;
  phone?: string;
  display_name?: string;
  displayName?: string;
  avatar?: string;
  avatar_url?: string;
  status?: 'online' | 'offline' | 'away' | 'busy';
  public_key?: string;
  bio?: string;
  gender?: 'male' | 'female' | 'other';
  birthday?: string;
  location?: string;
  company?: string;
  website?: string;
  created_at?: number;
  createdAt?: number;
  last_seen?: number;
  lastSeen?: number;
}

export interface Conversation {
  id: number;
  type: 'direct' | 'group' | 'channel';
  participants: string[];
  participantUsers?: User[];
  name?: string;
  avatar?: string;
  creator_id: string;
  creatorId?: string;
  last_message?: Message;
  lastMessage?: Message | {
    id: number;
    content: string;
    timestamp: number;
    senderId?: string;
  };
  last_activity: number;
  lastActivity?: number;
  last_sequence: number;
  is_pinned: boolean;
  isPinned?: boolean;
  is_muted: boolean;
  isMuted?: boolean;
  unread_count: number;
  unreadCount?: number;
  member_roles?: Record<string, 'owner' | 'admin' | 'member'>;
  draft?: string;
  createdAt?: number;
  updatedAt?: number;
}

export interface Message {
  id: number;
  sequence: number;
  conversation_id: number;
  conversationId?: number;
  sender_id: string;
  senderId?: string;
  sender_username?: string;
  senderUsername?: string;
  sender?: User;
  message_type: 'text' | 'image' | 'voice' | 'video' | 'file' | 'system' | 'notification' | 'link';
  messageType?: 'text' | 'image' | 'voice' | 'video' | 'file' | 'system' | 'notification' | 'link';
  type?: 'text' | 'image' | 'voice' | 'video' | 'file' | 'system' | 'notification' | 'link';
  content: string | null;
  attachments?: Attachment[];
  created_at: number;
  createdAt?: number;
  edited_at?: number;
  recalled: boolean;
  read_by?: Record<string, number>;
  readBy?: Array<{
    userId: string;
    timestamp: number;
  }>;
  mentions?: string[];
  reply_to?: number;
  replyTo?: number;
  metadata?: Record<string, any>;
  reactions?: ReactionGroup[];
}

// 兼容旧代码的消息类型
export type MessageType = 'text' | 'image' | 'voice' | 'video' | 'file' | 'system' | 'notification' | 'link';

export interface Attachment {
  type: string;
  url: string;
  size?: number;
  name?: string;
  thumbnail?: string;
}

export interface Friend {
  id: string;
  username: string;
  display_name?: string;
  displayName?: string;
  avatar_url?: string;
  avatar?: string;
  status?: string;
  friend_status: 'accepted' | 'pending' | 'blocked';
  friendStatus?: 'accepted' | 'pending' | 'blocked';
  friend_since: number;
  friendSince?: number;
  remark?: string;
  tags?: string[];
  groupId?: number;
  starred_id?: string;
  starredId?: string;
  blocked_id?: string;
  blockedId?: string;
}

export interface FriendRequest {
  id: number;
  sender_id: string;
  senderId?: string;
  receiver_id: string;
  receiverId?: string;
  senderUsername?: string;
  message?: string;
  status: 'pending' | 'accepted' | 'rejected';
  created_at: number;
  createdAt?: number;
  sender?: User;
}

export interface Group {
  id: number;
  name: string;
  avatar?: string;
  owner_id: string;
  ownerId?: string;
  members: string[];
  member_count: number;
  memberCount?: number;
  announcement?: string;
  is_muted: boolean;
  isMuted?: boolean;
  created_at: number;
  createdAt?: number;
}

export interface GroupMember {
  userId: string;
  role: 'owner' | 'admin' | 'member';
  nickname?: string;
  joinedAt: number;
  isMuted: boolean;
  isQuiet: boolean;
  user?: User;
}

export interface Favorite {
  id: number;
  target_type: 'message' | 'file' | 'link';
  target_id: string;
  content: string;
  tags?: string[];
  created_at: number;
}

export interface PinnedMessage {
  messageId: number;
  content: string;
  senderId: string;
  type: string;
  pinnedAt: number;
  pinnedBy: string;
  pinnedByUsername: string;
}

export interface AuthState {
  user: User | null;
  token: string | null;
  sessionId: string | null;
  isAuthenticated: boolean;
  refreshToken?: string | null;
}

export interface ConnectionState {
  connected: boolean;
  connecting: boolean;
  error: string | null;
  reconnectAttempts: number;
}

export interface Notification {
  id: number;
  type: 'message' | 'call' | 'friend-request' | 'system' | 'group';
  title: string;
  body: string;
  data?: any;
  is_read: boolean;
  created_at: number;
}

export interface AppState {
  auth: AuthState;
  connection: ConnectionState;
  conversations: Conversation[];
  messages: Map<number, Message[]>;
  users: Map<string, User>;
  friends: Friend[];
  friendRequests: FriendRequest[];
  notifications: Notification[];
  activeConversationId: number | null;
}

export interface ChatState {
  conversations: Conversation[];
  activeConversationId: number | null;
  messages: Map<number, Message[]>;
  users: Map<string, User>;
}

// 批量操作相关类型
export interface BatchOperationResult<T> {
  success: boolean;
  data?: T;
  error?: string;
}

export interface BatchLoadHistoryOptions {
  conversationIds: number[];
  limitPerConversation?: number;
  maxConcurrent?: number;
}

export interface BatchMarkAsReadOptions {
  markers: Array<{ conversationId: number; messageIds: number[] }>;
  maxConcurrent?: number;
}

// ==================== 新功能类型定义 ====================

// 消息表情回应
export interface MessageReaction {
  id: number;
  messageId: number;
  emoji: string;
  userId: string;
  username?: string;
  userAvatar?: string;
  createdAt: number;
}

export interface ReactionGroup {
  emoji: string;
  count: number;
  userNames: string[];
  isSelf: boolean;
}

// 语音消息
export interface VoiceMessage {
  duration: number; // 秒
  waveform: number[]; // 波形数据
  url: string;
  mimeType: string;
}

// 用户状态/动态
export interface UserStatus {
  id: number;
  userId: string;
  username?: string;
  userAvatar?: string;
  content: string;
  mediaType?: 'image' | 'video' | 'text';
  mediaUrl?: string;
  thumbnailUrl?: string;
  expiresIn: number; // 过期时间（秒）
  createdAt: number;
  expiresAt: number;
  viewerCount?: number;
}

// 聊天文件夹
export interface ChatFolder {
  id: number;
  name: string;
  icon?: string;
  conversationIds: number[];
  isDefault?: boolean;
  createdAt: number;
}

// 频道
export interface Channel {
  id: number;
  groupId: number;
  name: string;
  description?: string;
  type: 'text' | 'voice' | 'category';
  parentId?: number;
  position: number;
  isMuted?: boolean;
  memberCount?: number;
  createdAt: number;
}

// 搜索相关
export interface SearchResult {
  messageId: number;
  conversationId: number;
  conversationName?: string;
  content: string;
  highlightedContent?: string;
  senderId: string;
  senderName?: string;
  createdAt: number;
  matchCount: number;
}

export interface SearchOptions {
  query: string;
  conversationId?: number;
  senderId?: string;
  startDate?: number;
  endDate?: number;
  messageType?: 'text' | 'image' | 'file' | 'link';
  limit?: number;
  offset?: number;
}
