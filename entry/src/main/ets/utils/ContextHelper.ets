import { common } from '@kit.AbilityKit'

/**
 * 获取当前上下文（统一收口，避免各处直接调用已废弃的全局 getContext()）。
 *
 * 优先级：
 * 1. 全局缓存的 AbilityContext（EntryAbility.onCreate 中缓存，最稳定，非组件代码可用）；
 * 2. 传入的 UIContext（组件内使用 this.getUIContext() 传入，走 getHostContext()）；
 * 3. 返回 null，由调用方降级处理。
 */

let cachedAbilityContext: common.UIAbilityContext | null = null

/** EntryAbility 启动时缓存上下文 */
export function setAppContext(context: common.UIAbilityContext): void {
  cachedAbilityContext = context
}

/** 读取缓存的 AbilityContext */
export function getAppContext(): common.UIAbilityContext | null {
  return cachedAbilityContext
}

/** 获取可用于 Preferences 的 Context */
export function resolveContext(uiContext?: UIContext | null): Context | null {
  if (cachedAbilityContext) {
    return cachedAbilityContext
  }
  try {
    if (uiContext) {
      const host = uiContext.getHostContext()
      if (host) {
        return host
      }
    }
  } catch (err) {
    // 忽略：降级到 null
  }
  return null
}
