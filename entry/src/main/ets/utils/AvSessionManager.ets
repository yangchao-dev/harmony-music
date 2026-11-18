import { avSession } from '@kit.AVSessionKit'
import { wantAgent } from '@kit.AbilityKit'
import { backgroundTaskManager } from '@kit.BackgroundTasksKit'
import { notificationManager } from '@kit.NotificationKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { SongItemType } from '../models/music'
import { PlaybackObserver } from '../models/PlaybackObserver'
import { PlayerState, getPlayerState } from '../models/PlayerState'
import { getAppContext } from './ContextHelper'

const DOMAIN = 0x0001

/**
 * 会话管理器：只负责 AVSession / 后台任务 / 通知。
 *
 * 通过实现 PlaybackObserver 被动接收来自 AvPlayerManager 的播放事件；
 * 不再 import AvPlayerManager（改由控制回调注入），彻底打破循环依赖。
 */
class AvSessionManager implements PlaybackObserver {

  // 创建AV会话实例
  session: avSession.AVSession | null = null
  // 通知ID
  private notificationId: number = 1001
  // 当前歌曲信息引用（统一从 PlayerState 模块获取）
  private currentSong: PlayerState = getPlayerState()
  // 会话是否已激活
  private isActivated: boolean = false
  // 是否已销毁（防止重复 destroy）
  private destroyed: boolean = false
  // 应用是否在后台
  isAppInBackground: boolean = false

  // ===== 播放控制回调（由外部注入，避免直接依赖 AvPlayerManager）=====
  private onPlayCmd: (() => void) | null = null
  private onPauseCmd: (() => void) | null = null
  private onPrevCmd: (() => void) | null = null
  private onNextCmd: (() => void) | null = null
  private onSeekCmd: ((value: number) => void) | null = null

  /** 注入播放控制命令，用于响应系统媒体控制（锁屏/灵动岛/耳机） */
  bindPlaybackControls(
    onPlay: () => void,
    onPause: () => void,
    onPrev: () => void,
    onNext: () => void,
    onSeek: (value: number) => void
  ) {
    this.onPlayCmd = onPlay
    this.onPauseCmd = onPause
    this.onPrevCmd = onPrev
    this.onNextCmd = onNext
    this.onSeekCmd = onSeek
  }

  // 初始化AV会话（仅创建，不激活）
  async init(context: Context) {
    // 幂等：已创建则直接返回，避免重复创建 session / 重复注册监听
    if (this.session) {
      return
    }
    // 支持销毁后重建：重置销毁标记
    this.destroyed = false
    try {
      this.session = await avSession.createAVSession(context, 'bgPlay', 'audio')
      this.registerEvent()
      hilog.info(DOMAIN, 'testTag', 'AVSession created successfully')
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to create AVSession: %{public}s', JSON.stringify(err))
    }
  }

  // 申请长时任务（失败不能影响播放主流程）
  async startBackgroundTask() {
    try {
      let wantAgentInfo: wantAgent.WantAgentInfo = {
        wants: [
          {
            bundleName: 'com.example.harmonycloudmusic1',
            abilityName: 'EntryAbility'
          }
        ],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      }
      const want = await wantAgent.getWantAgent(wantAgentInfo)
      const context = getAppContext()
      if (!context) {
        hilog.warn(DOMAIN, 'testTag', 'startBackgroundTask skipped: context not ready')
        return
      }
      await backgroundTaskManager.startBackgroundRunning(context, backgroundTaskManager.BackgroundMode.AUDIO_PLAYBACK, want)
    } catch (err) {
      hilog.warn(DOMAIN, 'testTag', 'startBackgroundTask skipped: %{public}s', JSON.stringify(err))
    }
  }

  // ===== PlaybackObserver 实现（被 AvPlayerManager 回调）=====

  /** 切歌：激活会话并更新媒体信息 */
  onSongChanged(song: SongItemType): void {
    this.activateAndUpdateMedia(song)
  }

  /** 播放/暂停状态变化：同步灵动岛状态 + 通知 */
  async onPlayStateChanged(isPlaying: boolean) {
    // 先确保会话已激活，否则系统媒体控制（桌面组件/锁屏）收不到状态变化，图标不会更新
    await this.ensureActivated()
    await this.setAvPlayBackState(isPlaying)
    if (isPlaying) {
      this.publishMediaNotification(this.currentSong.name, this.currentSong.author)
    } else {
      this.publishMediaNotification(this.currentSong.name, this.currentSong.author, false)
    }
  }

  /** 播放进度：同步灵动岛进度条（按真实播放状态推送，避免暂停后图标闪回播放） */
  onProgress(_time: number): void {
    this.updatePlayState(this.currentSong.isPlay)
  }

  /** 时长更新：刷新元数据 */
  onDuration(_duration: number): void {
    this.setAvMetadata(this.currentSong.playList[this.currentSong.playIndex])
  }

  // 激活会话并更新媒体信息（开始播放时调用）
  async activateAndUpdateMedia(song: SongItemType) {
    if (!this.session) {
      return
    }
    try {
      // 激活会话
      if (!this.isActivated) {
        await this.session.activate()
        this.isActivated = true
        hilog.info(DOMAIN, 'testTag', 'AVSession activated')
      }

      // 更新播放状态为播放中
      await this.session.setAVPlaybackState({
        state: avSession.PlaybackState.PLAYBACK_STATE_PLAY,
        speed: 1.0,
        position: {
          elapsedTime: 0,
          updateTime: Date.now()
        }
      })

      // 设置元数据（包含封面图，灵动岛需要）
      let metadata: avSession.AVMetadata = {
        assetId: song.id,
        title: song.name || '未知歌曲',
        artist: song.author || '未知歌手',
        mediaImage: song.img || undefined,
        duration: this.currentSong.duration
      }
      await this.session.setAVMetadata(metadata)
      hilog.info(DOMAIN, 'testTag', 'AVSession metadata set: %{public}s - %{public}s', song.name, song.author)
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to activate AVSession: %{public}s', JSON.stringify(err))
    }
  }

  // 更新播放状态（用于进度同步）
  async updatePlayState(isPlaying: boolean) {
    if (!this.session) {
      return
    }
    try {
      // speed 必须 > 0（暂停也用 1.0，避免 401）
      await this.session.setAVPlaybackState({
        state: isPlaying ? avSession.PlaybackState.PLAYBACK_STATE_PLAY :
        avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
        speed: 1.0,
        position: {
          elapsedTime: Math.max(0, this.currentSong.time),
          updateTime: Date.now()
        }
      })
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to update play state: %{public}s', JSON.stringify(err))
    }
  }

  // 停用会话
  async deactivateSession() {
    try {
      if (this.session && this.isActivated) {
        await this.session.deactivate()
        this.isActivated = false
        hilog.info(DOMAIN, 'testTag', 'AVSession deactivated')
      }
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to deactivate AVSession: %{public}s', JSON.stringify(err))
    }
  }

  // 发布媒体通知（下拉通知栏显示，仅在后台播放时调用）
  async publishMediaNotification(title: string, artist: string, isPlaying: boolean = true) {
    // 前台不显示通知
    if (!this.isAppInBackground) {
      return
    }
    try {
      // 创建点击通知跳转的WantAgent
      let wantAgentInfo: wantAgent.WantAgentInfo = {
        wants: [
          {
            bundleName: 'com.example.harmonycloudmusic1',
            abilityName: 'EntryAbility'
          }
        ],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      }
      const launchWant = await wantAgent.getWantAgent(wantAgentInfo)

      let notificationReq: notificationManager.NotificationRequest = {
        id: this.notificationId,
        notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: (isPlaying ? '正在播放  ' : '已暂停  ') + (title || '未知歌曲'),
            text: '歌手：' + (artist || '未知歌手')
          }
        },
        wantAgent: launchWant,
        isOngoing: true // 常驻通知，用户不可滑动删除
      }
      await notificationManager.publish(notificationReq)
      hilog.info(DOMAIN, 'testTag', 'Media notification published: %{public}s - %{public}s', title, artist)
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to publish notification: %{public}s', JSON.stringify(err))
    }
  }

  // 取消媒体通知
  async cancelMediaNotification() {
    try {
      await notificationManager.cancel(this.notificationId)
      hilog.info(DOMAIN, 'testTag', 'Media notification cancelled')
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to cancel notification: %{public}s', JSON.stringify(err))
    }
  }

  // 销毁：解绑监听、清理通知、停用并销毁会话（幂等，可重复调用）
  async destroy() {
    // 幂等：session 已释放则直接返回，避免重复销毁
    if (this.destroyed) {
      return
    }
    this.destroyed = true
    try {
      // 取消通知
      try {
        await notificationManager.cancel(this.notificationId)
      } catch (err) {
        hilog.warn(DOMAIN, 'testTag', 'cancel notification failed: %{public}s', JSON.stringify(err))
      }

      if (this.session) {
        // 解绑所有监听，避免会话销毁后回调残留
        this.unregisterEvent()
        // 停用会话
        if (this.isActivated) {
          try {
            await this.session.deactivate()
          } catch (err) {
            hilog.warn(DOMAIN, 'testTag', 'deactivate failed: %{public}s', JSON.stringify(err))
          }
          this.isActivated = false
        }
        // 真正销毁会话实例并释放引用
        try {
          await this.session.destroy()
        } catch (err) {
          hilog.warn(DOMAIN, 'testTag', 'session destroy failed: %{public}s', JSON.stringify(err))
        }
        this.session = null
      }
      hilog.info(DOMAIN, 'testTag', 'AvSessionManager destroyed')
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to destroy: %{public}s', JSON.stringify(err))
    }
  }

  // 解绑所有系统媒体控制监听
  private unregisterEvent() {
    if (!this.session) {
      return
    }
    try {
      this.session.off('play')
    } catch (err) {
      hilog.warn(DOMAIN, 'testTag', 'off play failed: %{public}s', JSON.stringify(err))
    }
    try {
      this.session.off('pause')
    } catch (err) {
      hilog.warn(DOMAIN, 'testTag', 'off pause failed: %{public}s', JSON.stringify(err))
    }
    try {
      this.session.off('playPrevious')
    } catch (err) {
      hilog.warn(DOMAIN, 'testTag', 'off playPrevious failed: %{public}s', JSON.stringify(err))
    }
    try {
      this.session.off('playNext')
    } catch (err) {
      hilog.warn(DOMAIN, 'testTag', 'off playNext failed: %{public}s', JSON.stringify(err))
    }
    try {
      this.session.off('seek')
    } catch (err) {
      hilog.warn(DOMAIN, 'testTag', 'off seek failed: %{public}s', JSON.stringify(err))
    }
  }

  // 设置元数据
  setAvMetadata(song: SongItemType | undefined) {
    if (!this.session || !song) {
      return
    }
    try {
      this.session.setAVMetadata({
        assetId: song.id,
        title: song.name,
        mediaImage: song.img,
        artist: song.author,
        duration: this.currentSong.duration
      })
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set AVMetadata: %{public}s', JSON.stringify(err))
    }
  }

  // 确保会话已激活（系统媒体控制只在激活后才会同步状态/图标）
  private async ensureActivated() {
    if (!this.session) {
      return
    }
    if (!this.isActivated) {
      try {
        await this.session.activate()
        this.isActivated = true
        hilog.info(DOMAIN, 'testTag', 'AVSession activated (ensure)')
      } catch (err) {
        hilog.error(DOMAIN, 'testTag', 'ensureActivated failed: %{public}s', JSON.stringify(err))
      }
    }
  }

  // 设置播放状态（确保灵动岛/桌面卡片正确显示播放/暂停按钮）
  async setAvPlayBackState(isPlaying: boolean) {
    if (!this.session) {
      hilog.warn(DOMAIN, 'testTag', 'setAvPlayBackState skipped: session is null')
      return
    }
    // 状态同步前确保会话已激活，避免状态被系统丢弃导致图标不更新
    await this.ensureActivated()
    try {
      // 注意：speed 必须 > 0，暂停态也应为 1.0（否则会报 401 参数错误），
      // 播放/暂停由 state 字段表达，不用 speed=0
      await this.session.setAVPlaybackState({
        state: isPlaying ? avSession.PlaybackState.PLAYBACK_STATE_PLAY :
          avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
        speed: 1.0,
        position: {
          elapsedTime: Math.max(0, this.currentSong.time),
          updateTime: Date.now()
        }
      })
      hilog.info(DOMAIN, 'testTag', 'setAvPlayBackState: %{public}s', isPlaying ? 'PLAY' : 'PAUSE')
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set AVPlaybackState: %{public}s', JSON.stringify(err))
    }
  }

  // 注册系统媒体控制事件
  registerEvent() {
    this.session?.on('play', () => {
      if (this.currentSong.playList.length === 0) {
        hilog.warn(DOMAIN, 'testTag', 'play event ignored: playList is empty')
        return
      }
      this.onPlayCmd?.()
    })
    this.session?.on('pause', () => {
      this.onPauseCmd?.()
    })
    this.session?.on('playPrevious', () => {
      if (this.currentSong.playList.length === 0) {
        return
      }
      this.onPrevCmd?.()
    })
    this.session?.on('playNext', () => {
      if (this.currentSong.playList.length === 0) {
        return
      }
      this.onNextCmd?.()
    })
    this.session?.on('seek', (value: number) => {
      this.onSeekCmd?.(value)
    })
  }

  // 注销会话（复用 destroy 的完整清理与幂等逻辑）
  async destroySession() {
    await this.destroy()
  }

}
export const sessionManager: AvSessionManager = new AvSessionManager()
