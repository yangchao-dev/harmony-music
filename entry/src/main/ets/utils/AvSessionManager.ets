import { avSession } from '@kit.AVSessionKit'
import { wantAgent } from '@kit.AbilityKit'
import { backgroundTaskManager } from '@kit.BackgroundTasksKit'
import { notificationManager } from '@kit.NotificationKit'
import { GlobalMusic } from '../models/globalMusic'
import { AppStorageV2 } from '@kit.ArkUI'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { SongItemType } from '../models/music'
import { playerManager } from './AvPlayerManager'

const DOMAIN = 0x0001

class AvSessionManager {

  // 创建AV会话实例
  session: avSession.AVSession | null = null
  // 通知ID
  private notificationId: number = 1001
  // 当前歌曲信息引用
  private currentSong: GlobalMusic = AppStorageV2.connect(GlobalMusic, 'SONG_KEY', () => new GlobalMusic())!
  // 会话是否已激活
  private isActivated: boolean = false
  // 应用是否在后台
  isAppInBackground: boolean = false

  // 初始化AV会话（仅创建，不激活）
  async init(context: Context) {
    try {
      this.session = await avSession.createAVSession(context, 'bgPlay', 'audio')
      this.registerEvent()
      hilog.info(DOMAIN, 'testTag', 'AVSession created successfully')
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to create AVSession: %{public}s', JSON.stringify(err))
    }
  }

  // 申请长时任务
  async startBackgroundTask() {
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
    await backgroundTaskManager.startBackgroundRunning(getContext(), backgroundTaskManager.BackgroundMode.AUDIO_PLAYBACK, want)
  }

  // 激活会话并更新媒体信息（开始播放时调用）
  async activateAndUpdateMedia(title: string, artist: string) {
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
        assetId: '0',
        title: title || '未知歌曲',
        artist: artist || '未知歌手',
        mediaImage: this.currentSong.img || undefined,
        duration: this.currentSong.duration
      }
      await this.session.setAVMetadata(metadata)
      hilog.info(DOMAIN, 'testTag', 'AVSession metadata set: %{public}s - %{public}s', title, artist)
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to activate AVSession: %{public}s', JSON.stringify(err))
    }
  }


  // 更新播放状态（用于 timeUpdate 进度同步，需要更宽松的检查）
  async updatePlayState(isPlaying: boolean) {
    if (!this.session) {
      return
    }
    try {
      await this.session.setAVPlaybackState({
        state: isPlaying ? avSession.PlaybackState.PLAYBACK_STATE_PLAY :
        avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
        speed: isPlaying ? 1.0 : 0.0,
        position: {
          elapsedTime: this.currentSong.time,
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

  // 销毁：清理通知、停用会话（应用被从后台划掉时调用）
  async destroy() {
    try {
      // 取消通知
      await notificationManager.cancel(this.notificationId)
      // 停用AVSession
      if (this.session && this.isActivated) {
        await this.session.deactivate()
        this.isActivated = false
      }
      hilog.info(DOMAIN, 'testTag', 'AvSessionManager destroyed')
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to destroy: %{public}s', JSON.stringify(err))
    }
  }
  // 设置元数据
  setAvMetadata(song:SongItemType){
    if (!this.session) {
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

  //设置播放状态（确保灵动岛正确显示播放/暂停按钮）
  async setAvPlayBackState(isPlaying: boolean) {
    if (!this.session) {
      hilog.warn(DOMAIN, 'testTag', 'setAvPlayBackState skipped: session is null')
      return
    }
    if (!this.isActivated) {
      hilog.warn(DOMAIN, 'testTag', 'setAvPlayBackState skipped: session not activated')
      return
    }
    try {
      await this.session.setAVPlaybackState({
        state: isPlaying ? avSession.PlaybackState.PLAYBACK_STATE_PLAY :
          avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
        speed: isPlaying ? 1.0 : 0.0,
        position: {
          elapsedTime: this.currentSong.time,
          updateTime: Date.now()
        }
      })
      hilog.info(DOMAIN, 'testTag', 'setAvPlayBackState: %{public}s', isPlaying ? 'PLAY' : 'PAUSE')
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set AVPlaybackState: %{public}s', JSON.stringify(err))
    }
  }

  //注册事件
  registerEvent(){
    this.session?.on('play',()=>{
      // 保护：播放列表为空时不执行
      if (this.currentSong.playList.length === 0) {
        hilog.warn(DOMAIN, 'testTag', 'play event ignored: playList is empty')
        return
      }
      const song = this.currentSong.playList[this.currentSong.playIndex]
      if (!song) {
        hilog.warn(DOMAIN, 'testTag', 'play event ignored: song is undefined')
        return
      }
      playerManager.singPlay(song)
    })
    this.session?.on('pause',()=>{
      playerManager.pause()
    })
    this.session?.on('playPrevious',()=>{
      // 保护：播放列表为空时不执行
      if (this.currentSong.playList.length === 0) {
        return
      }
      playerManager.prevPlay()
    })
    this.session?.on('playNext',()=>{
      // 保护：播放列表为空时不执行
      if (this.currentSong.playList.length === 0) {
        return
      }
      playerManager.nextPlay(false)
    })
    this.session?.on('seek',(value:number)=>{
      playerManager.seekPlay(value)
    })
  }

  // 注销会话
  async destroySession(){
    await this.session?.destroy()
  }

}
export const sessionManager: AvSessionManager = new AvSessionManager()