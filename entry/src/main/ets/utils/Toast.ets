import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN = 0x0005

/** toast 可选项（字段与 ShowToastOptions 类型对齐，避免依赖 promptAction 命名空间） */
export interface ToastOptions {
  message: string | Resource
  /** 显示时长，默认 1500ms */
  duration?: number
  /** 距离底部的偏移（vp） */
  bottom?: number
  backgroundBlurStyle?: BlurStyle
  textColor?: ResourceColor
}

/** 当前页面 UIContext（由入口组件注册，避免使用已废弃的全局 promptAction） */
let currentUIContext: UIContext | null = null

/** 页面显示时注册 UIContext */
export function bindUIContext(context: UIContext): void {
  currentUIContext = context
}

/**
 * 统一的轻提示入口。
 * 优先走 UIContext.getPromptAction()（推荐用法），context 缺失时静默降级。
 */
export function toast(options: ToastOptions | string): void {
  const opts: ToastOptions = typeof options === 'string' ? { message: options } : options
  const duration: number = opts.duration ?? 1500
  try {
    if (currentUIContext) {
      const showOptions: ToastOptions = {
        message: opts.message,
        duration: duration,
        bottom: opts.bottom,
        backgroundBlurStyle: opts.backgroundBlurStyle,
        textColor: opts.textColor
      }
      currentUIContext.getPromptAction().showToast(showOptions)
      return
    }
    hilog.warn(DOMAIN, 'testTag', 'toast skipped: UIContext not bound')
  } catch (err) {
    hilog.error(DOMAIN, 'testTag', 'toast failed: %{public}s', JSON.stringify(err))
  }
}
