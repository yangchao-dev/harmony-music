import { media } from '@kit.MediaKit'
import { GlobalMusic } from '../models/globalMusic'
import { SongItemType } from '../models/music'
import { AppStorageV2 } from '@kit.ArkUI'
import { sessionManager } from '../utils/AvSessionManager'
import { getLyricBySongName } from '../models/lyricData'

class AvPlayerManager {
  // 播放/暂停切换：按当前状态二选一
  async playOrPause() {
    if (!this.player || this.currentSong.playList.length === 0) {
      return
    }
    if (this.currentSong.isPlay) {
      await this.pause()
    } else {
      this.player.play()
      this.currentSong.isPlay = true
      // 同步 AVSession 播放状态（控制中心/胶囊按钮），后台时更新通知
      await sessionManager.setAvPlayBackState(true)
      sessionManager.publishMediaNotification(this.currentSong.name, this.currentSong.author)
    }
  }
  // 播放器
  player: media.AVPlayer | null = null
  // 共享播放数据
  currentSong: GlobalMusic = AppStorageV2.connect(GlobalMusic, 'SONG_KEY', () => new GlobalMusic())!

  async init() {
    if (!this.player) {
      this.player = await media.createAVPlayer()
    }
    this.player.on('stateChange', (state) => {
      if (state === 'initialized') {
        this.player?.prepare()
      } else if (state === 'prepared') {
        this.player?.play()
        this.currentSong.isPlay = true
      } else if (state === 'completed') {
        this.nextPlay(true)
      }else if (state === 'released'){
        this.currentSong.reset()
      }
    })

    // 歌曲总时长
    this.player.on('durationUpdate', (duration) => {
      this.currentSong.duration = duration

      //把歌曲的数据存入元数据
      sessionManager.setAvMetadata(this.currentSong.playList[this.currentSong.playIndex])

    })
    // 当前播放时间
    this.player.on('timeUpdate', (time) => {
      this.currentSong.time = time
      // 更新AVSession播放进度（灵动岛进度条同步）
      sessionManager.updatePlayState(true)

    })


  }

  // 播放歌曲
  async singPlay(song: SongItemType) {

    // 申请长时任务
    sessionManager.startBackgroundTask()

    // 是否在播放列表里，some检查数组是否满足条件，只要有一个满足就返回true
    const inList = this.currentSong.playList.some(item => item.id === song.id)

    if (inList) {
      // 在列表里，是否正在播放，是就继续播放，不是就切歌
      if (this.currentSong.url === song.url) {
        // 继续播放
        this.player?.play()
        // 更新播放状态为 播放
        this.currentSong.isPlay = true
        // 更新AVSession播放状态（灵动岛同步）和通知
        await sessionManager.setAvPlayBackState(true)
        sessionManager.publishMediaNotification(this.currentSong.name, this.currentSong.author)
      } else {
        // 切换歌曲
        this.currentSong.playIndex = this.currentSong.playList.findIndex(item => item.id === song.id)
        // 切换歌曲
        this.changeSong()
      }

    } else {
      // 不在播放列表里，添加到播放列表，切歌播放
      this.currentSong.playList.unshift(song)
      this.currentSong.playIndex = 0 // 重置播放索引为数组刚刚加进来的第一个

      // 切歌播放
      this.changeSong()

    }


  }

  // 歌曲进度跳转
  seekPlay(value: number) {
    this.player?.seek(value)
  }

  // 切换歌曲 , 使用async await
  async changeSong() {
    await this.player?.reset() // 重置播放器
    this.currentSong.time = 0
    this.currentSong.duration = 0
    this.currentSong.img = this.currentSong.playList[this.currentSong.playIndex].img
    this.currentSong.name = this.currentSong.playList[this.currentSong.playIndex].name
    this.currentSong.author = this.currentSong.playList[this.currentSong.playIndex].author
    this.currentSong.url = this.currentSong.playList[this.currentSong.playIndex].url
    // 加载歌词数据
    this.currentSong.lyrics = getLyricBySongName(this.currentSong.name)
    // 激活AVSession并更新媒体信息（通知栏显示）
    sessionManager.activateAndUpdateMedia(this.currentSong.name, this.currentSong.author)
    // 发布媒体通知
    sessionManager.publishMediaNotification(this.currentSong.name, this.currentSong.author)
    // 设置播放资源
    this.player!.url = this.currentSong.url
    sessionManager.setAvMetadata(this.currentSong.playList[this.currentSong.playIndex])

  }

  // 暂停
  async pause() {
    this.player?.pause()
    this.currentSong.isPlay = false
    // 更新AVSession播放状态为暂停（灵动岛会同步更新）
    await sessionManager.setAvPlayBackState(false)
    // 后台时更新通知显示"已暂停"
    sessionManager.publishMediaNotification(this.currentSong.name, this.currentSong.author, false)
  }

  // 上一首
  prevPlay() {
    // 随机播放
    if (this.currentSong.playMode === 'random') {
      this.currentSong.playIndex = Math.floor(Math.random() * this.currentSong.playList.length)
    } else {
      // 顺序播放
      this.currentSong.playIndex-- // 索引在数组里往上（左）移一位
      if (this.currentSong.playIndex < 0) { // 如果索引小于0
        // 当前播放的是播放列表第一首的时候点击上一曲，跳到最后一首
        this.currentSong.playIndex = this.currentSong.playList.length - 1
        // 播放索引改为播放列表最后一首歌
      }
    }
    this.singPlay(this.currentSong.playList[this.currentSong.playIndex])
  }

  // 下一首
  nextPlay(autoNextPlay: boolean) {
    // 模式1：单曲循环 且是自动播放的， 索引不变
    if (this.currentSong.playMode === 'repeat' && autoNextPlay) {

    } else if (this.currentSong.playMode === 'random') { // 模式2：随机播放，随机索引
      this.currentSong.playIndex = Math.floor(Math.random() * this.currentSong.playList.length)

    } else { // 模式3：顺序播放
      this.currentSong.playIndex++ // 索引往后挪一位
      // 如果当前播放索引大于等于播放列表的长度（播放列表最后一首）
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

    // 申请长时任务
    sessionManager.startBackgroundTask()

    // 清空当前播放列表
    this.currentSong.playList = [...songList]
    this.currentSong.playIndex = 0

    // 切歌播放第一首
    this.changeSong()
  }

  // 移除歌曲
  removeSong(index: number) {
    if (index === this.currentSong.playIndex) { // 如果是当前播放的歌曲
      if (this.currentSong.playList.length > 1) { // 如果播放列表有多首歌
        this.currentSong.playList.splice(index, 1) // splice(删除的索引，删除的个数)
        // 播放索引大于等于了播放列表的长度，跳回第一首
        if (this.currentSong.playIndex >= this.currentSong.playList.length) {
          this.currentSong.playIndex = 0
        }
        // 播放歌曲
        this.singPlay(this.currentSong.playList[this.currentSong.playIndex])


      } else {
        // 播放列表只有一首歌
        this.player?.reset()
        // 取消通知
        sessionManager.cancelMediaNotification()
        // 停用AVSession
        sessionManager.deactivateSession()
        // 重置全局歌曲数据
        this.currentSong.reset()

      }

    } else {
      // 移除的不是正在播放的歌曲
      if (index < this.currentSong.playIndex) {
        // 要移除的歌曲在播放的歌曲之前
        this.currentSong.playIndex--
      }

      // 从播放列表里移除
      this.currentSong.playList.splice(index, 1)

    }

  }

  // 释放播放器
  async release(){
    await this.player?.release()
  }

}

export const playerManager: AvPlayerManager = new AvPlayerManager()