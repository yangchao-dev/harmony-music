import { SongItemType } from './music'
import { songs } from './songData'

/**
 * 「我的」页数据模型与静态数据。
 * 从 Mine.ets 拆出，降低单文件复杂度，便于维护与测试。
 */

/** 用户统计数据 */
export interface UserStats {
  follows: number
  fans: number
  level: number
  hours: number
}

/** 快捷入口项 */
export interface QuickEntry {
  icon: string
  label: string
}

/** 歌单列表项 */
export interface PlaylistItem {
  id?: string              // 歌单唯一标识（用户创建的歌单才有，用于持久化）
  name: string
  count: number
  coverImg: string
  songs: SongItemType[]    // 歌单内的歌曲列表
  isLiked?: boolean
  isNew?: boolean
  isImport?: boolean
  showPin?: boolean
  playCount?: number
  isRecent?: boolean       // 是否「最近播放」入口
  isLocal?: boolean        // 是否「本地下载」入口
}

/** 歌单落盘结构（只存必要字段，读取时回查完整歌曲信息） */
export interface PersistedPlaylist {
  id: string
  name: string
  coverImg: string
  songIds: string[]
  showPin?: boolean
}

/** 内容 Tab 项 */
export interface ContentTab {
  label: string
}

/** 默认用户统计 */
export const DEFAULT_USER_STATS: UserStats = {
  follows: 1,
  fans: 1,
  level: 3,
  hours: 3
}

/** 快捷入口数据 */
export const QUICK_ENTRIES: QuickEntry[] = [
  { icon: '\ue600', label: '最近' },
  { icon: '\ue601', label: '本地' },
  { icon: '\ue602', label: 'VIP' },
  { icon: '\ue603', label: '装扮' },
  { icon: '\ue604', label: '更多' },
]

/** 内容 Tab */
export const CONTENT_TABS: ContentTab[] = [
  { label: '音乐' },
  { label: '播客' },
  { label: '笔记' },
]

/** 主歌单列表（工厂函数，返回新实例避免多组件共享可变状态） */
export function createPlaylists(): PlaylistItem[] {
  return [
    {
      name: '我喜欢的音乐',
      count: 3,
      coverImg: 'https://yjy-teach-oss.oss-cn-beijing.aliyuncs.com/HeimaCloudMusic/1.jpg',
      songs: [songs[0], songs[6], songs[14]], // 画、孤独、海阔天空
      isLiked: true
    },
    {
      name: '听歌排行',
      count: 0,
      coverImg: '',
      songs: [],
      playCount: 75,
      showPin: true
    },
    {
      name: '新建歌单',
      count: 0,
      coverImg: '',
      songs: [],
      isNew: true
    },
    {
      name: '导入外部歌单',
      count: 0,
      coverImg: '',
      songs: [],
      isImport: true
    },
  ]
}

/** 创建的歌单（工厂函数） */
export function createCreatedPlaylists(): PlaylistItem[] {
  return [
    {
      id: 'pl_created_1',
      name: '经典华语老歌',
      count: 5,
      coverImg: 'https://yjy-teach-oss.oss-cn-beijing.aliyuncs.com/HeimaCloudMusic/9.jpg',
      songs: [songs[8], songs[11], songs[12], songs[13], songs[14]] // 倩女幽魂、一生所爱、月半小夜曲、Rolling in the Deep、海阔天空
    },
    {
      id: 'pl_created_2',
      name: '睡前轻音乐',
      count: 4,
      coverImg: 'https://yjy-teach-oss.oss-cn-beijing.aliyuncs.com/HeimaCloudMusic/2.jpg',
      songs: [songs[0], songs[1], songs[6], songs[9]] // 画、Sweet Dreams、孤独、北京北京
    },
  ]
}

/** 收藏的歌单（工厂函数） */
export function createFavPlaylists(): PlaylistItem[] {
  return [
    {
      name: '欧美热门精选',
      count: 4,
      coverImg: 'https://yjy-teach-oss.oss-cn-beijing.aliyuncs.com/HeimaCloudMusic/8.jpg',
      songs: [songs[1], songs[5], songs[7], songs[13]] // Sweet Dreams、No.9、Lose Control、Rolling in the Deep
    },
    {
      name: '粤语经典',
      count: 3,
      coverImg: 'https://yjy-teach-oss.oss-cn-beijing.aliyuncs.com/HeimaCloudMusic/13.jpg',
      songs: [songs[8], songs[11], songs[12]] // 倩女幽魂、一生所爱、月半小夜曲
    },
    {
      name: '电音派对',
      count: 2,
      coverImg: 'https://yjy-teach-oss.oss-cn-beijing.aliyuncs.com/HeimaCloudMusic/6.jpg',
      songs: [songs[4], songs[5]] // 反转地球、No.9
    },
  ]
}
