import { media } from '@kit.MediaKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { SongItemType } from '../models/music'
import { getLyricBySongName } from '../models/lyricData'
import { toast } from './Toast'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { PlayerState, getPlayerState } from '../models/PlayerState'
import { PlaybackObserver } from '../models/PlaybackObserver'
import { preferencesService } from '../models/UserSettings'

const DOMAIN = 0x0002

class AvPlayerManager {
  // 播放器
  player: media.AVPlayer | null = null
  // 共享播放数据（统一从 PlayerState 模块获取）
  currentSong: PlayerState = getPlayerState()

  private isInitialized: boolean = false
  private initPromise: Promise<void> | null = null
  // 事件观察者（如 AvSessionManager），可为空
  private observer: PlaybackObserver | null = null

  /** 注册播放事件观察者 */
  setObserver(observer: PlaybackObserver) {
    this.observer = observer
  }

  // 确保播放器已创建并注册监听（幂等，避免竞态导致 player 为 null）
  async init(): Promise<void> {
    if (this.isInitialized && this.player) {
      return
    }
    if (!this.initPromise) {
      this.initPromise = this.createPlayer()
    }
    return this.initPromise
  }

  private async createPlayer(): Promise<void> {
    try {
      if (!this.player) {
        this.player = await media.createAVPlayer()
      }
      const player = this.player
      const state = this.currentSong

      player.on('stateChange', (s) => {
        hilog.info(DOMAIN, 'testTag', 'AVPlayer state: %{public}s', s)
        switch (s) {
          case 'initialized':
            player.prepare().catch((err: BusinessError) => {
              hilog.error(DOMAIN, 'testTag', 'prepare failed: %{public}s', JSON.stringify(err))
            })
            break
          case 'prepared':
            player.play().catch((err: BusinessError) => {
              hilog.error(DOMAIN, 'testTag', 'play failed: %{public}s', JSON.stringify(err))
              state.isPlay = false
              this.observer?.onPlayStateChanged(false)
            })
            break
          case 'playing':
            // 以播放器实际状态为准同步，保证桌面卡片/灵动岛图标与真实状态一致
            if (!state.isPlay) {
              state.isPlay = true
              this.observer?.onPlayStateChanged(true)
            }
            break
          case 'paused':
            if (state.isPlay) {
              state.isPlay = false
              this.observer?.onPlayStateChanged(false)
            }
            break
          case 'completed':
            this.nextPlay(true)
            break
          case 'released':
            state.isPlay = false
            break
          case 'error':
            state.isPlay = false
            break
          default:
            break
        }
      })

      // 歌曲总时长
      player.on('durationUpdate', (duration) => {
        state.duration = duration
        this.observer?.onDuration(duration)
      })

      // 当前播放时间（进度条依赖此回调）
      player.on('timeUpdate', (time) => {
        state.time = time
        this.observer?.onProgress(time)
      })

      // 播放出错：复位状态并给出可见反馈，避免"点了没反应"
      player.on('error', (err: BusinessError) => {
        hilog.error(DOMAIN, 'testTag', 'AVPlayer error: %{public}s', JSON.stringify(err))
        state.isPlay = false
        // 同步暂停状态到系统媒体控制，避免图标停留在"播放中"
        this.observer?.onPlayStateChanged(false)
        toast({ message: '播放失败，请检查网络或歌曲地址', duration: 2000 })
      })

      this.isInitialized = true
      hilog.info(DOMAIN, 'testTag', 'AVPlayer initialized')
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'createAVPlayer failed: %{public}s', JSON.stringify(err))
      this.initPromise = null
    }
  }

  // 后台/系统媒体控制的"播放"命令：健壮地从暂停状态恢复
  async resumeOrPlay() {
    if (this.currentSong.playList.length === 0) {
      return
    }
    // 已暂停且有资源：尝试直接续播
    if (this.player && this.currentSong.url) {
      try {
        await this.player.play()
        hilog.info(DOMAIN, 'testTag', 'resumeOrPlay: resumed')
        return
      } catch (err) {
        hilog.warn(DOMAIN, 'testTag', 'resumeOrPlay: direct play failed, reload: %{public}s', JSON.stringify(err))
      }
    }
    // 兜底：重新加载当前歌曲
    await this.changeSong()
  }

  // 播放/暂停切换：按当前状态二选一
  async playOrPause() {
    if (this.currentSong.playList.length === 0) {
      return
    }
    if (this.currentSong.isPlay) {
      await this.pause()
    } else if (this.currentSong.url && this.player) {
      // 已有资源且处于暂停态，直接续播
      try {
        await this.player.play()
      } catch (err) {
        hilog.warn(DOMAIN, 'testTag', 'resume failed, reload song: %{public}s', JSON.stringify(err))
        await this.changeSong()
      }
    } else {
      await this.singPlay(this.currentSong.playList[this.currentSong.playIndex])
    }
  }

  // 播放歌曲
  async singPlay(song: SongItemType) {
    const inList = this.currentSong.playList.some(item => item.id === song.id)

    if (inList) {
      if (this.currentSong.url === song.url && this.player) {
        // 同一首歌，继续播放（状态同步由 stateChange('playing') 回调处理）
        try {
          await this.player.play()
          return
        } catch (err) {
          hilog.warn(DOMAIN, 'testTag', 'replay failed, reload song: %{public}s', JSON.stringify(err))
        }
      }
      const index = this.currentSong.playList.findIndex(item => item.id === song.id)
      this.currentSong.playIndex = index >= 0 ? index : 0
      await this.changeSong()
    } else {
      // 不在播放列表里，添加到列表开头并播放
      this.currentSong.playList.unshift(song)
      this.currentSong.playIndex = 0
      await this.changeSong()
    }
  }

  // 歌曲进度跳转
  seekPlay(value: number) {
    try {
      this.player?.seek(value)
    } catch (err) {
      hilog.warn(DOMAIN, 'testTag', 'seek failed: %{public}s', JSON.stringify(err))
    }
  }

  // 切换歌曲：重置播放器 → 更新状态 → 加载资源（stateChange 回调会自动 prepare/play）
  async changeSong() {
    await this.init()
    if (!this.player || this.currentSong.playList.length === 0) {
      hilog.warn(DOMAIN, 'testTag', 'changeSong aborted: player not ready or empty list')
      return
    }

    const song = this.currentSong.playList[this.currentSong.playIndex]
    if (!song) {
      hilog.warn(DOMAIN, 'testTag', 'changeSong aborted: song undefined')
      return
    }

    try {
      await this.player.reset()
    } catch (err) {
      hilog.warn(DOMAIN, 'testTag', 'reset failed: %{public}s', JSON.stringify(err))
    }

    this.currentSong.time = 0
    this.currentSong.duration = 0
    this.currentSong.img = song.img
    this.currentSong.name = song.name
    this.currentSong.author = song.author
    this.currentSong.url = song.url
    this.currentSong.lyrics = getLyricBySongName(song.name)
    this.currentSong.isPlay = false

    // 记录播放历史（去重 + 按时间倒序 TopN），由 PreferencesService 负责落盘
    preferencesService.recordPlay(song.id)

    // 通知观察者：切歌
    this.observer?.onSongChanged(song)

    try {
      // 设置播放资源后，stateChange('initialized') 会自动 prepare → play
      this.player.url = song.url
      hilog.info(DOMAIN, 'testTag', 'loading song: %{public}s', song.url)
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'set url failed: %{public}s', JSON.stringify(err))
      this.currentSong.isPlay = false
    }
  }

  // 暂停
  async pause() {
    try {
      await this.player?.pause()
    } catch (err) {
      hilog.warn(DOMAIN, 'testTag', 'pause failed: %{public}s', JSON.stringify(err))
    }
    // 状态同步由 stateChange('paused') 回调统一处理；此处兜底确保 UI 立即响应
    if (this.currentSong.isPlay) {
      this.currentSong.isPlay = false
      this.observer?.onPlayStateChanged(false)
    }
  }

  // 上一首
  prevPlay() {
    if (this.currentSong.playList.length === 0) {
      return
    }
    if (this.currentSong.playMode === 'random') {
      this.currentSong.playIndex = Math.floor(Math.random() * this.currentSong.playList.length)
    } else {
      this.currentSong.playIndex--
      if (this.currentSong.playIndex < 0) {
        this.currentSong.playIndex = this.currentSong.playList.length - 1
      }
    }
    this.singPlay(this.currentSong.playList[this.currentSong.playIndex])
  }

  // 下一首
  nextPlay(autoNextPlay: boolean) {
    if (this.currentSong.playList.length === 0) {
      return
    }
    if (this.currentSong.playMode === 'repeat' && autoNextPlay) {
      // 单曲循环：索引不变，重新播放
    } else if (this.currentSong.playMode === 'random') {
      this.currentSong.playIndex = Math.floor(Math.random() * this.currentSong.playList.length)
    } else {
      this.currentSong.playIndex++
      if (this.currentSong.playIndex >= this.currentSong.playList.length) {
        this.currentSong.playIndex = 0
      }
    }
    this.singPlay(this.currentSong.playList[this.currentSong.playIndex])
  }

  // 播放全部：将歌单所有歌曲加入播放列表并播放第一首
  async playAllSongs(songList: SongItemType[]) {
    if (songList.length === 0) {
      return
    }
    this.currentSong.playList = [...songList]
    this.currentSong.playIndex = 0
    await this.changeSong()
  }

  // 移除歌曲
  removeSong(index: number) {
    if (index < 0 || index >= this.currentSong.playList.length) {
      return
    }
    if (index === this.currentSong.playIndex) {
      if (this.currentSong.playList.length > 1) {
        this.currentSong.playList.splice(index, 1)
        if (this.currentSong.playIndex >= this.currentSong.playList.length) {
          this.currentSong.playIndex = 0
        }
        this.singPlay(this.currentSong.playList[this.currentSong.playIndex])
      } else {
        try {
          this.player?.reset()
        } catch (err) {
          hilog.warn(DOMAIN, 'testTag', 'reset failed: %{public}s', JSON.stringify(err))
        }
        this.observer?.onPlayStateChanged(false)
        this.currentSong.reset()
      }
    } else {
      if (index < this.currentSong.playIndex) {
        this.currentSong.playIndex--
      }
      this.currentSong.playList.splice(index, 1)
    }
  }

  // 释放播放器
  async release() {
    try {
      await this.player?.release()
    } catch (err) {
      hilog.warn(DOMAIN, 'testTag', 'release failed: %{public}s', JSON.stringify(err))
    }
    this.player = null
    this.isInitialized = false
    this.initPromise = null
  }

}

export const playerManager: AvPlayerManager = new AvPlayerManager()
