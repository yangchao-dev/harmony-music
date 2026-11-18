import { http } from '@kit.NetworkKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { SongItemType } from '../models/music'
import {
  getSettingsStore,
  SEARCH_SOURCE_ITUNES,
  SEARCH_SOURCE_NETEASE
} from '../models/UserSettings'

const DOMAIN: number = 0x0004
const TAG: string = 'SearchService'
const ITUNES_ENDPOINT: string = 'https://itunes.apple.com/search'

/** 搜索结果（带数据源标识，供 UI 区分「试听 / 完整」） */
export interface SearchResult {
  list: SongItemType[]
  /** 是否需要重试（网络错误 / 被限流） */
  error: string
  /** 实际使用的数据源：itunes / netease */
  source: string
  /** 因版权 / 会员无播放源而被过滤掉的歌曲数（仅网易云） */
  filteredCount: number
}

// ==================== iTunes 数据结构 ====================

interface ITunesTrack {
  trackId: number
  trackName?: string
  artistName?: string
  artworkUrl100?: string
  previewUrl?: string
}

interface ITunesResponse {
  resultCount: number
  results: ITunesTrack[]
}

// ==================== 网易云数据结构 ====================

interface NeteaseArtist {
  name?: string
}

interface NeteaseAlbum {
  picUrl?: string
}

interface NeteaseSong {
  id: number
  name?: string
  artists?: NeteaseArtist[]
  album?: NeteaseAlbum
}

interface NeteaseSearchResult {
  songs?: NeteaseSong[]
  songCount?: number
}

interface NeteaseSearchResponse {
  code?: number
  result?: NeteaseSearchResult
}

interface NeteaseUrlItem {
  id: number
  url?: string | null
}

interface NeteaseUrlResponse {
  code?: number
  data?: NeteaseUrlItem[]
}

/** 把 100x100 封面地址替换为 600x600 高清封面（iTunes CDN 通用约定） */
function toHighResCover(url?: string): string {
  if (!url) {
    return ''
  }
  return url.replace('100x100bb', '600x600bb')
}

/** 拼接歌手名（可能有多个歌手） */
function joinArtists(artists?: NeteaseArtist[]): string {
  if (!artists || artists.length === 0) {
    return '未知歌手'
  }
  const names: string[] = []
  for (const artist of artists) {
    if (artist && artist.name) {
      names.push(artist.name)
    }
  }
  return names.length > 0 ? names.join(' / ') : '未知歌手'
}

class SearchService {
  // 当前进行中的请求，用于发起新搜索时取消旧请求，避免竞态
  private currentRequest: http.HttpRequest | null = null
  private requestSeq: number = 0

  /** 取消当前搜索请求（切换关键词 / 离开页面时调用） */
  cancel(): void {
    this.requestSeq++
    if (this.currentRequest) {
      try {
        this.currentRequest.destroy()
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'cancel failed: %{public}s', JSON.stringify(err))
      }
      this.currentRequest = null
    }
  }

  /**
   * 统一搜索入口：读取当前数据源配置并路由。
   * @param keyword 关键词（歌名 / 歌手 / 专辑）
   * @param country 商店地区（仅 iTunes 有效，默认 cn）
   */
  async search(keyword: string, country: string = 'cn'): Promise<SearchResult> {
    const kw = keyword.trim()
    if (!kw) {
      return { list: [], error: '', source: '', filteredCount: 0 }
    }
    const source = getSettingsStore().searchSource
    if (source === SEARCH_SOURCE_NETEASE) {
      return await this.searchNetease(kw)
    }
    return await this.searchItunes(kw, country)
  }

  // ==================== iTunes：元数据 + 预览地址一次到位 ====================

  private async searchItunes(kw: string, country: string): Promise<SearchResult> {
    this.cancel()
    const seq = this.requestSeq
    const url = `${ITUNES_ENDPOINT}?term=${encodeURIComponent(kw)}&entity=song&country=${country}&limit=30`
    const raw = await this.fetchText(url, seq)
    if (raw === null) {
      return { list: [], error: this.lastError, source: SEARCH_SOURCE_ITUNES, filteredCount: 0 }
    }

    let parsed: ITunesResponse
    try {
      parsed = JSON.parse(raw) as ITunesResponse
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'itunes parse failed: %{public}s', JSON.stringify(err))
      return { list: [], error: '搜索结果解析失败', source: SEARCH_SOURCE_ITUNES, filteredCount: 0 }
    }

    const list: SongItemType[] = []
    const tracks: ITunesTrack[] = Array.isArray(parsed.results) ? parsed.results : []
    for (const track of tracks) {
      // 没有试听地址的歌曲跳过（点了也播不了）
      if (!track.previewUrl || !track.trackName) {
        continue
      }
      list.push({
        id: `itunes_${track.trackId}`,
        name: track.trackName,
        author: track.artistName && track.artistName.length > 0 ? track.artistName : '未知歌手',
        img: toHighResCover(track.artworkUrl100),
        url: track.previewUrl
      })
    }
    hilog.info(DOMAIN, TAG, 'itunes "%{public}s" got %{public}d tracks', kw, list.length)
    return { list: list, error: '', source: SEARCH_SOURCE_ITUNES, filteredCount: 0 }
  }

  // ==================== 网易云：cloudsearch 拿元数据 → 批量 /song/url 拿真实地址 ====================

  private async searchNetease(kw: string): Promise<SearchResult> {
    this.cancel()
    const seq = this.requestSeq
    const base = getSettingsStore().neteaseApiBase

    // 第一步：搜索元数据
    const searchUrl = `${base}/cloudsearch?keywords=${encodeURIComponent(kw)}&type=1&limit=30&offset=0`
    const searchRaw = await this.fetchText(searchUrl, seq)
    if (searchRaw === null) {
      return {
        list: [],
        error: this.lastError.length > 0 ? this.lastError : '网易云接口不可用，请检查 API 地址',
        source: SEARCH_SOURCE_NETEASE,
        filteredCount: 0
      }
    }

    let searchResp: NeteaseSearchResponse
    try {
      searchResp = JSON.parse(searchRaw) as NeteaseSearchResponse
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'netease search parse failed: %{public}s', JSON.stringify(err))
      return { list: [], error: '搜索结果解析失败', source: SEARCH_SOURCE_NETEASE, filteredCount: 0 }
    }
    const resultBody = searchResp.result
    let songs: NeteaseSong[] = []
    if (resultBody && Array.isArray(resultBody.songs)) {
      songs = resultBody.songs
    }
    if (songs.length === 0) {
      return { list: [], error: '', source: SEARCH_SOURCE_NETEASE, filteredCount: 0 }
    }

    // 第二步：批量换取真实播放地址（接口支持逗号分隔的多个 id）
    const ids: number[] = []
    for (const song of songs) {
      if (song && song.id) {
        ids.push(song.id)
      }
    }
    const urlMap: Map<number, string> = await this.fetchSongUrls(base, ids, seq)

    // 第三步：组装结果，过滤掉无播放源的歌曲（版权 / 会员）
    const list: SongItemType[] = []
    let filtered = 0
    for (const song of songs) {
      if (!song || !song.id || !song.name) {
        continue
      }
      const realUrl = urlMap.get(song.id)
      if (!realUrl || realUrl.length === 0) {
        filtered++
        continue
      }
      const cover = song.album && song.album.picUrl ? song.album.picUrl : ''
      list.push({
        id: `netease_${song.id}`,
        name: song.name,
        author: joinArtists(song.artists),
        img: cover,
        url: realUrl
      })
    }
    hilog.info(DOMAIN, TAG, 'netease "%{public}s" got %{public}d playable (%{public}d filtered)',
      kw, list.length, filtered)
    return {
      list: list,
      error: '',
      source: SEARCH_SOURCE_NETEASE,
      filteredCount: filtered
    }
  }

  /** 批量获取播放地址，返回 id -> url 映射（无音源的 id 不入 map） */
  private async fetchSongUrls(base: string, ids: number[], seq: number): Promise<Map<number, string>> {
    const result: Map<number, string> = new Map<number, string>()
    if (ids.length === 0) {
      return result
    }
    // 分批，每批 30 个 id，避免 URL 过长
    const batchSize = 30
    for (let start = 0; start < ids.length; start += batchSize) {
      if (seq !== this.requestSeq) {
        break
      }
      const batch = ids.slice(start, start + batchSize)
      const idParam = batch.join(',')
      const raw = await this.fetchText(`${base}/song/url?id=${idParam}`, seq)
      if (raw === null) {
        continue
      }
      try {
        const resp = JSON.parse(raw) as NeteaseUrlResponse
        const data: NeteaseUrlItem[] = Array.isArray(resp.data) ? resp.data : []
        for (const item of data) {
          if (item && item.id && item.url && item.url.length > 0) {
            result.set(item.id, item.url)
          }
        }
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'netease url parse failed: %{public}s', JSON.stringify(err))
      }
    }
    return result
  }

  // ==================== 通用 HTTP 文本请求（含竞态保护） ====================

  private lastError: string = ''

  /** 发起 GET 请求并返回文本；被取消 / 出错时返回 null 并设置 lastError */
  private async fetchText(url: string, seq: number): Promise<string | null> {
    this.lastError = ''
    const request = http.createHttp()
    this.currentRequest = request
    try {
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 10000,
        readTimeout: 10000,
        header: { 'Accept': 'application/json' }
      })
      // 旧请求已被取消，丢弃其响应
      if (seq !== this.requestSeq) {
        return null
      }
      if (response.responseCode !== 200) {
        hilog.warn(DOMAIN, TAG, 'http code: %{public}d', response.responseCode)
        this.lastError = '搜索服务暂时不可用，请稍后重试'
        return null
      }
      const raw = typeof response.result === 'string'
        ? response.result
        : JSON.stringify(response.result)
      return raw
    } catch (err) {
      if (seq !== this.requestSeq) {
        return null
      }
      const error = err as BusinessError
      hilog.error(DOMAIN, TAG, 'request failed: %{public}d %{public}s', error.code, error.message)
      this.lastError = '网络请求失败，请检查网络或 API 地址后重试'
      return null
    } finally {
      try {
        request.destroy()
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'destroy failed: %{public}s', JSON.stringify(err))
      }
      if (this.currentRequest === request) {
        this.currentRequest = null
      }
    }
  }
}

export const searchService: SearchService = new SearchService()
