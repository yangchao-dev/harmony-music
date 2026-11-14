export interface SongItemType {
  img: string
  name: string
  author: string
  url: string
  id:string
}

// 动态广场接口
export interface MomentListType {
  author: string
  avatar: string
  content: string
  comment: number
  like: number
  song: SongItemType
}