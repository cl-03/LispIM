/**
 * GroupPoll 组件 - 群投票功能
 */

import React, { useState, useEffect, useCallback } from 'react'
import { getApiClient, GroupPoll as GroupPollType, CreatePollData as CreatePollDataType } from '../utils/api-client'
import type { User } from '../types'

interface GroupPollProps {
  groupId: number
  currentUserId: string
  currentUser?: User
}

interface CreatePollFormData {
  title: string
  description: string
  options: string[]
  multipleChoice: boolean
  allowSuggestions: boolean
  anonymousVoting: boolean
  endAt?: string
}

export const GroupPoll: React.FC<GroupPollProps> = ({
  groupId,
  currentUserId,
  currentUser
}) => {
  const api = getApiClient()
  const [polls, setPolls] = useState<GroupPollType[]>([])
  const [selectedPoll, setSelectedPoll] = useState<GroupPollType | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [showCreateForm, setShowCreateForm] = useState(false)
  const [statusFilter, setStatusFilter] = useState<'active' | 'ended' | 'archived'>('active')

  // 创建投票表单状态
  const [formData, setFormData] = useState<CreatePollFormData>({
    title: '',
    description: '',
    options: ['', ''],
    multipleChoice: false,
    allowSuggestions: false,
    anonymousVoting: false,
    endAt: undefined
  })

  // 加载投票列表
  const loadPolls = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const result = await api.getGroupPolls(groupId, statusFilter)
      if (result.success && result.data) {
        setPolls(result.data as GroupPollType[])
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load polls')
    } finally {
      setLoading(false)
    }
  }, [groupId, statusFilter, api])

  useEffect(() => {
    loadPolls()
  }, [loadPolls])

  // 创建投票
  const handleCreatePoll = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    setError(null)
    try {
      const pollData: CreatePollDataType = {
        title: formData.title,
        description: formData.description,
        options: formData.options.filter(o => o.trim()),
        multipleChoice: formData.multipleChoice,
        allowSuggestions: formData.allowSuggestions,
        anonymousVoting: formData.anonymousVoting,
        endAt: formData.endAt ? new Date(formData.endAt).getTime() : undefined
      }
      const result = await api.createPoll(groupId, pollData)
      if (result.success) {
        setShowCreateForm(false)
        loadPolls()
        // 重置表单
        setFormData({
          title: '',
          description: '',
          options: ['', ''],
          multipleChoice: false,
          allowSuggestions: false,
          anonymousVoting: false,
          endAt: undefined
        })
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to create poll')
    } finally {
      setLoading(false)
    }
  }

  // 投票
  const handleVote = async (pollId: number, optionId: number) => {
    try {
      const result = await api.castVote(pollId, optionId)
      if (result.success) {
        // 重新加载投票详情
        if (selectedPoll) {
          const pollResult = await api.getPoll(pollId)
          if (pollResult.success && pollResult.data) {
            setSelectedPoll(pollResult.data as GroupPollType)
          }
        }
        loadPolls()
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to cast vote')
    }
  }

  // 结束投票
  const handleEndPoll = async (pollId: number) => {
    if (!confirm('确定要结束这个投票吗？')) return
    try {
      const result = await api.endPoll(pollId)
      if (result.success) {
        loadPolls()
        if (selectedPoll?.id === pollId) {
          setSelectedPoll(null)
        }
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to end poll')
    }
  }

  // 添加选项
  const addOption = () => {
    setFormData({
      ...formData,
      options: [...formData.options, '']
    })
  }

  // 移除选项
  const removeOption = (index: number) => {
    if (formData.options.length <= 2) return
    setFormData({
      ...formData,
      options: formData.options.filter((_, i) => i !== index)
    })
  }

  // 更新选项
  const updateOption = (index: number, value: string) => {
    const newOptions = [...formData.options]
    newOptions[index] = value
    setFormData({ ...formData, options: newOptions })
  }

  // 渲染投票详情
  const renderPollDetail = () => {
    if (!selectedPoll) return null

    const isPollEnded = selectedPoll.status === 'ended'
    const hasVoted = selectedPoll.results.some(result =>
      result.voters.some(v => v.userId === currentUserId)
    )

    return (
      <div className="poll-detail">
        <div className="poll-header">
          <h3>{selectedPoll.title}</h3>
          <span className={`poll-status status-${selectedPoll.status}`}>
            {selectedPoll.status === 'active' ? '进行中' :
             selectedPoll.status === 'ended' ? '已结束' : '已归档'}
          </span>
        </div>

        {selectedPoll.description && (
          <p className="poll-description">{selectedPoll.description}</p>
        )}

        <div className="poll-meta">
          <span>发起人：{selectedPoll.createdBy}</span>
          <span>
            {selectedPoll.multipleChoice && ' (多选)'}
            {selectedPoll.anonymousVoting && ' (匿名)'}
          </span>
        </div>

        <div className="poll-options">
          {selectedPoll.results.map((result) => {
            const userVotedThis = result.voters.some(v => v.userId === currentUserId)
            return (
              <div
                key={result.optionId}
                className={`poll-option ${userVotedThis ? 'voted' : ''}`}
                onClick={() => !isPollEnded && !hasVoted && handleVote(selectedPoll.id, result.optionId)}
              >
                <div className="option-content">
                  <span className="option-text">{result.text}</span>
                  {!selectedPoll.anonymousVoting && result.voters.length > 0 && (
                    <span className="option-voters">
                      {result.voters.map(v => v.username).join(', ')}
                    </span>
                  )}
                </div>
                <div className="option-result">
                  <div className="progress-bar">
                    <div
                      className="progress"
                      style={{ width: `${result.percentage}%` }}
                    />
                  </div>
                  <span className="vote-count">
                    {result.voteCount}票 ({result.percentage}%)
                  </span>
                </div>
              </div>
            )
          })}
        </div>

        <div className="poll-actions">
          {selectedPoll.status === 'active' && currentUser?.id === selectedPoll.createdBy && (
            <button onClick={() => handleEndPoll(selectedPoll.id)} className="btn-end">
              结束投票
            </button>
          )}
          <button onClick={() => setSelectedPoll(null)} className="btn-back">
            返回列表
          </button>
        </div>
      </div>
    )
  }

  // 渲染创建投票表单
  const renderCreateForm = () => (
    <form className="create-poll-form" onSubmit={handleCreatePoll}>
      <h3>创建投票</h3>

      <div className="form-group">
        <label>标题</label>
        <input
          type="text"
          value={formData.title}
          onChange={(e) => setFormData({ ...formData, title: e.target.value })}
          required
          placeholder="输入投票标题"
        />
      </div>

      <div className="form-group">
        <label>描述（可选）</label>
        <textarea
          value={formData.description}
          onChange={(e) => setFormData({ ...formData, description: e.target.value })}
          placeholder="输入投票描述"
          rows={3}
        />
      </div>

      <div className="form-group">
        <label>选项</label>
        {formData.options.map((option, index) => (
          <div key={index} className="option-input">
            <input
              type="text"
              value={option}
              onChange={(e) => updateOption(index, e.target.value)}
              placeholder={`选项 ${index + 1}`}
              required
            />
            {formData.options.length > 2 && (
              <button
                type="button"
                onClick={() => removeOption(index)}
                className="btn-remove-option"
              >
                移除
              </button>
            )}
          </div>
        ))}
        <button type="button" onClick={addOption} className="btn-add-option">
          + 添加选项
        </button>
      </div>

      <div className="form-group checkbox-group">
        <label>
          <input
            type="checkbox"
            checked={formData.multipleChoice}
            onChange={(e) => setFormData({ ...formData, multipleChoice: e.target.checked })}
          />
          多选
        </label>
        <label>
          <input
            type="checkbox"
            checked={formData.allowSuggestions}
            onChange={(e) => setFormData({ ...formData, allowSuggestions: e.target.checked })}
          />
          允许建议新选项
        </label>
        <label>
          <input
            type="checkbox"
            checked={formData.anonymousVoting}
            onChange={(e) => setFormData({ ...formData, anonymousVoting: e.target.checked })}
          />
          匿名投票
        </label>
      </div>

      <div className="form-group">
        <label>截止时间（可选）</label>
        <input
          type="datetime-local"
          value={formData.endAt || ''}
          onChange={(e) => setFormData({ ...formData, endAt: e.target.value })}
        />
      </div>

      <div className="form-actions">
        <button type="submit" className="btn-submit" disabled={loading}>
          {loading ? '创建中...' : '创建投票'}
        </button>
        <button
          type="button"
          onClick={() => setShowCreateForm(false)}
          className="btn-cancel"
        >
          取消
        </button>
      </div>
    </form>
  )

  // 渲染投票列表
  const renderPollList = () => (
    <div className="poll-list">
      <div className="poll-list-header">
        <h3>群投票</h3>
        <button onClick={() => setShowCreateForm(true)} className="btn-create">
          创建投票
        </button>
      </div>

      <div className="poll-filter">
        <button
          className={statusFilter === 'active' ? 'active' : ''}
          onClick={() => setStatusFilter('active')}
        >
          进行中
        </button>
        <button
          className={statusFilter === 'ended' ? 'active' : ''}
          onClick={() => setStatusFilter('ended')}
        >
          已结束
        </button>
        <button
          className={statusFilter === 'archived' ? 'active' : ''}
          onClick={() => setStatusFilter('archived')}
        >
          已归档
        </button>
      </div>

      {loading ? (
        <div className="loading">加载中...</div>
      ) : error ? (
        <div className="error">{error}</div>
      ) : polls.length === 0 ? (
        <div className="empty">暂无投票</div>
      ) : (
        <div className="polls">
          {polls.map((poll) => (
            <div
              key={poll.id}
              className="poll-item"
              onClick={() => setSelectedPoll(poll)}
            >
              <div className="poll-item-header">
                <h4>{poll.title}</h4>
                <span className={`poll-status status-${poll.status}`}>
                  {poll.status === 'active' ? '进行中' :
                   poll.status === 'ended' ? '已结束' : '已归档'}
                </span>
              </div>
              <div className="poll-item-meta">
                <span>发起人：{poll.createdBy}</span>
                <span>参与：{poll.options.reduce((sum, opt) => sum + opt.voteCount, 0)}票</span>
                <span>选项：{poll.options.length}</span>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  )

  return (
    <div className="group-poll-container">
      {showCreateForm ? renderCreateForm() :
       selectedPoll ? renderPollDetail() :
       renderPollList()}
    </div>
  )
}

export default GroupPoll
