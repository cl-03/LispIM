/**
 * 截图防护 Hook
 * 实现 Session 风格的截图保护功能
 */

import React, { useEffect, useCallback } from 'react'

export interface ScreenshotProtectionOptions {
  enabled?: boolean
  onBlurEnabled?: boolean
  onScreenshotDetected?: () => void
}

/**
 * 截图防护 Hook
 *
 * 功能：
 * 1. 页面失去焦点时模糊内容（防止截屏）
 * 2. 检测打印对话框（常用于截图）
 * 3. 禁用 PrintScreen 键
 * 4. 检测截图工具（有限支持）
 */
export function useScreenshotProtection(options: ScreenshotProtectionOptions = {}) {
  const {
    enabled = true,
    onBlurEnabled = true,
    onScreenshotDetected
  } = options

  // 模糊屏幕
  const blurScreen = useCallback(() => {
    const overlay = document.getElementById('screenshot-protection-overlay')
    if (overlay) {
      overlay.style.display = 'flex'
    } else {
      const newOverlay = document.createElement('div')
      newOverlay.id = 'screenshot-protection-overlay'
      newOverlay.style.cssText = `
        position: fixed;
        top: 0;
        left: 0;
        width: 100vw;
        height: 100vh;
        background: rgba(0, 0, 0, 0.9);
        display: flex;
        align-items: center;
        justify-content: center;
        z-index: 999999;
        color: #fff;
        font-size: 24px;
        flex-direction: column;
        gap: 16px;
      `
      newOverlay.innerHTML = `
        <svg width="64" height="64" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <rect x="3" y="3" width="18" height="18" rx="2" ry="2"/>
          <circle cx="8.5" cy="8.5" r="1.5"/>
          <polyline points="21 15 16 10 5 21"/>
        </svg>
        <span>为保护隐私，内容已隐藏</span>
      `
      document.body.appendChild(newOverlay)
    }
  }, [])

  // 恢复屏幕
  const restoreScreen = useCallback(() => {
    const overlay = document.getElementById('screenshot-protection-overlay')
    if (overlay) {
      overlay.style.display = 'none'
    }
  }, [])

  // 处理可见性变化
  useEffect(() => {
    if (!enabled) return

    const handleVisibilityChange = () => {
      if (document.hidden) {
        blurScreen()
      } else {
        setTimeout(restoreScreen, 100)
      }
    }

    document.addEventListener('visibilitychange', handleVisibilityChange)
    return () => document.removeEventListener('visibilitychange', handleVisibilityChange)
  }, [enabled, blurScreen, restoreScreen])

  // 处理窗口失焦
  useEffect(() => {
    if (!enabled || !onBlurEnabled) return

    const handleBlur = () => {
      blurScreen()
    }

    const handleFocus = () => {
      setTimeout(restoreScreen, 100)
    }

    window.addEventListener('blur', handleBlur)
    window.addEventListener('focus', handleFocus)

    return () => {
      window.removeEventListener('blur', handleBlur)
      window.removeEventListener('focus', handleFocus)
    }
  }, [enabled, onBlurEnabled, blurScreen, restoreScreen])

  // 检测 PrintScreen 键
  useEffect(() => {
    if (!enabled) return

    const handleKeyDown = (e: KeyboardEvent) => {
      // PrintScreen 键检测
      if (
        e.key === 'PrintScreen' ||
        e.code === 'PrintScreen' ||
        (e.ctrlKey && e.key === 'p') ||
        (e.metaKey && e.shiftKey && e.key === 's')
      ) {
        e.preventDefault()
        blurScreen()
        onScreenshotDetected?.()

        // 显示警告
        alert('⚠️ 为保护隐私，截图功能已被禁用')
      }
    }

    document.addEventListener('keydown', handleKeyDown, { capture: true })
    return () => document.removeEventListener('keydown', handleKeyDown, { capture: true })
  }, [enabled, blurScreen, onScreenshotDetected])

  // 检测打印对话框（常用于截图）
  useEffect(() => {
    if (!enabled) return

    let printBlocked = false

    const handleBeforePrint = () => {
      printBlocked = true
      blurScreen()
      return false
    }

    const handleAfterPrint = () => {
      if (printBlocked) {
        setTimeout(restoreScreen, 1000)
      }
    }

    window.addEventListener('beforeprint', handleBeforePrint)
    window.addEventListener('afterprint', handleAfterPrint)

    return () => {
      window.removeEventListener('beforeprint', handleBeforePrint)
      window.removeEventListener('afterprint', handleAfterPrint)
    }
  }, [enabled, blurScreen, restoreScreen])

  // 防止右键菜单（可选）
  const preventContextMenu = useCallback((e: React.MouseEvent) => {
    if (!enabled) return
    e.preventDefault()
  }, [enabled])

  // 防止拖拽图片（防止保存图片）
  useEffect(() => {
    if (!enabled) return

    const handleDragStart = (e: DragEvent) => {
      const target = e.target as HTMLElement
      if (target.tagName === 'IMG') {
        e.preventDefault()
      }
    }

    document.addEventListener('dragstart', handleDragStart)
    return () => document.removeEventListener('dragstart', handleDragStart)
  }, [enabled])

  // 防止长按保存图片（移动端）
  useEffect(() => {
    if (!enabled) return

    const handleTouchStart = (e: TouchEvent) => {
      const target = e.target as HTMLElement
      if (target.tagName === 'IMG') {
        e.preventDefault()
      }
    }

    document.addEventListener('touchstart', handleTouchStart, { passive: false })
    return () => document.removeEventListener('touchstart', handleTouchStart)
  }, [enabled])

  return {
    blurScreen,
    restoreScreen,
    preventContextMenu
  }
}

/**
 * 截图防护组件包装器
 * @deprecated 此函数已废弃，请直接使用 useScreenshotProtection hook
 */
export function withScreenshotProtection<P extends Record<string, any>>(
  Component: React.ComponentType<P>,
  options?: ScreenshotProtectionOptions
): React.FC<P> {
  const ProtectedComponent: React.FC<P> = (props: P) => {
    useScreenshotProtection(options)
    return React.createElement(Component, props)
  }
  return ProtectedComponent
}
