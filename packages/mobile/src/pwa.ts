import { ref } from 'vue'
import { DialogPlugin } from 'tdesign-mobile-vue'
import { registerSW } from 'virtual:pwa-register'

/** Android/Chrome 可安装时显示“安装到桌面”；iOS 走 Safari 的分享菜单，无此事件。 */
export const canInstall = ref(false)

function inStandalone(): boolean {
  const nav = navigator as Navigator & { standalone?: boolean }
  return window.matchMedia('(display-mode: standalone)').matches || nav.standalone === true
}

/** 已经从桌面图标启动时不再显示安装入口。 */
export const isStandalone = ref(inStandalone())

window.matchMedia('(display-mode: standalone)').addEventListener('change', () => {
  isStandalone.value = inStandalone()
})

interface InstallPromptEvent extends Event {
  prompt: () => Promise<void>
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>
}

let deferredPrompt: InstallPromptEvent | null = null
let refreshPrompting = false

declare global {
  interface Window {
    __bashubInstallPrompt?: InstallPromptEvent | null
  }
}

function adoptInstallPrompt(event: InstallPromptEvent | null | undefined): void {
  if (!event) return
  deferredPrompt = event
  canInstall.value = true
}

// index.html 的内联脚本可能已经接住了事件，这里直接接管。
adoptInstallPrompt(window.__bashubInstallPrompt)
window.addEventListener('bashub-install-available', () => {
  adoptInstallPrompt(window.__bashubInstallPrompt)
})

export function setupPwa(): void {
  if (!('serviceWorker' in navigator)) return

  const updateSW = registerSW({
    immediate: true,
    onNeedRefresh() {
      if (refreshPrompting) return
      refreshPrompting = true
      const dialog = DialogPlugin.confirm({
        title: '发现新版本',
        content: '刷新后使用最新版本。',
        confirmBtn: '刷新',
        cancelBtn: '稍后',
        onConfirm: () => {
          dialog.destroy()
          void updateSW(true)
        },
        onCancel: () => {
          refreshPrompting = false
        },
        onClose: () => {
          refreshPrompting = false
        },
      })
    },
    onRegisteredSW(_url, registration) {
      if (!registration) return
      const check = () => {
        if (!document.hidden) void registration.update()
      }
      setInterval(check, 60 * 60 * 1000)
      document.addEventListener('visibilitychange', () => {
        if (!document.hidden) check()
      })
    },
    onRegisterError(error) {
      console.warn('PWA service worker registration failed', error)
    },
  })
}

export async function installApp(): Promise<void> {
  const prompt = deferredPrompt
  if (!prompt) return
  deferredPrompt = null
  canInstall.value = false
  window.__bashubInstallPrompt = null
  await prompt.prompt()
  await prompt.userChoice
}

window.addEventListener('beforeinstallprompt', (event) => {
  event.preventDefault()
  adoptInstallPrompt(event as InstallPromptEvent)
})

window.addEventListener('appinstalled', () => {
  deferredPrompt = null
  canInstall.value = false
  window.__bashubInstallPrompt = null
})
