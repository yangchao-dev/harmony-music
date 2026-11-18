import { SongItemType } from "./music" // 导入歌曲数据类型
import { LyricItem } from "./LyricItem"
import { AppStorageV2 } from "@kit.ArkUI"

/**
 * 全局播放状态（V2 响应式）
 *
 * 独立成模块，作为「播放器」与「会话管理器」之间唯一的状态通信桥梁，
 * 避免 AvPlayerManager ↔ AvSessionManager 直接互相 import 形成循环依赖。
 */
@ObservedV2
export class PlayerState {
  @Trace img: string = "" // 音乐封面
  @Trace name: string = "" // 音乐名称
  @Trace author: string = "" // 作者
  @Trace url: string = "" // 当前播放链接
  @Trace time: number = 0 // 播放时间
  @Trace duration: number = 0 // 音乐的播放时长

  @Trace playIndex: number = 0 // 当前播放的索引
  @Trace playList: SongItemType[] = [] // 播放列表

  @Trace isPlay: boolean = false // 播放状态

  @Trace lyrics: LyricItem[] = [] // 当前歌曲歌词数据

  @Trace playMode: 'auto' | 'random' | 'repeat' = 'auto' // 播放模式

  // 重置数据方法
  reset() {
    this.img = ''
    this.name = ''
    this.author = ''
    this.url = ''
    this.time = 0
    this.duration = 0
    this.playIndex = 0
    this.playList = []
    this.isPlay = false
    this.lyrics = []
    this.playMode = 'auto'
  }
}

/** 全局共享状态 key，全局统一使用该常量 */
export const PLAYER_STATE_KEY: string = 'SONG_KEY'

/**
 * 获取全局共享的播放入口（统一封装 AppStorageV2.connect）。
 * 非组件类、模块级单例、定时器闭包内都应通过此函数获取，确保拿到同一实例。
 */
export function getPlayerState(): PlayerState {
  return AppStorageV2.connect(PlayerState, PLAYER_STATE_KEY, () => new PlayerState())!
}
