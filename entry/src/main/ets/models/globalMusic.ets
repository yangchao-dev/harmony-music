import { SongItemType } from "./music" // 导入歌曲数据类型
import { LyricItem } from "./LyricItem"
import { url } from "@kit.ArkTS"

@ObservedV2
export class GlobalMusic {
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

  @Trace playMode: 'auto' | 'random' | 'repeat' = 'auto' //播放模式


  // 重置数据方法
  reset(){
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