import { systemShare } from '@kit.ShareKit'
import { uniformTypeDescriptor } from '@kit.ArkData'
import { common } from '@kit.AbilityKit'
import { pasteboard } from '@kit.BasicServicesKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { SongItemType } from '../models/music'
import { playerManager } from './AvPlayerManager'
import { getQueueStore, insertNextUp } from '../models/UserSettings'
import { getAppContext } from './ContextHelper'
import { toast } from './Toast'

const DOMAIN = 0x0004

/** 获取 UIAbilityContext（分享面板必需） */
function getAbilityContext(): common.UIAbilityContext | null {
  try {
    const ctx = getAppContext()
    return ctx && ctx.abilityInfo ? ctx : null
  } catch (err) {
    return null
  }
}

/** 分享纯文本（系统分享面板），失败时退回复制到剪贴板 */
async function shareText(title: string, text: string): Promise<void> {
  const ctx = getAbilityContext()
  if (ctx) {
    try {
      const data: systemShare.SharedData = new systemShare.SharedData({
        utd: uniformTypeDescriptor.UniformDataType.PLAIN_TEXT,
        content: text,
        title: title
      })
      const controller: systemShare.ShareController = new systemShare.ShareController(data)
      await controller.show(ctx, {
        previewMode: systemShare.SharePreviewMode.DEFAULT,
        selectionMode: systemShare.SelectionMode.SINGLE
      })
      return
    } catch (err) {
      hilog.warn(DOMAIN, 'testTag', 'system share failed: %{public}s', JSON.stringify(err))
    }
  }
  // 兜底：复制到剪贴板，保证用户至少拿到内容
  await copyText(text, '系统分享不可用，已复制内容')
}

/** 复制文本到剪贴板并提示 */
export async function copyText(text: string, tip: string = '已复制到剪贴板'): Promise<void> {
  try {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)
    await pasteboard.getSystemPasteboard().setData(data)
    toast({ message: tip, duration: 1500 })
  } catch (err) {
    hilog.error(DOMAIN, 'testTag', 'copy failed: %{public}s', JSON.stringify(err))
    toast({ message: '复制失败', duration: 1500 })
  }
}

/** 分享当前播放的歌曲 */
export async function shareSong(song: SongItemType | undefined): Promise<void> {
  if (!song || !song.name) {
    toast({ message: '暂无播放中的歌曲', duration: 1500 })
    return
  }
  const text = `我在鸿蒙云音乐听《${song.name}》- ${song.author}：${song.url}`
  await shareText(`分享歌曲《${song.name}》`, text)
}

/** 分享一段文本（动态广场 / 歌单） */
export async function sharePlainText(title: string, text: string): Promise<void> {
  await shareText(title, text)
}

/** 「下一首播放」：把歌曲插入到当前播放曲目之后并立即刷新播放队列 */
export function playNextUp(song: SongItemType): boolean {
  if (!song || !song.id) {
    return false
  }
  const state = playerManager.currentSong
  if (state.playList.length === 0) {
    // 播放队列为空：直接开始播放
    playerManager.singPlay(song)
    return true
  }
  // 记录到「下一首播放」队列（展示用），并重排播放列表
  const queueStore = getQueueStore()
  if (!queueStore.nextUpQueue.includes(song.id)) {
    queueStore.nextUpQueue = [song.id, ...queueStore.nextUpQueue]
  }
  state.playList = insertNextUp(state.playList, state.playIndex, [song])
  return true
}

/** 取走「下一首播放」队列的队首 id（播放时消费） */
export function popNextUp(): string {
  const store = getQueueStore()
  if (store.nextUpQueue.length === 0) {
    return ''
  }
  const id = store.nextUpQueue[0]
  store.nextUpQueue = store.nextUpQueue.slice(1)
  return id
}
