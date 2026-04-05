import React, { useState, useRef, KeyboardEvent, useMemo, useEffect, useCallback } from 'react'
import { useAppStore } from '@/store/appStore'
import { useFileUpload } from '@/hooks/useFileUpload'
import { getApiClient } from '@/utils/api-client'
import { VoiceMessageRecorder } from './VoiceMessageRecorder'
import { searchGifs, getTrendingGifs, getGifsByCategory, Gif, isGiphyConfigured } from '@/utils/giphy'

interface MessageInputProps {
  conversationId: number
  replyingTo?: { id: number; senderName: string; content: string } | null
  onCancelReply?: () => void
}

const MessageInput: React.FC<MessageInputProps> = ({ conversationId, replyingTo, onCancelReply }) => {
  const { sendMessage } = useAppStore()
  const [content, setContent] = useState('')
  const [isTyping, setIsTyping] = useState(false)
  const [showEmojiPicker, setShowEmojiPicker] = useState(false)
  const [toast, setToast] = useState<{ message: string; visible: boolean }>({ message: '', visible: false })
  const [uploadProgress, setUploadProgress] = useState<{ visible: boolean; progress: number; filename: string } | null>(null)
  const [showVoiceRecorder, setShowVoiceRecorder] = useState(false)
  const [showReactionPicker, setShowReactionPicker] = useState(false)
  const [showMentions, setShowMentions] = useState(false)
  const [mentionQuery, setMentionQuery] = useState('')
  const [cursorPosition, setCursorPosition] = useState(0)
  const [draftContent, setDraftContent] = useState('')
  const [isComposing, setIsComposing] = useState(false) // 中文输入状态
  const [wordCount, setWordCount] = useState(0)
  const [charCount, setCharCount] = useState(0)
  const textareaRef = useRef<HTMLTextAreaElement>(null)
  const fileInputRef = useRef<HTMLInputElement>(null)
  const imageInputRef = useRef<HTMLInputElement>(null)
  const pickerContainerRef = useRef<HTMLDivElement>(null)
  const { uploadFile, isUploading, progress, reset: resetUpload } = useFileUpload()

  // 关闭选择器
  const closeAllPickers = useCallback(() => {
    setShowEmojiPicker(false)
    setShowGifPicker(false)
    setShowReactionPicker(false)
    setShowMentions(false)
  }, [])

  // 点击外部关闭选择器
  useEffect(() => {
    function handleClickOutside(event: MouseEvent) {
      if (pickerContainerRef.current && !pickerContainerRef.current.contains(event.target as Node)) {
        closeAllPickers()
      }
    }
    document.addEventListener('mousedown', handleClickOutside)
    return () => document.removeEventListener('mousedown', handleClickOutside)
  }, [closeAllPickers])

  const showToast = (message: string) => {
    setToast({ message, visible: true })
    setTimeout(() => setToast({ message: '', visible: false }), 2000)
  }

  const handleSend = () => {
    if (content.trim()) {
      // 如果有回复对象，在内容中添加引用信息
      if (replyingTo) {
        const messageWithReply = `// Re: ${replyingTo.senderName}\n${content.trim()}`
        sendMessage(conversationId, messageWithReply, undefined, replyingTo.id)
      } else {
        sendMessage(conversationId, content.trim())
      }
      setContent('')
      setIsTyping(false)
      setShowEmojiPicker(false)
      setWordCount(0)
      setCharCount(0)
      if (replyingTo && onCancelReply) {
        onCancelReply()
      }
      textareaRef.current?.focus()
    }
  }

  // 处理格式化命令（Markdown 风格）
  const insertFormat = (prefix: string, suffix: string = prefix) => {
    const textarea = textareaRef.current
    if (!textarea) return

    const start = textarea.selectionStart
    const end = textarea.selectionEnd
    const selectedText = content.substring(start, end)

    const newContent = content.substring(0, start) + prefix + selectedText + suffix + content.substring(end)
    setContent(newContent)

    setTimeout(() => {
      textarea.focus()
      if (selectedText) {
        textarea.setSelectionRange(start + prefix.length, end + prefix.length)
      } else {
        textarea.setSelectionRange(start + prefix.length, start + prefix.length)
      }
    }, 0)
  }

  // 处理粗体
  const handleBold = () => insertFormat('**', '**')

  // 处理斜体
  const handleItalic = () => insertFormat('*', '*')

  // 处理删除线
  const handleStrike = () => insertFormat('~~', '~~')

  // 处理行内代码
  const handleCode = () => insertFormat('`', '`')

  // 处理引用
  const handleQuote = () => {
    const textarea = textareaRef.current
    if (!textarea) return
    const start = textarea.selectionStart
    const newContent = content.substring(0, start) + '> ' + content.substring(start)
    setContent(newContent)
    setTimeout(() => {
      textarea.focus()
      textarea.setSelectionRange(start + 2, start + 2)
    }, 0)
  }

  // 处理快捷键
  const handleKeyDown = (e: KeyboardEvent<HTMLTextAreaElement>) => {
    // 中文输入中不处理
    if (isComposing) return

    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault()
      handleSend()
      // 保存到输入历史
      if (content.trim()) {
        setInputHistory(prev => [...prev.slice(-9), content.trim()])
        setHistoryIndex(-1)
      }
    } else if (e.key === 'ArrowUp' && !e.shiftKey && !e.ctrlKey) {
      // 上箭头 - 查看历史输入
      if (inputHistory.length > 0 && historyIndex < inputHistory.length - 1) {
        e.preventDefault()
        const newIndex = historyIndex + 1
        setHistoryIndex(newIndex)
        setContent(inputHistory[inputHistory.length - 1 - newIndex])
      }
    } else if (e.key === 'ArrowDown' && !e.shiftKey && !e.ctrlKey) {
      // 下箭头 - 返回最新输入
      if (historyIndex >= 0) {
        e.preventDefault()
        const newIndex = historyIndex - 1
        setHistoryIndex(newIndex)
        if (newIndex < 0) {
          setContent('')
        } else {
          setContent(inputHistory[inputHistory.length - 1 - newIndex])
        }
      }
    }
    // Ctrl+B 粗体
    else if (e.key === 'b' && e.ctrlKey) {
      e.preventDefault()
      handleBold()
    }
    // Ctrl+I 斜体
    else if (e.key === 'i' && e.ctrlKey) {
      e.preventDefault()
      handleItalic()
    }
    // Ctrl+E 删除线
    else if (e.key === 'e' && e.ctrlKey) {
      e.preventDefault()
      handleStrike()
    }
    // Ctrl+K 代码
    else if (e.key === 'k' && e.ctrlKey) {
      e.preventDefault()
      handleCode()
    }
  }

  // 处理输入历史（上/下箭头）
  const [inputHistory, setInputHistory] = useState<string[]>([])
  const [historyIndex, setHistoryIndex] = useState(-1)

  const handleChange = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    setContent(e.target.value)
    setIsTyping(true)
    setCursorPosition(e.target.selectionStart)

    // 统计字数
    const value = e.target.value
    setCharCount(value.length)
    setWordCount(value.trim() ? value.trim().split(/\s+/).length : 0)

    // 检测 @ 符号
    const cursor = e.target.selectionStart
    const lastAtIndex = value.lastIndexOf('@', cursor - 1)

    if (lastAtIndex !== -1 && lastAtIndex < cursor) {
      const mentionText = value.slice(lastAtIndex + 1, cursor)
      if (/^\w*$/.test(mentionText)) {
        setMentionQuery(mentionText)
        setShowMentions(true)
        return
      }
    }
    setShowMentions(false)
    setMentionQuery('')

    // 自动调整高度
    if (textareaRef.current) {
      textareaRef.current.style.height = 'auto'
      textareaRef.current.style.height = `${Math.min(textareaRef.current.scrollHeight, 120)}px`
    }
  }

  const handleCompositionStart = () => {
    setIsComposing(true)
  }

  const handleCompositionEnd = () => {
    setIsComposing(false)
  }

  // 处理表情选择
  const handleEmojiSelect = (emoji: string) => {
    const textarea = textareaRef.current
    if (!textarea) return

    const start = textarea.selectionStart
    const end = textarea.selectionEnd
    const newContent = content.substring(0, start) + emoji + content.substring(end)
    setContent(newContent)
    setIsTyping(true)
    setCharCount(newContent.length)
    setWordCount(newContent.trim() ? newContent.trim().split(/\s+/).length : 0)

    // 恢复光标位置
    setTimeout(() => {
      textarea.focus()
      textarea.setSelectionRange(start + emoji.length, start + emoji.length)
    }, 0)
  }

  // 处理@选择
  const handleMentionSelect = (username: string) => {
    const textarea = textareaRef.current
    if (!textarea) return

    const lastAtIndex = content.lastIndexOf('@', cursorPosition - 1)
    if (lastAtIndex !== -1) {
      const beforeMention = content.substring(0, lastAtIndex)
      const afterMention = content.substring(cursorPosition)
      const newContent = `${beforeMention}@${username} ${afterMention}`
      setContent(newContent)
      setShowMentions(false)
      setMentionQuery('')

      setTimeout(() => {
        textarea.focus()
        const newPos = lastAtIndex + username.length + 2
        textarea.setSelectionRange(newPos, newPos)
      }, 0)
    }
  }

  // 获取提及建议（从当前会话的参与者中获取）
  const mentionSuggestions = useMemo(() => {
    // 这里可以从 API 获取群组成员或联系人列表
    // 暂时返回一个固定的示例列表
    const allUsers = ['user1', 'user2', 'admin', 'system']
    if (!mentionQuery) return allUsers.slice(0, 5)
    return allUsers.filter(u => u.toLowerCase().includes(mentionQuery.toLowerCase())).slice(0, 5)
  }, [mentionQuery])

  // 自动保存草稿
  useEffect(() => {
    const draftKey = `draft_${conversationId}`
    const saved = localStorage.getItem(draftKey)
    if (saved) {
      setDraftContent(saved)
      setContent(saved)
    }
  }, [conversationId])

  // 监听内容变化，自动保存草稿
  useEffect(() => {
    const draftKey = `draft_${conversationId}`
    const timeoutId = setTimeout(() => {
      if (content.trim()) {
        localStorage.setItem(draftKey, content)
      } else {
        localStorage.removeItem(draftKey)
      }
    }, 500)
    return () => clearTimeout(timeoutId)
  }, [content, conversationId])

  // 发送消息后清除草稿
  useEffect(() => {
    if (!content.trim()) {
      const draftKey = `draft_${conversationId}`
      localStorage.removeItem(draftKey)
    }
  }, [content, conversationId])

  // 处理文件选择
  const handleFileSelect = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (file) {
      try {
        setUploadProgress({ visible: true, progress: 0, filename: file.name })

        const result = await uploadFile(file, {
          onProgress: (prog) => {
            setUploadProgress({
              visible: true,
              progress: prog.progress,
              filename: file.name
            })
          },
          onComplete: (fileId, downloadUrl) => {
            // 发送文件消息
            const fileMessage = JSON.stringify({
              fileId,
              filename: file.name,
              size: file.size,
              type: file.type,
              url: downloadUrl
            })
            sendMessage(conversationId, fileMessage)
            setUploadProgress(null)
            resetUpload()
            showToast('文件发送成功')
          },
          onError: (error) => {
            setUploadProgress(null)
            showToast(`文件上传失败：${error}`)
            resetUpload()
          }
        })

        if (!result) {
          setUploadProgress(null)
          showToast('文件上传失败')
          resetUpload()
        }
      } catch (err) {
        setUploadProgress(null)
        showToast('文件上传出错')
        resetUpload()
      }
    }
    // 重置 input 以允许重复选择同一文件
    if (fileInputRef.current) {
      fileInputRef.current.value = ''
    }
  }

  // 处理图片选择
  const handleImageSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (file && file.type.startsWith('image/')) {
      const reader = new FileReader()
      reader.onload = (event) => {
        const imgUrl = event.target?.result as string
        // 发送图片消息（使用 [image:url] 格式）
        const imageMarkup = `[image:${imgUrl}]`
        sendMessage(conversationId, imageMarkup)
      }
      reader.readAsDataURL(file)
    }
    if (imageInputRef.current) {
      imageInputRef.current.value = ''
    }
  }

  // 处理语音消息上传
  const handleVoiceMessageUpload = (audioBlob: Blob, duration: number, _waveform: number[]) => {
    const api = getApiClient()
    try {
      showToast('正在发送语音消息...')
      // 将 Blob 转换为 File
      const audioFile = new File([audioBlob], `voice_${Date.now()}.webm`, { type: 'audio/webm' })
      api.uploadVoice(audioFile, duration).then(result => {
        if (result.success && result.data) {
          // 发送语音消息（使用 [voice:url:duration] 格式）
          const voiceMarkup = `[voice:${result.data.url}:${duration}]`
          sendMessage(conversationId, voiceMarkup)
          showToast('语音消息已发送')
        }
      }).catch(() => {
        showToast('语音消息上传失败')
      })
    } catch (err) {
      showToast('语音消息上传出错')
    }
  }

  // 增强的表情分类
  const emojiCategories = [
    {
      id: 'recent',
      label: '最近',
      emojis: ['👍', '👎', '❤️', '😂', '😮', '😢', '😡', '🎉', '🔥', '⭐', '💯', '✨', '💪', '🙏', '😊', '🤔']
    },
    {
      id: 'emotion',
      label: '表情',
      emojis: ['😀', '😃', '😄', '😁', '😆', '😅', '🤣', '😂', '🙂', '🙃', '😉', '😊', '😇', '🥰', '😍', '🤩', '😘', '😗', '😚', '😙', '😋', '😛', '😜', '🤪', '😝', '🤑', '🤗', '🤭', '🤫', '🤔', '🤐', '🤨', '😐', '😑', '😶', '😏', '😒', '🙄', '😬', '🤥', '😌', '😔', '😪', '🤤', '😴', '😷', '🤒', '🤕', '🤢', '🤮', '🤧', '🥵', '🥶', '🥴', '😵', '🤯', '🤠', '🥳', '😎', '🤓', '🧐', '😕', '😟', '🙁', '☹️', '😮', '😯', '😲', '😳', '🥺', '😦', '😧', '😨', '😰', '😥', '😢', '😭', '😱', '😖', '😣', '😞', '😓', '😩', '😫', '🥱', '😤', '😡', '😠', '🤬', '😈', '👿', '💀', '☠️', '💩', '🤡', '👹', '👺', '👻', '👽', '👾', '🤖']
    },
    {
      id: 'gesture',
      label: '手势',
      emojis: ['👋', '🤚', '🖐️', '✋', '🖖', '👌', '🤌', '🤏', '✌️', '🤞', '🤟', '🤘', '🤙', '👈', '👉', '👆', '🖕', '👇', '☝️', '👍', '👎', '✊', '👊', '🤛', '🤜', '👏', '🙌', '👐', '🤲', '🤝', '🙏', '✍️', '💅', '🤳', '💪']
    },
    {
      id: 'heart',
      label: '爱心',
      emojis: ['❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '🤎', '💔', '❣️', '💕', '💞', '💓', '💗', '💖', '💘', '💝', '💟', '☮️', '✝️', '☪️', '🕉️', '☸️', '✡️', '🔯', '🕎', '☯️', '☦️', '🛐', '⛎', '♈', '♉', '♊', '♋', '♌', '♍', '♎', '♏', '♐', '♑', '♒', '♓', '🆔', '⚛️']
    },
    {
      id: 'animals',
      label: '动物',
      emojis: ['🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼', '🐨', '🐯', '🦁', '🐮', '🐷', '🐸', '🐵', '🐔', '🐧', '🐦', '🐤', '🦆', '🦅', '🦉', '🦇', '🐺', '🐗', '🐴', '🦄', '🐝', '🐛', '🦋', '🐌', '🐞', '🐜', '🦟', '🦗', '🕷️', '🕸️', '🐢', '🐍', '🦎', '🦖', '🦕', '🐙', '🦑', '🦐', '🦞', '🦀', '🐡', '🐠', '🐟', '🐬', '🐳', '🐋', '🦈', '🐊', '🐅', '🐆', '🦓', '🦍', '🦧', '🐘', '🦛', '🦏', '🐪', '🐫', '🦒', '🦘', '🐃', '🐄', '🐂', '🐎', '🐖', '🐏', '🐑', '🦙', '🐐', '🦌', '🐕', '🐩', '🦮', '🐕‍🦺', '🐈', '🐓', '🦃', '🦚', '🦜', '🦢', '🦩', '🕊️', '🐇', '🦝', '🦨', '🦡', '🦦', '🦥', '🐁', '🐀', '🐿️', '🦔']
    },
    {
      id: 'food',
      label: '食物',
      emojis: ['🍎', '🍐', '🍊', '🍋', '🍌', '🍉', '🍇', '🍓', '🍈', '🍒', '🍑', '🥭', '🍍', '🥥', '🥝', '🍅', '🍆', '🥑', '🥦', '🥬', '🥒', '🌶️', '🌽', '🥕', '🧄', '🧅', '🥔', '🍠', '🥐', '🥯', '🍞', '🥖', '🥨', '🧀', '🥚', '🍳', '🧈', '🥞', '🧇', '🥓', '🥩', '🍗', '🍖', '🦴', '🌭', '🍔', '🍟', '🍕', '🥪', '🥙', '🧆', '🌮', '🌯', '🥗', '🥘', '🍝', '🍜', '🍲', '🍛', '🍣', '🍱', '🥟', '🦪', '🍤', '🍙', '🍚', '🍘', '🍥', '🥠', '🍢', '🍡', '🍧', '🍨', '🍦', '🥧', '🧁', '🍰', '🎂', '🍮', '🍭', '🍬', '🍫', '🍿', '🍩', '🍪', '🌰', '🥜', '🍯', '🥛', '🍼', '☕', '🍵', '🧃', '🥤', '🍶', '🍺', '🍻', '🥂', '🍷', '🥃', '🍸', '🍹', '🧉', '🍾']
    },
    {
      id: 'sports',
      label: '运动',
      emojis: ['⚽', '🏀', '🏈', '⚾', '🥎', '🎾', '🏐', '🏉', '🥏', '🎱', '🪀', '🏓', '🏸', '🏒', '🏑', '🥍', '🏏', '🪃', '🥅', '⛳', '🪁', '🏹', '🎣', '🤿', '🥊', '🥋', '🎽', '🛹', '🛼', '🛷', '⛸️', '🥌', '🎿', '⛷️', '🏂', '🪂', '🏋️‍♂️', '🤼‍♂️', '🤾‍♂️', '🏌️‍♂️', '🏇', '⛹️‍♂️', '🏆', '🥇', '🥈', '🥉', '🏅', '🎖️', '🏵️', '🎗️', '🎫', '🎟️', '🎪', '🤹‍♂️', '🎭', '🩰', '🎨', '🎬', '🎤', '🎧', '🎼', '🎹', '🥁', '🎷', '🎺', '🎸', '🪕', '🎻', '🎲', '♟️', '🎯', '🎳', '🎮', '🎰', '🧩']
    },
    {
      id: 'travel',
      label: '旅行',
      emojis: ['🚗', '🚕', '🚙', '🚌', '🚎', '🏎️', '🚓', '🚑', '🚒', '🚐', '🛻', '🚚', '🚛', '🚜', '🦯', '🦽', '🦼', '🛴', '🚲', '🛵', '🏍️', '🛺', '🚨', '🚔', '🚍', '🚘', '🚖', '🚡', '🚠', '🚟', '🚃', '🚋', '🚞', '🚝', '🚄', '🚅', '🚈', '🚂', '🚆', '🚇', '🚊', '🚉', '✈️', '🛫', '🛬', '🛩️', '💺', '🛰️', '🚀', '🛸', '🚁', '🛶', '⛵', '🚤', '🛥️', '🛳️', '⛴️', '🚢', '⚓', '🪝', '⛽', '🚧', '🚦', '🚥', '🚏', '🗺️', '🗿', '🗽', '🗼', '🏰', '🏯', '🏟️', '🎡', '🎢', '🎠', '⛲', '⛱️', '🏖️', '🏝️', '🏜️', '🌋', '⛰️', '🏔️', '🗻', '🏕️', '⛺', '🛖', '🏠', '🏡', '🏘️', '🏚️', '🏗️', '🏭', '🏢', '🏬', '🏣', '🏤', '🏥', '🏦', '🏨', '🏪', '🏫', '🏩', '💒', '🛕', '🕌', '🛖', '⛪', '🕋', '🌁', '🌃', '🏙️', '🌄', '🌅', '🌆', '🌇', '🌉']
    },
    {
      id: 'objects',
      label: '物品',
      emojis: ['⌚', '📱', '💻', '⌨️', '🖥️', '🖨️', '🖱️', '🖲️', '🕹️', '🗜️', '💽', '💾', '💿', '📀', '📼', '📷', '📸', '📹', '🎥', '📽️', '🎞️', '📞', '☎️', '📟', '📠', '📺', '📻', '🎙️', '🎚️', '🎛️', '🧭', '⏱️', '⏲️', '⏰', '🕰️', '⌛', '⏳', '📡', '🔋', '🔌', '💡', '🔦', '🕯️', '🪔', '🧯', '🛢️', '💸', '💵', '💴', '💶', '💷', '🪙', '💰', '💳', '💎', '⚖️', '🪜', '🧰', '🪛', '🔧', '🔨', '⚒️', '🛠️', '⛏️', '🪚', '🔩', '⚙️', '🪤', '🧱', '⛓️', '🧲', '🔫', '💣', '🧨', '🪓', '🔪', '🗡️', '⚔️', '🛡️', '🚬', '⚰️', '🪦', '⚱️', '🏺', '🔮', '📿', '🧿', '💈', '⚗️', '🔭', '🔬', '🕳️', '🩹', '🩺', '💊', '💉', '🩸', '🧬', '🦠', '🧫', '🧪', '🌡️', '🧹', '🪠', '🧺', '🧻', '🚽', '🚰', '🚿', '🛁', '🛀', '🧼', '🪒', '🪥', '🧽', '🧴', '🛎️', '🔑', '🗝️', '🚪', '🪑', '🛋️', '🛏️', '🛌', '🧸', '🪆', '🖼️', '🪞', '🪟', '🛍️', '🛒', '🎁', '🎈', '🎏', '🎀', '🪄', '🪅', '🎊', '🎉', '🎎', '🏮', '🎐', '🧧', '✉️', '📩', '📨', '📧', '💌', '📥', '📤', '📦', '🏷️', '🪧', '📪', '📫', '📬', '📭', '📮', '📯', '📜', '📃', '📄', '📑', '🧾', '📊', '📈', '📉', '🗒️', '🗓️', '📆', '📅', '🗑️', '📇', '🗃️', '🗳️', '🗄️', '📋', '📁', '📂', '🗂️', '🗞️', '📰', '📓', '📔', '📒', '📕', '📗', '📘', '📙', '📚', '📖', '🔖', '🧷', '🔗', '📎', '🖇️', '📐', '📏', '🧮', '📌', '📍', '✂️', '🖊️', '🖋️', '✒️', '🖌️', '🖍️', '📝', '✏️', '🔍', '🔎', '🔏', '🔐', '🔒', '🔓']
    },
    {
      id: 'symbols',
      label: '符号',
      emojis: ['❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '🤎', '💔', '❣️', '💕', '💞', '💓', '💗', '💖', '💘', '💝', '💟', '☮️', '✝️', '☪️', '🕉️', '☸️', '✡️', '🔯', '🕎', '☯️', '☦️', '🛐', '⛎', '♈', '♉', '♊', '♋', '♌', '♍', '♎', '♏', '♐', '♑', '♒', '♓', '🆔', '⚛️', '🉑', '☢️', '☣️', '📴', '📳', '🈶', '🈚', '🈸', '🈺', '🈷️', '✴️', '🆚', '💮', '🉐', '㊙️', '㊗️', '🈴', '🈵', '🈹', '🈲', '🅰️', '🅱️', '🆎', '🆑', '🅾️', '🆘', '❌', '⭕', '🛑', '⛔', '📛', '🚫', '💯', '💢', '♨️', '🚷', '🚯', '🚳', '🚱', '🔞', '📵', '🚭', '❗', '❕', '❓', '❔', '‼️', '⁉️', '🔅', '🔆', '〽️', '⚠️', '🚸', '🔱', '⚜️', '🔰', '♻️', '✅', '🈯', '💹', '❇️', '✳️', '❎', '🌐', '💠', 'Ⓜ️', '🌀', '💤', '🏧', '🚾', '♿', '🅿️', '🛗', '🈳', '🈂️', '🛂', '🛃', '🛄', '🛅', '🚹', '🚺', '🚼', '⚧️', '🚻', '🚮', '🎦', '📶', '🈁', '🔣', 'ℹ️', '🔤', '🔡', '🔠', '🆖', '🆗', '🆙', '🆒', '🆕', '🆓', '0️⃣', '1️⃣', '2️⃣', '3️⃣', '4️⃣', '5️⃣', '6️⃣', '7️⃣', '8️⃣', '9️⃣', '🔟', '🔢', '#️⃣', '*️⃣', '⏏️', '▶️', '⏸️', '⏯️', '⏹️', '⏺️', '⏭️', '⏮️', '⏩', '⏪', '⏫', '⏬', '◀️', '🔼', '🔽', '➡️', '⬅️', '🔼', '🔽', '↪️', '↩️', '⤴️', '⤵️', '🔀', '🔁', '🔂', '🔄', '🔃', '🎵', '🎶', '➕', '➖', '➗', '✖️', '♾️', '💲', '💱', '™️', '©️', '®️', '〰️', '➰', '➿', '✔️', '☑️', '🔘', '🔴', '🟠', '🟡', '🟢', '🔵', '🟣', '⚫', '⚪', '🟤', '🔺', '🔻', '🔸', '🔹', '🔶', '🔷', '🔳', '🔲', '▪️', '▫️', '◾', '◽', '◼️', '◻️', '🟥', '🟧', '🟨', '🟩', '🟦', '🟪', '⬛', '⬜', '🟫', '🔈', '🔇', '🔉', '🔊', '🔔', '🔕', '📣', '📢', '💬', '💭', '🗯️', '♠️', '♣️', '♥️', '♦️', '🃏', '🎴', '🀄', '🕐', '🕜', '🕑', '🕝', '🕒', '🕞', '🕓', '🕟', '🕔', '🕠', '🕕', '🕡', '🕖', '🕢', '🕗', '🕣', '🕘', '🕤', '🕙', '🕥', '🕚', '🕦', '👁️‍🗨️']
    }
  ]

  const [activeEmojiCategory, setActiveEmojiCategory] = useState('recent')
  const [emojiSearchQuery, setEmojiSearchQuery] = useState('')
  const [showGifPicker, setShowGifPicker] = useState(false)
  const [gifSearchQuery, setGifSearchQuery] = useState('')
  const [activeGifCategory, setActiveGifCategory] = useState('trending')
  const [gifs, setGifs] = useState<Gif[]>([])
  const [isLoadingGifs, setIsLoadingGifs] = useState(false)
  const [gifError, setGifError] = useState<string | null>(null)

  // GIF 分类列表
  const gifCategoryList = [
    { id: 'trending', label: '热门' },
    { id: 'reactions', label: '表情回应' },
    { id: 'animals', label: '动物' },
    { id: 'sports', label: '运动' },
    { id: 'entertainment', label: '娱乐' },
    { id: 'memes', label: '梗图' },
    { id: 'love', label: '爱心' },
    { id: 'celebration', label: '庆祝' },
    { id: 'funny', label: '搞笑' }
  ]

  // 加载 GIF
  const loadGifs = async () => {
    setIsLoadingGifs(true)
    setGifError(null)

    try {
      let result: Gif[]

      if (gifSearchQuery.trim()) {
        // 搜索 GIF
        result = await searchGifs(gifSearchQuery, { limit: 20 })
      } else if (activeGifCategory === 'trending') {
        // 获取热门 GIF
        result = await getTrendingGifs({ limit: 20 })
      } else {
        // 按分类获取
        result = await getGifsByCategory(activeGifCategory, { limit: 20 })
      }

      if (result.length === 0) {
        setGifError('未找到相关 GIF')
      }
      setGifs(result)
    } catch (err) {
      console.error('Failed to load GIFs:', err)
      setGifError('加载 GIF 失败，请检查网络连接')
      // 回退到模拟数据
      setGifs(getFallbackGifs())
    } finally {
      setIsLoadingGifs(false)
    }
  }

  useEffect(() => {
    if (!showGifPicker) return

    const debounceTimer = setTimeout(loadGifs, 300)
    return () => clearTimeout(debounceTimer)
  }, [showGifPicker, gifSearchQuery, activeGifCategory])

  // 回退 GIF 数据（当 API 不可用时）
  const getFallbackGifs = (): Gif[] => {
    const gifPlaceholders: Array<{ id: string; url: string; title: string }> = [
      { id: '1', url: 'https://media.giphy.com/media/v1.Y2lkPTc5MGI3NjExcDdxeGJ3Ym5xeXc3eDh4eDh4eDh4eDh4eDh4eDh4eCZlcD12MV9pbnRlcm5hbF9naWZfYnlfaWQmY3Q9Zw/3o7TKSjRrfIPjeiVyM/giphy.gif', title: 'Excited' },
      { id: '2', url: 'https://media.giphy.com/media/v1.Y2lkPTc5MGI3NjExcDdxeGJ3Ym5xeXc3eDh4eDh4eDh4eDh4eDh4eDh4eCZlcD12MV9pbnRlcm5hbF9naWZfYnlfaWQmY3Q9Zw/l0HlHFRbmaZtBRhXG/giphy.gif', title: 'Cool' },
      { id: '3', url: 'https://media.giphy.com/media/v1.Y2lkPTc5MGI3NjExcDdxeGJ3Ym5xeXc3eDh4eDh4eDh4eDh4eDh4eDh4eCZlcD12MV9pbnRlcm5hbF9naWZfYnlfaWQmY3Q9Zw/3o6Zt481isNVuQI1l6/giphy.gif', title: 'Love' },
      { id: '4', url: 'https://media.giphy.com/media/v1.Y2lkPTc5MGI3NjExcDdxeGJ3Ym5xeXc3eDh4eDh4eDh4eDh4eDh4eDh4eCZlcD12MV9pbnRlcm5hbF9naWZfYnlfaWQmY3Q9Zw/26ufdipQqU2lhNA4g/giphy.gif', title: 'Happy' },
      { id: '5', url: 'https://media.giphy.com/media/v1.Y2lkPTc5MGI3NjExcDdxeGJ3Ym5xeXc3eDh4eDh4eDh4eDh4eDh4eDh4eCZlcD12MV9pbnRlcm5hbF9naWZfYnlfaWQmY3Q9Zw/xT9IgG50Fb7Mi0prBC/giphy.gif', title: 'Wow' },
      { id: '6', url: 'https://media.giphy.com/media/v1.Y2lkPTc5MGI3NjExcDdxeGJ3Ym5xeXc3eDh4eDh4eDh4eDh4eDh4eDh4eCZlcD12MV9pbnRlcm5hbF9naWZfYnlfaWQmY3Q9Zw/3o7abKhOpu0NwenH3O/giphy.gif', title: 'Thumbs Up' },
      { id: '7', url: 'https://media.giphy.com/media/v1.Y2lkPTc5MGI3NjExcDdxeGJ3Ym5xeXc3eDh4eDh4eDh4eDh4eDh4eDh4eCZlcD12MV9pbnRlcm5hbF9naWZfYnlfaWQmY3Q9Zw/l0MYt5jPR6tXr6uHC/giphy.gif', title: 'Dancing' },
      { id: '8', url: 'https://media.giphy.com/media/v1.Y2lkPTc5MGI3NjExcDdxeGJ3Ym5xeXc3eDh4eDh4eDh4eDh4eDh4eDh4eCZlcD12MV9pbnRlcm5hbF9naWZfYnlfaWQmY3Q9Zw/3o6ZtaO9BZHfcOv2Vi/giphy.gif', title: 'Laughing' }
    ]

    return gifPlaceholders.map(g => ({
      ...g,
      images: {
        original: { url: g.url, width: '480', height: '270', size: '1000000' },
        preview: { url: g.url, width: '240', height: '135' },
        fixed_height: { url: g.url, width: '200', height: '200' },
        fixed_width: { url: g.url, width: '200', height: '200' }
      }
    }))
  }

  // 获取当前分类的表情
  const getCurrentEmojis = () => {
    const category = emojiCategories.find(c => c.id === activeEmojiCategory)
    const emojis = category?.emojis || []

    if (emojiSearchQuery.trim()) {
      return emojis.filter(e => e.includes(emojiSearchQuery.trim()))
    }
    return emojis
  }

  return (
    <div className="p-4 bg-gradient-to-r from-gray-800/90 to-gray-800/70 backdrop-blur border-t border-gray-700/50 relative">
      {/* 草稿提示 */}
      {draftContent && content !== draftContent && (
        <div className="flex items-center justify-between p-2.5 bg-gradient-to-r from-yellow-500/20 to-orange-500/20 border border-yellow-500/30 rounded-xl mb-2 backdrop-blur">
          <span className="text-xs text-yellow-400 flex items-center gap-1.5">
            <svg className="w-3.5 h-3.5" fill="currentColor" viewBox="0 0 24 24">
              <path d="M19.952 1.651a.75.75 0 01.298.599V16.303a3 3 0 01-1.185 2.388l-8.729 6.902a.75.75 0 01-.927 0l-8.73-6.902a3 3 0 01-1.184-2.388V2.25a.75.75 0 01.298-.599L5.45 1.002a.75.75 0 01.562 0l2.256.6a.75.75 0 00.385 0l2.257-.6a.75.75 0 01.56 0l2.258.6a.75.75 0 00.384 0l2.258-.6a.75.75 0 01.562 0l3.02.65z"/>
            </svg>
            已恢复未发送的草稿
          </span>
          <button
            onClick={() => {
              setContent('')
              localStorage.removeItem(`draft_${conversationId}`)
            }}
            className="text-xs text-yellow-400 hover:text-yellow-300 font-medium"
          >
            清除
          </button>
        </div>
      )}

      {/* 回复提示条 */}
      {replyingTo && (
        <div className="flex items-center justify-between p-3 bg-gradient-to-r from-blue-600/20 to-indigo-600/20 backdrop-blur rounded-xl mb-2 border-l-4 border-blue-500 shadow-lg">
          <div className="flex-1 min-w-0">
            <div className="text-xs text-blue-400 font-medium mb-1 flex items-center gap-1">
              <svg className="w-3 h-3" fill="currentColor" viewBox="0 0 24 24">
                <path d="M10 9V5l-7 7 7 7v-4.1c5 0 8.5 1.6 11 5.1-1-5.6-4-10-11-11z"/>
              </svg>
              回复给 {replyingTo.senderName}
            </div>
            <div className="text-sm text-gray-400 truncate">
              {replyingTo.content}
            </div>
          </div>
          <button
            onClick={onCancelReply}
            className="ml-3 p-1.5 text-gray-400 hover:text-white hover:bg-gray-700/50 rounded-lg transition-all"
          >
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>
      )}

      {/* 格式化工具栏 */}
      <div className="flex items-center gap-1 mb-2 px-2" ref={pickerContainerRef}>
        <button
          onClick={handleBold}
          className="p-2 text-gray-400 hover:text-white hover:bg-gray-700/50 rounded-lg transition-all"
          title="粗体 (Ctrl+B)"
        >
          <span className="font-bold text-sm">B</span>
        </button>
        <button
          onClick={handleItalic}
          className="p-2 text-gray-400 hover:text-white hover:bg-gray-700/50 rounded-lg transition-all"
          title="斜体 (Ctrl+I)"
        >
          <span className="italic text-sm">I</span>
        </button>
        <button
          onClick={handleStrike}
          className="p-2 text-gray-400 hover:text-white hover:bg-gray-700/50 rounded-lg transition-all"
          title="删除线 (Ctrl+E)"
        >
          <span className="line-through text-sm">S</span>
        </button>
        <button
          onClick={handleCode}
          className="p-2 text-gray-400 hover:text-white hover:bg-gray-700/50 rounded-lg transition-all"
          title="代码 (Ctrl+K)"
        >
          <span className="font-mono text-xs">&lt;/&gt;</span>
        </button>
        <button
          onClick={handleQuote}
          className="p-2 text-gray-400 hover:text-white hover:bg-gray-700/50 rounded-lg transition-all"
          title="引用"
        >
          <span className="text-sm">"</span>
        </button>
        <div className="flex-1" />
        <div className="text-xs text-gray-500 bg-gray-700/30 px-2 py-1 rounded-lg">
          {wordCount} 词 | {charCount} 字
        </div>
      </div>

      <div className="flex items-end space-x-2">
        {/* 附件按钮 */}
        <button
          onClick={() => fileInputRef.current?.click()}
          className="p-2.5 text-gray-400 hover:text-white hover:bg-gray-700/50 rounded-xl transition-all"
          title="发送附件"
        >
          <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M15.172 7l-6.586 6.586a2 2 0 102.828 2.828l6.414-6.586a4 4 0 00-5.656-5.656l-6.415 6.585a6 6 0 108.486 8.486L20.5 13"
            />
          </svg>
        </button>

        {/* 图片按钮 */}
        <button
          onClick={() => imageInputRef.current?.click()}
          className="p-2.5 text-gray-400 hover:text-white hover:bg-gray-700/50 rounded-xl transition-all"
          title="发送图片"
        >
          <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v8a2 2 0 002 2z"
            />
          </svg>
        </button>

        {/* 语音消息按钮 */}
        <button
          onClick={() => setShowVoiceRecorder(true)}
          className="p-2.5 text-gray-400 hover:text-white hover:bg-gray-700/50 rounded-xl transition-all"
          title="语音消息"
        >
          <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z"
            />
          </svg>
        </button>

        {/* 表情按钮 */}
        <button
          onClick={() => setShowEmojiPicker(!showEmojiPicker)}
          className="p-2.5 text-gray-400 hover:text-white hover:bg-gray-700/50 rounded-xl transition-all"
          title="表情"
        >
          <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M14.828 14.828a4 4 0 01-5.656 0M9 10h.01M15 10h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
            />
          </svg>
        </button>

        {/* GIF 按钮 */}
        <button
          onClick={() => {
            setShowGifPicker(!showGifPicker)
            setShowEmojiPicker(false)
          }}
          className="p-2.5 text-gray-400 hover:text-white hover:bg-gray-700/50 rounded-xl transition-all relative"
          title="GIF"
        >
          <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v8a2 2 0 002 2z"
            />
          </svg>
        </button>

        {/* 消息反应按钮 */}
        <button
          onClick={() => setShowReactionPicker(!showReactionPicker)}
          className="p-2.5 text-gray-400 hover:text-white hover:bg-gray-700/50 rounded-xl transition-all"
          title="消息反应"
        >
          <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M14.828 14.828a4 4 0 01-5.656 0M9 10h.01M15 10h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
            />
          </svg>
        </button>

        {/* 输入框 */}
        <div className="flex-1 relative">
          <textarea
            ref={textareaRef}
            value={content}
            onChange={handleChange}
            onKeyDown={handleKeyDown}
            onCompositionStart={handleCompositionStart}
            onCompositionEnd={handleCompositionEnd}
            placeholder="输入消息... (Enter 发送，Shift+Enter 换行，↑↓ 查看历史)"
            rows={1}
            className="w-full px-4 py-3 bg-gray-700/50 backdrop-blur border border-gray-600/50 rounded-2xl
                     text-white placeholder-gray-500 focus:outline-none focus:ring-2
                     focus:ring-blue-500/50 focus:border-transparent resize-none
                     max-h-[120px] transition-all"
          />
        </div>

        {/* 发送按钮 */}
        <button
          onClick={handleSend}
          disabled={!content.trim()}
          className="relative p-2.5 bg-gradient-to-r from-blue-500 to-indigo-600 hover:from-blue-600 hover:to-indigo-700 disabled:from-gray-600 disabled:to-gray-700
                   disabled:cursor-not-allowed text-white rounded-xl transition-all
                   hover:shadow-lg hover:shadow-blue-500/30 active:scale-95 disabled:opacity-50"
          title={content.trim() ? '发送 (Enter)' : '输入消息'}
        >
          {isUploading ? (
            <svg className="w-5 h-5 animate-spin" fill="none" viewBox="0 0 24 24">
              <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
              <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
            </svg>
          ) : (
            <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 20 20">
              <path d="M10.894 2.553a1 1 0 00-1.788 0l-7 14a1 1 0 001.169 1.409l5-1.429A1 1 0 009 15.571V11a1 1 0 112 0v4.571a1 1 0 00.725.962l5 1.428a1 1 0 001.17-1.408l-7-14z" />
            </svg>
          )}
        </button>
      </div>

      {/* 隐藏的文件输入 */}
      <input
        ref={fileInputRef}
        type="file"
        className="hidden"
        onChange={handleFileSelect}
      />
      <input
        ref={imageInputRef}
        type="file"
        className="hidden"
        accept="image/*"
        onChange={handleImageSelect}
      />

      {/* 表情选择器 */}
      {showEmojiPicker && (
        <div className="absolute bottom-full left-0 mb-2 bg-gradient-to-br from-gray-800 to-gray-900 border border-gray-700/50 rounded-2xl shadow-2xl z-50 w-80 backdrop-blur" ref={pickerContainerRef}>
          {/* 搜索框 */}
          <div className="p-2 border-b border-gray-700/50">
            <input
              type="text"
              value={emojiSearchQuery}
              onChange={(e) => setEmojiSearchQuery(e.target.value)}
              placeholder="搜索表情..."
              className="w-full px-3 py-2 bg-gray-700/50 border border-gray-600/50 rounded-xl text-white text-sm focus:outline-none focus:ring-2 focus:ring-blue-500/50"
              autoFocus
            />
          </div>

          {/* 分类标签 */}
          <div className="flex items-center gap-1 px-2 py-2 border-b border-gray-700/50 overflow-x-auto">
            {emojiCategories.map((category) => (
              <button
                key={category.id}
                onClick={() => setActiveEmojiCategory(category.id)}
                className={`px-2.5 py-1.5 text-xs rounded-xl whitespace-nowrap transition-all ${
                  activeEmojiCategory === category.id
                    ? 'bg-gradient-to-r from-blue-500 to-indigo-600 text-white shadow-lg'
                    : 'text-gray-400 hover:bg-gray-700/50'
                }`}
              >
                {category.label}
              </button>
            ))}
          </div>

          {/* 表情网格 */}
          <div className="p-2 max-h-64 overflow-y-auto">
            <div className="grid grid-cols-8 gap-1">
              {getCurrentEmojis().map((emoji) => (
                <button
                  key={emoji}
                  onClick={() => {
                    handleEmojiSelect(emoji)
                    setShowEmojiPicker(false)
                  }}
                  className="w-9 h-9 hover:bg-gray-700/50 rounded-xl transition-all flex items-center justify-center text-xl"
                >
                  {emoji}
                </button>
              ))}
            </div>
            {getCurrentEmojis().length === 0 && (
              <div className="text-center py-4 text-gray-400 text-sm">
                未找到相关表情
              </div>
            )}
          </div>
        </div>
      )}

      {/* GIF 选择器 */}
      {showGifPicker && (
        <div className="absolute bottom-full left-0 mb-2 bg-gradient-to-br from-gray-800 to-gray-900 border border-gray-700/50 rounded-2xl shadow-2xl z-50 w-96 max-h-[500px] flex flex-col backdrop-blur" ref={pickerContainerRef}>
          {/* 搜索框 */}
          <div className="p-3 border-b border-gray-700/50">
            <input
              type="text"
              value={gifSearchQuery}
              onChange={(e) => setGifSearchQuery(e.target.value)}
              placeholder={isGiphyConfigured() ? '搜索 GIPHY...' : '搜索 GIF...'}
              className="w-full px-3 py-2 bg-gray-700/50 border border-gray-600/50 rounded-xl text-white text-sm focus:outline-none focus:ring-2 focus:ring-blue-500/50"
              autoFocus
            />
          </div>

          {/* 分类标签 */}
          <div className="flex items-center gap-1 px-3 py-2 border-b border-gray-700/50 overflow-x-auto flex-shrink-0">
            {gifCategoryList.map((category) => (
              <button
                key={category.id}
                onClick={() => setActiveGifCategory(category.id)}
                className={`px-3 py-1.5 text-xs rounded-full whitespace-nowrap transition-all ${
                  activeGifCategory === category.id
                    ? 'bg-gradient-to-r from-blue-500 to-indigo-600 text-white shadow-lg'
                    : 'text-gray-400 hover:bg-gray-700/50'
                }`}
              >
                {category.label}
              </button>
            ))}
          </div>

          {/* GIF 网格 */}
          <div className="p-3 overflow-y-auto flex-1">
            {isLoadingGifs ? (
              <div className="flex items-center justify-center py-8">
                <svg className="animate-spin h-8 w-8 text-blue-500" fill="none" viewBox="0 0 24 24">
                  <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                  <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
                </svg>
                <span className="ml-2 text-gray-400 text-sm">加载中...</span>
              </div>
            ) : gifError ? (
              <div className="text-center py-8">
                <div className="text-gray-400 text-sm mb-2">{gifError}</div>
                <div className="text-gray-500 text-xs">显示示例数据</div>
              </div>
            ) : (
              <div className="grid grid-cols-3 gap-2">
                {gifs.map((gif) => (
                  <button
                    key={gif.id}
                    onClick={() => {
                      // 发送 GIF 消息（使用 [gif:url] 格式）
                      const gifMarkup = `[gif:${gif.images.fixed_width?.url || gif.url}]`
                      sendMessage(conversationId, gifMarkup)
                      setShowGifPicker(false)
                      setGifSearchQuery('')
                      showToast(`已发送 GIF: ${gif.title}`)
                    }}
                    className="relative aspect-square rounded-xl overflow-hidden hover:ring-2 hover:ring-blue-500 transition-all shadow-lg hover:shadow-xl"
                    title={gif.title}
                  >
                    <img
                      src={gif.images.preview?.url || gif.url}
                      alt={gif.title}
                      className="w-full h-full object-cover"
                      loading="lazy"
                    />
                  </button>
                ))}
              </div>
            )}
            {gifs.length === 0 && !isLoadingGifs && !gifError && (
              <div className="text-center py-8 text-gray-400 text-sm">
                未找到相关 GIF
              </div>
            )}
          </div>

          {/* 底部提示 */}
          <div className="px-3 py-2 border-t border-gray-700/50 bg-gray-800/50 rounded-b-2xl flex-shrink-0">
            <p className="text-xs text-gray-500 text-center">
              {isGiphyConfigured() ? (
                <span>由 <span className="font-semibold">GIPHY</span> 提供</span>
              ) : (
                <span>示例数据 - 配置 VITE_GIPHY_API_KEY 以启用真实 GIF</span>
              )}
            </p>
          </div>
        </div>
      )}

      {/* 语音消息录制器 */}
      {showVoiceRecorder && (
        <VoiceMessageRecorder
          onClose={() => setShowVoiceRecorder(false)}
          onSend={handleVoiceMessageUpload}
        />
      )}

      {/* @提及建议 */}
      {showMentions && mentionSuggestions.length > 0 && (
        <div className="absolute bottom-full left-0 mb-2 p-2 bg-gradient-to-br from-gray-800 to-gray-900 border border-gray-700/50 rounded-2xl shadow-2xl z-50 min-w-[180px] backdrop-blur" ref={pickerContainerRef}>
          <div className="text-xs text-gray-400 mb-2 px-2 font-medium">提及用户</div>
          {mentionSuggestions.map((username) => (
            <button
              key={username}
              onClick={() => handleMentionSelect(username)}
              className="w-full px-3 py-2 text-left hover:bg-gray-700/50 rounded-xl transition-all flex items-center gap-2"
            >
              <div className="w-7 h-7 rounded-full bg-gradient-to-br from-blue-500 to-purple-600 flex items-center justify-center text-white text-xs font-medium shadow-lg">
                {username.charAt(0).toUpperCase()}
              </div>
              <span className="text-white text-sm">{username}</span>
            </button>
          ))}
        </div>
      )}

      {/* 消息反应选择器 */}
      {showReactionPicker && (
        <div className="absolute bottom-full left-0 mb-2 p-2 bg-gradient-to-br from-gray-800 to-gray-900 border border-gray-700/50 rounded-2xl shadow-2xl z-50 backdrop-blur" ref={pickerContainerRef}>
          <div className="grid grid-cols-8 gap-1">
            {['👍', '👎', '❤️', '😂', '😮', '😢', '😡', '🎉', '🔥', '⭐', '💯', '✨', '💪', '🙏', '😊', '🤔'].map((emoji) => (
              <button
                key={emoji}
                onClick={() => {
                  handleEmojiSelect(emoji)
                  setShowReactionPicker(false)
                }}
                className="w-9 h-9 hover:bg-gray-700/50 rounded-xl transition-all flex items-center justify-center text-xl"
              >
                {emoji}
              </button>
            ))}
          </div>
        </div>
      )}

      {/* 正在输入提示 */}
      {isTyping && (
        <div className="mt-2 flex items-center gap-1.5">
          <div className="flex gap-1">
            <span className="w-1.5 h-1.5 bg-gray-400 rounded-full animate-bounce" style={{ animationDelay: '0ms' }}></span>
            <span className="w-1.5 h-1.5 bg-gray-400 rounded-full animate-bounce" style={{ animationDelay: '150ms' }}></span>
            <span className="w-1.5 h-1.5 bg-gray-400 rounded-full animate-bounce" style={{ animationDelay: '300ms' }}></span>
          </div>
          <span className="text-xs text-gray-500">正在输入...</span>
          <span className="text-xs text-gray-600 ml-2 bg-gray-800/50 px-2 py-0.5 rounded-lg">{content.length} 字</span>
        </div>
      )}

      {/* 文件上传进度 */}
      {uploadProgress && (
        <div className="absolute bottom-full left-1/2 transform -translate-x-1/2 bg-gradient-to-br from-gray-800 to-gray-900 text-white px-6 py-4 rounded-2xl shadow-2xl z-50 mb-2 min-w-[320px] border border-gray-700/50 backdrop-blur">
          <div className="flex items-center justify-between mb-2">
            <span className="text-sm font-medium truncate max-w-[220px]">
              {uploadProgress.filename}
            </span>
            <span className="text-xs text-blue-400 font-mono">
              {uploadProgress.progress}%
            </span>
          </div>
          <div className="w-full bg-gray-700/50 rounded-full h-2.5 overflow-hidden">
            <div
              className="bg-gradient-to-r from-blue-500 to-indigo-600 h-full rounded-full transition-all duration-300"
              style={{ width: `${uploadProgress.progress}%` }}
            />
          </div>
          {isUploading && (
            <div className="mt-2 text-xs text-gray-400 flex items-center justify-center">
              <svg className="animate-spin h-3 w-3 mr-1" fill="none" viewBox="0 0 24 24">
                <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
              </svg>
              上传中...
            </div>
          )}
          {progress?.speed && (
            <div className="mt-1 text-xs text-gray-500 text-center">
              {(progress.speed / 1024 / 1024).toFixed(1)} MB/s
              {progress.eta && progress.eta > 0 && ` · 剩余 ${Math.ceil(progress.eta)}秒`}
            </div>
          )}
        </div>
      )}

      {/* Toast Notification */}
      {toast.visible && (
        <div className="absolute bottom-full left-1/2 transform -translate-x-1/2 bg-gradient-to-r from-gray-800 to-gray-900 text-white px-6 py-3 rounded-xl shadow-2xl z-50 animate-fade-in mb-2 border border-gray-700/50 backdrop-blur">
          {toast.message}
        </div>
      )}
    </div>
  )
}

export default MessageInput
