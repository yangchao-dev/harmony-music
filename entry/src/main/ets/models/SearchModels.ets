import { SongItemType } from './music'

/**
 * 搜索相关纯函数与评论数据。
 * 拆成独立模块，避免 Recommend / Play 两个页面各自实现一套过滤逻辑。
 */

/** 搜索历史最大保留条数 */
export const SEARCH_HISTORY_MAX: number = 10
/** 热搜词（无输入时的推荐） */
export const HOT_KEYWORDS: string[] = ['画', '海阔天空', '孤独', '邓紫棋', 'Beyond', '月半小夜曲']

/**
 * 按歌名 / 歌手关键字过滤歌曲（忽略大小写与首尾空格）
 * @param songs 待过滤的歌曲
 * @param keyword 关键字，为空时返回空数组（由调用方决定是否展示默认内容）
 */
export function filterSongs(songs: SongItemType[], keyword: string): SongItemType[] {
  const key = (keyword ?? '').trim().toLowerCase()
  if (key.length === 0) {
    return []
  }
  return songs.filter((song: SongItemType) =>
    song.name.toLowerCase().includes(key) || song.author.toLowerCase().includes(key)
  )
}

/**
 * 把关键字插入搜索历史（去重、置顶、截断 TopN）
 * @returns 新的历史数组（不修改入参）
 */
export function pushSearchHistory(history: string[], keyword: string, maxSize: number = SEARCH_HISTORY_MAX): string[] {
  const value = (keyword ?? '').trim()
  if (value.length === 0) {
    return [...history]
  }
  const rest = history.filter((item: string) => item !== value)
  return [value, ...rest].slice(0, maxSize)
}

/**
 * 关键字高亮分段：把文本按命中关键字切成 [前, 命中, 后] 三段。
 * 未命中时 hit 为空串，调用方可直接展示整段。
 */
export function splitByKeyword(text: string, keyword: string): string[] {
  const key = (keyword ?? '').trim()
  if (key.length === 0 || !text) {
    return [text ?? '', '', '']
  }
  const index = text.toLowerCase().indexOf(key.toLowerCase())
  if (index < 0) {
    return [text, '', '']
  }
  return [text.substring(0, index), text.substring(index, index + key.length), text.substring(index + key.length)]
}

/** 单条评论 */
export interface CommentItem {
  id: string
  author: string
  avatar: string
  content: string
  /** 点赞数（会随用户点赞变化） */
  like: number
  /** 相对时间文案，如 "3分钟前" */
  time: string
}

const AVATAR_BASE: string = 'https://yjy-teach-oss.oss-cn-beijing.aliyuncs.com/HeimaCloudMusic/h'

/** 依据歌曲 id 稳定生成一批评论（同一首歌每次进入内容一致，不会随机跳变） */
export function createComments(songId: string, baseCount: number): CommentItem[] {
  const contents: string[] = [
    '单曲循环第 28 遍，副歌一响眼眶就热了。',
    '耳机里这首歌陪我走完了整个高三的晚自习。',
    '以前觉得好听，现在听懂的时候已经不小了。',
    '这个前奏一出来就知道要哭了。',
    '深夜听这首歌的人，大概都有故事吧。',
    '推荐给朋友了，他说这是他今年听过最好的一首。',
    '旋律一起，夏天和晚风都回来了。',
    '不在现场也能感受到那种气氛，谢谢分享。'
  ]
  const authors: string[] = [
    '晚风吹过旧巷',
    '听歌不打烊',
    '路人甲的音乐盒',
    '凌晨三点的耳机',
    '北方的候鸟',
    '一颗柠檬炸弹',
    '海边捡贝壳的人',
    '沉默的行者'
  ]
  const times: string[] = ['刚刚', '3分钟前', '1小时前', '昨天 22:14', '前天', '3天前', '上周', '1个月前']
  // 用歌曲 id 的数字部分做种子，保证内容稳定
  const seed = Number.parseInt(songId, 10) || songId.length
  const count = Math.max(3, Math.min(contents.length, 3 + baseCount % 6))
  const list: CommentItem[] = []
  for (let i = 0; i < count; i++) {
    const idx = (seed + i) % contents.length
    list.push({
      id: `${songId}_c${i}`,
      author: authors[idx],
      avatar: `${AVATAR_BASE}${(seed + i) % 16}.jpg`,
      content: contents[idx],
      like: ((seed + i * 7) * 13) % 900 + 12,
      time: times[i % times.length]
    })
  }
  return list
}

/** 歌曲的基础点赞数（由 id 稳定推导，替代硬编码的 10w+） */
export function baseLikeCount(songId: string): number {
  const seed = Number.parseInt(songId, 10) || 1
  return 10000 + (seed * 3457) % 89999
}

/** 歌曲的基础评论数 */
export function baseCommentCount(songId: string): number {
  const seed = Number.parseInt(songId, 10) || 1
  return 1000 + (seed * 631) % 8999
}
