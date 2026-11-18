import { AppStorageV2 } from '@kit.ArkUI'
import { preferences } from '@kit.ArkData'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { SongItemType } from './music'
import { PlayHistoryRecord } from './PlaybackObserver'
import { PlaylistItem, PersistedPlaylist } from './MineModels'
import { songs } from './songData'
import { getAppContext } from '../utils/ContextHelper'

/**
 * 全局用户数据（V2 响应式）—— PreferencesService 唯一写入口。
 *
 * 设计要点：
 * 1. Preferences 只负责「持久化」，内存中以本类 @Trace 字段为唯一数据源；
 * 2. 任何一处修改（播放页红心 / Mine 的我喜欢 / 歌词设置 / 歌单增删改）都会同步刷新所有订阅 UI；
 * 3. 组件通过 getLikedStore() / getHistoryStore() / getSettingsStore() 获取同一实例。
 */

const DOMAIN = 0x0003

/** AppStorageV2 全局 key（三份数据分 key 存储，避免互相干扰） */
export const LIKED_STORE_KEY: string = 'LIKED_STORE_KEY'
export const HISTORY_STORE_KEY: string = 'HISTORY_STORE_KEY'
export const SETTINGS_STORE_KEY: string = 'SETTINGS_STORE_KEY'
export const QUEUE_STORE_KEY: string = 'QUEUE_STORE_KEY'
export const PLAYLIST_STORE_KEY: string = 'PLAYLIST_STORE_KEY'

/** 默认昵称 */
export const DEFAULT_NICKNAME: string = '爱丁堡随性春卷'
/** 歌词字号范围 */
export const LYRIC_FONT_MIN: number = 12
export const LYRIC_FONT_MAX: number = 24
export const LYRIC_FONT_DEFAULT: number = 15
/** 最近播放保留条数（TopN） */
export const HISTORY_MAX_SIZE: number = 50

// ==================== 全网搜索数据源配置 ====================
/** 数据源：Apple iTunes（稳定合规，30 秒试听） */
export const SEARCH_SOURCE_ITUNES: string = 'itunes'
/** 数据源：网易云第三方接口（完整播放，需自建或公共实例，可能失效） */
export const SEARCH_SOURCE_NETEASE: string = 'netease'
/**
 * 网易云 API 默认根地址：指向本机自建的 NeteaseCloudMusicApi 服务。
 * 局域网 IP（192.168.10.41）模拟器与真机均可访问；换网络后需在 ⚙ 中更新 IP。
 * 约定兼容 Binaryify/NeteaseCloudMusicApi 的 /cloudsearch 与 /song/url 路由。
 */
export const DEFAULT_NETEASE_API: string = 'http://192.168.10.41:3000'
/** 已失效的旧公共实例地址（用于自动迁移到自建地址） */
const OBSOLETE_NETEASE_APIS: string[] = [
  'https://netease-cloud-music-api.vercel.app',
  'http://netease-cloud-music-api.vercel.app'
]

/** 歌词配色主题（与 LyricView 中的预设保持一致，索引落盘） */
export interface LyricColorTheme {
  name: string
  activeColor: string
  inactiveColor: string
}

export const LYRIC_COLOR_THEMES: LyricColorTheme[] = [
  { name: '纯白', activeColor: '#FFFFFF', inactiveColor: '#88ffffff' },
  { name: '金色', activeColor: '#FFD700', inactiveColor: '#88ffd700' },
  { name: '青色', activeColor: '#00CED1', inactiveColor: '#8800ced1' },
  { name: '粉红', activeColor: '#FF69B4', inactiveColor: '#88ff69b4' },
  { name: '橙黄', activeColor: '#FFA500', inactiveColor: '#88ffa500' },
]

// ==================== ① 收藏 / 喜欢 ====================

/** 喜欢的歌曲 ID 列表 */
@ObservedV2
export class LikedStore {
  /** 收藏的歌曲 id（顺序为收藏先后） */
  @Trace likedSongIds: string[] = []
}

export function getLikedStore(): LikedStore {
  return AppStorageV2.connect(LikedStore, LIKED_STORE_KEY, () => new LikedStore())!
}

// ==================== ② 播放历史 ====================

/** 播放历史（按时间倒序，去重） */
@ObservedV2
export class HistoryStore {
  /** 最近播放记录：records[0] 为最近一次播放 */
  @Trace records: PlayHistoryRecord[] = []
}

export function getHistoryStore(): HistoryStore {
  return AppStorageV2.connect(HistoryStore, HISTORY_STORE_KEY, () => new HistoryStore())!
}

// ==================== ③ 用户偏好 ====================

/** 用户偏好（昵称 + 歌词样式） */
@ObservedV2
export class SettingsStore {
  @Trace nickname: string = DEFAULT_NICKNAME
  /** 歌词字号 12~24 */
  @Trace lyricFontSize: number = LYRIC_FONT_DEFAULT
  /** 歌词配色主题索引 */
  @Trace lyricThemeIndex: number = 0
  /** 全网搜索数据源（见 SEARCH_SOURCE_* 常量） */
  @Trace searchSource: string = SEARCH_SOURCE_ITUNES
  /** 网易云 API 根地址（用户可自定义，兼容 NeteaseCloudMusicApi 路由） */
  @Trace neteaseApiBase: string = DEFAULT_NETEASE_API
}

export function getSettingsStore(): SettingsStore {
  return AppStorageV2.connect(SettingsStore, SETTINGS_STORE_KEY, () => new SettingsStore())!
}

/**
 * 数据规范化工具（导出以便复用与测试）
 */

/** 数值裁剪到 [min, max] 并取整 */
export function clampInt(value: number, min: number, max: number, fallback: number): number {
  if (!Number.isFinite(value)) {
    return fallback
  }
  return Math.min(max, Math.max(min, Math.floor(value)))
}

/** 播放历史去重 + 排序 + 截断 TopN（按 timestamp 倒序，同 id 只保留最新一条） */
export function dedupeHistory(records: PlayHistoryRecord[], maxSize: number = HISTORY_MAX_SIZE): PlayHistoryRecord[] {
  if (!records || records.length === 0) {
    return []
  }
  // 先按时间倒序
  const sorted = [...records].sort((a, b) => b.timestamp - a.timestamp)
  const seen: Set<string> = new Set<string>()
  const result: PlayHistoryRecord[] = []
  for (const item of sorted) {
    if (!item || !item.id || seen.has(item.id)) {
      continue
    }
    seen.add(item.id)
    result.push({ id: item.id, timestamp: item.timestamp })
    if (result.length >= maxSize) {
      break
    }
  }
  return result
}

/**
 * 规范化网易云 API 根地址：去首尾空白与结尾斜杠，确保带 https:// 前缀。
 * 返回空串表示地址非法（供 UI 判断提示）。
 */
export function normalizeApiBase(input: string): string {
  let value = (input ?? '').trim()
  if (value.length === 0) {
    return ''
  }
  // 允许用户输入不带协议的域名，自动补全 https
  if (!value.startsWith('http://') && !value.startsWith('https://')) {
    value = 'https://' + value
  }
  // 去结尾斜杠，避免拼接出 //cloudsearch
  while (value.endsWith('/')) {
    value = value.slice(0, -1)
  }
  return value
}

/** 字符串数组去重（保持首次出现顺序） */
export function uniqueStrings(list: string[]): string[] {
  if (!list || list.length === 0) {
    return []
  }
  const seen: Set<string> = new Set<string>()
  const result: string[] = []
  for (const item of list) {
    if (typeof item !== 'string' || item.length === 0 || seen.has(item)) {
      continue
    }
    seen.add(item)
    result.push(item)
  }
  return result
}

/** 全部静态歌曲的 id → 歌曲 索引（用于歌单回查详情） */
let SONG_INDEX: Map<string, SongItemType> | null = null

function getSongIndex(): Map<string, SongItemType> {
  if (!SONG_INDEX) {
    const map: Map<string, SongItemType> = new Map<string, SongItemType>()
    for (const song of songs) {
      map.set(song.id, song)
    }
    SONG_INDEX = map
  }
  return SONG_INDEX
}

/** 根据 id 查歌曲详情 */
export function findSongById(id: string): SongItemType | undefined {
  return getSongIndex().get(id)
}

/** 根据 id 列表还原歌曲列表（丢失的 id 自动跳过） */
export function findSongsByIds(ids: string[]): SongItemType[] {
  const result: SongItemType[] = []
  for (const id of ids) {
    const song = findSongById(id)
    if (song) {
      result.push(song)
    }
  }
  return result
}

/** 歌单 → 落盘结构 */
export function playlistsToPersist(playlists: PlaylistItem[]): PersistedPlaylist[] {
  return playlists.map((item: PlaylistItem) => {
    const data: PersistedPlaylist = {
      id: item.id ?? `pl_${Date.now()}_${Math.floor(Math.random() * 10000)}`,
      name: item.name,
      coverImg: item.coverImg,
      songIds: item.songs ? item.songs.map((song: SongItemType) => song.id) : []
    }
    if (item.showPin) {
      data.showPin = true
    }
    return data
  })
}

/** 落盘结构 → 歌单（回查歌曲详情） */
export function persistToPlaylists(data: PersistedPlaylist[]): PlaylistItem[] {
  return data.map((item: PersistedPlaylist) => {
    const songList = findSongsByIds(item.songIds ?? [])
    const playlist: PlaylistItem = {
      id: item.id,
      name: item.name,
      count: songList.length,
      coverImg: item.coverImg ?? '',
      songs: songList
    }
    if (item.showPin) {
      playlist.showPin = true
    }
    return playlist
  })
}

// ==================== ④ 歌单数据广播 ====================

/**
 * 歌单变更广播：任何页面（如「发现」页的「加入歌单」）修改歌单后
 * 递增 revision，「我的」页面监听该值重新拉取，保证两边一致。
 */
@ObservedV2
export class PlaylistStore {
  @Trace revision: number = 0
}

export function getPlaylistStore(): PlaylistStore {
  return AppStorageV2.connect(PlaylistStore, PLAYLIST_STORE_KEY, () => new PlaylistStore())!
}

// ==================== ⑤ 播放队列（下一首播放 / 播客收藏） ====================

/** 播放队列：手动「下一首播放」插入的歌曲 id 队列 + 收藏的播客（推荐歌单）key */
@ObservedV2
export class QueueStore {
  /** 「下一首播放」待播队列，队首最优先 */
  @Trace nextUpQueue: string[] = []
  /** 收藏的推荐歌单 / 播客（用封面 url 或标题作为 key） */
  @Trace favoritePodcasts: string[] = []
}

export function getQueueStore(): QueueStore {
  return AppStorageV2.connect(QueueStore, QUEUE_STORE_KEY, () => new QueueStore())!
}

/**
 * 播放队列工具（纯函数）：把「下一首播放」的歌曲插到队列里当前曲目之后。
 * @param playList 当前播放列表
 * @param playIndex 当前播放索引
 * @param songs 待插入歌曲
 * @returns 新的播放列表（不修改入参）
 */
export function insertNextUp(playList: SongItemType[], playIndex: number, songs: SongItemType[]): SongItemType[] {
  if (!songs || songs.length === 0) {
    return [...playList]
  }
  // 已在列表中的歌曲先移除，避免重复
  const ids: Set<string> = new Set<string>(songs.map((song: SongItemType) => song.id))
  const remain = playList.filter((song: SongItemType) => !ids.has(song.id))
  // 计算当前曲目在裁剪后的新列表里的位置
  const currentId = playList[playIndex] ? playList[playIndex].id : ''
  const currentPos = remain.findIndex((song: SongItemType) => song.id === currentId)
  const insertAt = currentPos >= 0 ? currentPos + 1 : remain.length
  const result = [...remain]
  result.splice(insertAt, 0, ...songs)
  return result
}

// ==================== PreferencesService ====================

/** 偏好配置文件里用到的 key（集中管理，避免拼写漂移） */
const KEY_LIKED_SONGS: string = 'liked_song_ids'
const KEY_PLAY_HISTORY: string = 'play_history'
const KEY_NICKNAME: string = 'nickname'
const KEY_LYRIC_FONT_SIZE: string = 'lyric_font_size'
const KEY_LYRIC_THEME: string = 'lyric_theme_index'
const KEY_PLAYLISTS: string = 'created_playlists'
const KEY_FAV_PODCASTS: string = 'fav_podcasts'
const KEY_SEARCH_HISTORY: string = 'search_history'
const KEY_SEARCH_SOURCE: string = 'search_source'
const KEY_NETEASE_API: string = 'netease_api_base'

/**
 * 本地持久化服务（@kit.ArkData → preferences）。
 *
 * 职责：把「喜欢 / 播放历史 / 用户偏好 / 歌单」四类数据读写到磁盘，
 * 并把磁盘数据同步进上面的 Store，供各页面共享。
 * 所有写操作都是「先改内存 → 再异步落盘」，UI 不会等待 IO。
 */
class PreferencesService {
  private pref: preferences.Preferences | null = null
  private initPromise: Promise<void> | null = null
  private ready: boolean = false

  /** 幂等初始化：Ability 启动、页面加载都可以安全重复调用 */
  init(context: Context | null): Promise<void> {
    if (this.ready) {
      return Promise.resolve()
    }
    if (!this.initPromise) {
      this.initPromise = this.doInit(context)
    }
    return this.initPromise
  }

  /**
   * 确保已初始化：上下文兜底从 ContextHelper 缓存里取，
   * 非组件代码（如 PreferencesService 内部方法）无需再调用全局 getContext()。
   */
  private ensureInit(): Promise<void> {
    if (this.ready) {
      return Promise.resolve()
    }
    return this.init(getAppContext())
  }

  private async doInit(context: Context | null): Promise<void> {
    if (!context) {
      // 上下文尚未就绪（罕见）：不缓存失败结果，等下次调用重试
      this.initPromise = null
      hilog.warn(DOMAIN, 'testTag', 'PreferencesService init skipped: context is null')
      return
    }
    try {
      this.pref = await preferences.getPreferences(context, { name: 'cloud_music_user' })
      await this.loadAll()
      this.ready = true
      hilog.info(DOMAIN, 'testTag', 'PreferencesService initialized')
    } catch (err) {
      // 失败时降级为纯内存模式：功能可用，只是不落盘
      hilog.error(DOMAIN, 'testTag', 'PreferencesService init failed: %{public}s', JSON.stringify(err))
      this.initPromise = null
    }
  }

  /** 是否已完成初始化（未完成时写操作只改内存） */
  isReady(): boolean {
    return this.ready
  }

  // ==================== 读取（启动时灌入内存） ====================

  private loadAll(): Promise<void> {
    if (!this.pref) {
      return Promise.resolve()
    }
    return this.loadLiked()
      .then(() => this.loadHistory())
      .then(() => this.loadSettings())
      .then(() => this.loadFavPodcasts())
  }

  private loadFavPodcasts(): Promise<void> {
    return this.getString(KEY_FAV_PODCASTS, '[]').then((raw: string) => {
      try {
        const parsed = JSON.parse(raw) as string[]
        getQueueStore().favoritePodcasts = uniqueStrings(Array.isArray(parsed) ? parsed : [])
      } catch (err) {
        hilog.error(DOMAIN, 'testTag', 'loadFavPodcasts failed: %{public}s', JSON.stringify(err))
      }
    })
  }

  private loadLiked(): Promise<void> {
    return this.getString(KEY_LIKED_SONGS, '[]').then((raw: string) => {
      try {
        const parsed = JSON.parse(raw) as string[]
        getLikedStore().likedSongIds = uniqueStrings(Array.isArray(parsed) ? parsed : [])
      } catch (err) {
        hilog.error(DOMAIN, 'testTag', 'loadLiked failed: %{public}s', JSON.stringify(err))
      }
    })
  }

  private loadHistory(): Promise<void> {
    return this.getString(KEY_PLAY_HISTORY, '[]').then((raw: string) => {
      try {
        const parsed = JSON.parse(raw) as PlayHistoryRecord[]
        getHistoryStore().records = dedupeHistory(Array.isArray(parsed) ? parsed : [])
      } catch (err) {
        hilog.error(DOMAIN, 'testTag', 'loadHistory failed: %{public}s', JSON.stringify(err))
      }
    })
  }

  private loadSettings(): Promise<void> {
    return Promise.all([
      this.getString(KEY_NICKNAME, DEFAULT_NICKNAME),
      this.getNumber(KEY_LYRIC_FONT_SIZE, LYRIC_FONT_DEFAULT),
      this.getNumber(KEY_LYRIC_THEME, 0),
      this.getString(KEY_SEARCH_SOURCE, SEARCH_SOURCE_ITUNES),
      this.getString(KEY_NETEASE_API, DEFAULT_NETEASE_API)
    ]).then((values: (string | number)[]) => {
      const nickname = values[0] as string
      const fontSize = values[1] as number
      const themeIndex = values[2] as number
      const source = values[3] as string
      const apiBase = values[4] as string
      const store = getSettingsStore()
      store.nickname = nickname && nickname.length > 0 ? nickname : DEFAULT_NICKNAME
      store.lyricFontSize = clampInt(fontSize, LYRIC_FONT_MIN, LYRIC_FONT_MAX, LYRIC_FONT_DEFAULT)
      store.lyricThemeIndex = clampInt(themeIndex, 0, LYRIC_COLOR_THEMES.length - 1, 0)
      store.searchSource = source === SEARCH_SOURCE_NETEASE ? SEARCH_SOURCE_NETEASE : SEARCH_SOURCE_ITUNES
      const normalizedApi = normalizeApiBase(apiBase)
      // 迁移：旧的失效公共实例地址自动替换为本地自建地址
      const obsolete = OBSOLETE_NETEASE_APIS.indexOf(normalizedApi) >= 0
      store.neteaseApiBase = (!obsolete && normalizedApi.length > 0) ? normalizedApi : DEFAULT_NETEASE_API
    })
  }

  // ==================== 写入（统一入口） ====================

  /** 写入并异步 flush（批量写后调用一次即可） */
  private async persist(key: string, value: string | number): Promise<void> {
    if (!this.pref) {
      return
    }
    try {
      await this.pref.put(key, value)
      await this.pref.flush()
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'persist %{public}s failed: %{public}s', key, JSON.stringify(err))
    }
  }

  // ---------- ① 收藏 / 喜欢 ----------

  isLiked(songId: string): boolean {
    if (!songId) {
      return false
    }
    return getLikedStore().likedSongIds.includes(songId)
  }

  /** 切换喜欢状态，返回切换后的状态 */
  toggleLiked(songId: string): boolean {
    if (!songId) {
      return false
    }
    const store = getLikedStore()
    const liked = store.likedSongIds.includes(songId)
    if (liked) {
      store.likedSongIds = store.likedSongIds.filter((id: string) => id !== songId)
    } else {
      // 新收藏放最前面，便于「我喜欢的」按收藏时间排序
      store.likedSongIds = [songId, ...store.likedSongIds]
    }
    this.persist(KEY_LIKED_SONGS, JSON.stringify(store.likedSongIds))
    return !liked
  }

  // ---------- ② 播放历史 ----------

  /** 记录一次播放（同一首歌只保留最新时间，整体按时间倒序 TopN） */
  recordPlay(songId: string): void {
    if (!songId) {
      return
    }
    const store = getHistoryStore()
    const record: PlayHistoryRecord = { id: songId, timestamp: Date.now() }
    store.records = dedupeHistory([record, ...store.records])
    this.persist(KEY_PLAY_HISTORY, JSON.stringify(store.records))
  }

  /** 清空播放历史 */
  clearHistory(): void {
    getHistoryStore().records = []
    this.persist(KEY_PLAY_HISTORY, '[]')
  }

  // ---------- ③ 用户偏好 ----------

  setNickname(nickname: string): void {
    const value = nickname.trim()
    if (value.length === 0) {
      return
    }
    getSettingsStore().nickname = value
    this.persist(KEY_NICKNAME, value)
  }

  setLyricFontSize(size: number): void {
    const value = clampInt(size, LYRIC_FONT_MIN, LYRIC_FONT_MAX, LYRIC_FONT_DEFAULT)
    getSettingsStore().lyricFontSize = value
    this.persist(KEY_LYRIC_FONT_SIZE, value)
  }

  setLyricThemeIndex(index: number): void {
    const value = clampInt(index, 0, LYRIC_COLOR_THEMES.length - 1, 0)
    getSettingsStore().lyricThemeIndex = value
    this.persist(KEY_LYRIC_THEME, value)
  }

  /** 切换全网搜索数据源（itunes / netease） */
  setSearchSource(source: string): void {
    const value = source === SEARCH_SOURCE_NETEASE ? SEARCH_SOURCE_NETEASE : SEARCH_SOURCE_ITUNES
    getSettingsStore().searchSource = value
    this.persist(KEY_SEARCH_SOURCE, value)
  }

  /**
   * 设置网易云 API 根地址。返回 true 表示保存成功，false 表示地址非法（未改动）。
   */
  setNeteaseApiBase(input: string): boolean {
    const value = normalizeApiBase(input)
    if (value.length === 0) {
      return false
    }
    getSettingsStore().neteaseApiBase = value
    this.persist(KEY_NETEASE_API, value)
    return true
  }

  /** 歌词字号 +1（越界自动忽略），返回当前字号 */
  increaseLyricFontSize(): number {
    const next = getSettingsStore().lyricFontSize + 1
    if (next <= LYRIC_FONT_MAX) {
      this.setLyricFontSize(next)
    }
    return getSettingsStore().lyricFontSize
  }

  /** 歌词字号 -1（越界自动忽略），返回当前字号 */
  decreaseLyricFontSize(): number {
    const next = getSettingsStore().lyricFontSize - 1
    if (next >= LYRIC_FONT_MIN) {
      this.setLyricFontSize(next)
    }
    return getSettingsStore().lyricFontSize
  }

  // ---------- ④ 歌单数据 ----------

  /**
   * 读取已创建的歌单。
   * @param fallback 磁盘无数据时使用的默认歌单（首次启动）
   * @returns 已恢复歌曲详情的歌单列表
   */
  loadPlaylists(fallback: PlaylistItem[]): Promise<PlaylistItem[]> {
    // 磁盘就绪后由 init 的 Promise 保证读写有序，避免首次启动读到空值后又被覆盖
    return this.ensureInit().then(() => {
      return this.getString(KEY_PLAYLISTS, '')
    }).then((text: string) => {
      if (text.length === 0) {
        // 首次启动：把默认歌单落盘，后续增删改才有基线
        this.persistPlaylists(fallback)
        return fallback
      }
      try {
        const persisted = JSON.parse(text) as PersistedPlaylist[]
        if (!Array.isArray(persisted)) {
          return fallback
        }
        return persistToPlaylists(persisted)
      } catch (err) {
        hilog.error(DOMAIN, 'testTag', 'loadPlaylists parse failed: %{public}s', JSON.stringify(err))
        return fallback
      }
    })
  }

  /**
   * 读取字符串类型的值。
   * 这里显式 package 成 Promise（而非直接 await pref.get），
   * 避免 ArkTS 对 Preferences.get 重载推断为非 Promise 而告警。
   */
  private getString(key: string, defValue: string): Promise<string> {
    const pref = this.pref
    if (!pref) {
      return Promise.resolve(defValue)
    }
    return new Promise<string>((resolve: (value: string) => void) => {
      pref.get(key, defValue).then((value: preferences.ValueType) => {
        resolve(typeof value === 'string' ? value : defValue)
      }).catch((err: Error) => {
        hilog.error(DOMAIN, 'testTag', 'getString %{public}s failed: %{public}s', key, JSON.stringify(err))
        resolve(defValue)
      })
    })
  }

  /** 读取数值类型的值（非数值时回退默认值） */
  private getNumber(key: string, defValue: number): Promise<number> {
    const pref = this.pref
    if (!pref) {
      return Promise.resolve(defValue)
    }
    return new Promise<number>((resolve: (value: number) => void) => {
      pref.get(key, defValue).then((value: preferences.ValueType) => {
        resolve(typeof value === 'number' ? value : defValue)
      }).catch((err: Error) => {
        hilog.error(DOMAIN, 'testTag', 'getNumber %{public}s failed: %{public}s', key, JSON.stringify(err))
        resolve(defValue)
      })
    })
  }

  /** 保存歌单列表（增 / 删 / 改 / 排序后统一调用） */
  persistPlaylists(playlists: PlaylistItem[]): void {
    const data: PersistedPlaylist[] = playlistsToPersist(playlists)
    this.persist(KEY_PLAYLISTS, JSON.stringify(data))
  }

  /** 读取用户创建的歌单名称列表（「加入歌单」选择用） */
  getPlaylistNames(): Promise<string[]> {
    return this.loadPlaylists([]).then((list: PlaylistItem[]) => {
      return list.map((item: PlaylistItem) => item.name)
    })
  }

  /**
   * 把歌曲加入指定名称的歌单（不存在则忽略），结果落盘。
   * @returns 是否添加成功（已存在则视为成功，不重复添加）
   */
  addSongToPlaylist(song: SongItemType, playlistName: string): Promise<boolean> {
    return this.loadPlaylists([]).then((list: PlaylistItem[]) => {
      const target = list.find((item: PlaylistItem) => item.name === playlistName)
      if (!target) {
        return false
      }
      if (target.songs.some((item: SongItemType) => item.id === song.id)) {
        return true
      }
      target.songs = [...target.songs, song]
      target.count = target.songs.length
      this.persistPlaylists(list)
      // 同步内存中的「我的」页面数据结构：通过 Store 广播刷新
      getPlaylistStore().revision++
      return true
    })
  }

  // ---------- ⑤ 搜索历史 ----------

  /** 读取搜索历史（未初始化时返回空数组） */
  getSearchHistory(): Promise<string[]> {
    if (!this.pref) {
      return Promise.resolve<string[]>([])
    }
    return this.getString(KEY_SEARCH_HISTORY, '[]').then((raw: string) => {
      try {
        const parsed = JSON.parse(raw) as string[]
        return uniqueStrings(Array.isArray(parsed) ? parsed : [])
      } catch (err) {
        hilog.error(DOMAIN, 'testTag', 'getSearchHistory failed: %{public}s', JSON.stringify(err))
        return []
      }
    })
  }

  /** 保存搜索历史 */
  saveSearchHistory(history: string[]): void {
    this.persist(KEY_SEARCH_HISTORY, JSON.stringify(uniqueStrings(history)))
  }

  // ---------- ⑥ 收藏的播客 / 推荐歌单 ----------

  isPodcastFav(key: string): boolean {
    if (!key) {
      return false
    }
    return getQueueStore().favoritePodcasts.includes(key)
  }

  /** 切换播客收藏，返回切换后的状态 */
  togglePodcastFav(key: string): boolean {
    if (!key) {
      return false
    }
    const store = getQueueStore()
    const fav = store.favoritePodcasts.includes(key)
    if (fav) {
      store.favoritePodcasts = store.favoritePodcasts.filter((item: string) => item !== key)
    } else {
      store.favoritePodcasts = [key, ...store.favoritePodcasts]
    }
    this.persist(KEY_FAV_PODCASTS, JSON.stringify(store.favoritePodcasts))
    return !fav
  }
}

export const preferencesService: PreferencesService = new PreferencesService()
