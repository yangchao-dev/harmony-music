import { SongItemType } from './music'

/**
 * 播放器事件观察者接口（独立模块）。
 *
 * 放在 models 下，使 AvPlayerManager 与 AvSessionManager 都能单向引用它，
 * 二者之间无需互相 import，彻底避免循环依赖。
 */
export interface PlaybackObserver {
  /** 切歌：歌曲信息变化 */
  onSongChanged(song: SongItemType): void
  /** 播放/暂停状态变化（允许异步实现） */
  onPlayStateChanged(isPlaying: boolean): void | Promise<void>
  /** 播放进度更新（毫秒） */
  onProgress(time: number): void
  /** 歌曲总时长更新（毫秒） */
  onDuration(duration: number): void
}

/** 一条播放历史记录：只存 id + 时间戳，歌曲详情回查静态数据 */
export interface PlayHistoryRecord {
  id: string
  /** 播放时间戳（毫秒） */
  timestamp: number
}
