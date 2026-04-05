/**
 * LispIM Web Client - Components Exports
 */

// 主要聊天组件
export { default as ConversationList } from './ConversationList';
export { default as MessageList } from './MessageList';
export { default as MessageInput } from './MessageInput';
export { default as Chat } from './Chat';

// 联系人相关
export { default as Contacts } from './Contacts';
export { default as AddFriendModal } from './AddFriendModal';
export { default as ContactGroupModal } from './ContactGroupModal';
export { default as ContactRemarkModal } from './ContactRemarkModal';
export { default as ContactStarModal } from './ContactStarModal';
export { default as ContactTagModal } from './ContactTagModal';
export { default as ContactBlacklistModal } from './ContactBlacklistModal';

// 群组相关
export { default as GroupModal } from './GroupModal';
export { GroupPoll } from './GroupPoll';

// 消息功能
export { default as PinnedMessages } from './PinnedMessages';
export { default as MessageReactions } from './MessageReactions';
export { MessageSearch } from './MessageSearch';
export { MessageReactionPicker, MessageReactionsDisplay } from './MessageReactionPicker';

// 语音消息
export { VoiceMessageRecorder, VoiceMessagePlayer } from './VoiceMessageRecorder';

// 用户状态/动态
export { UserStatusStories, CreateStatusModal } from './UserStatusStories';

// 聊天文件夹和频道
export { ChatFolders, GroupChannels } from './ChatFolders';

// 通话
export { default as CallModal } from './CallModal';

// 发现
export { default as Discover } from './Discover';
export { default as MomentsFeed } from './MomentsFeed';
export { default as NearbyPeopleModal } from './NearbyPeopleModal';
export { default as ScanModal } from './ScanModal';

// 设置
export { default as Settings } from './Settings';
export { default as ProfileSettings } from './ProfileSettings';
export { default as AccountSettings } from './AccountSettings';
export { default as NotificationSettings } from './NotificationSettings';
export { default as PrivacySettings } from './PrivacySettings';
export { default as ConversationPrivacySettings } from './ConversationPrivacySettings';
export { default as SecuritySettings } from './SecuritySettings';
export { default as AboutSettings } from './AboutSettings';

// 用户认证
export { default as Login } from './Login';
export { default as Register } from './Register';

// 用户资料
export { default as Profile } from './Profile';
export { default as ProfileDetail } from './ProfileDetail';

// 用户面板
export { default as UserPanel } from './UserPanel';

// 并发示例（开发/演示用）
export { default as ConcurrentExample } from './ConcurrentExample';
export { ConversationListExample, BatchSendMessageExample, BatchOperationHookExample } from './ConcurrentExample';
