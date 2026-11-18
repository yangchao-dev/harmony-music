/**
 * 通用格式化工具（纯函数，无副作用，便于单元测试）。
 */

/**
 * 播放时长格式化：毫秒 → "mm:ss"
 * @param number 毫秒数
 */
export function formatDuration(number: number): string {
  if (number <= 0) {
    return '00:00'
  }
  const s = Math.floor(number / 1000 % 60)
  const m = Math.floor(number / 1000 / 60)
  const second = s.toString().padStart(2, '0')
  const minute = m.toString().padStart(2, '0')
  return minute + ':' + second
}

/**
 * 大数字格式化：≥1万 → "x.x万"，否则原样
 * @param count 数量
 */
export function formatCount(count: number): string {
  if (count >= 10000) {
    return (count / 10000).toFixed(1) + '万'
  }
  return count.toString()
}

/**
 * 播放进度换算唱片旋转角度（度）。
 * 唱片角速度按每秒 30° 线性增长，不取模以避免 359°→0° 反向跳动。
 * @param timeMs 播放时间（毫秒）
 * @param degreePerSecond 每秒旋转角度，默认 30
 */
export function timeToRecordAngle(timeMs: number, degreePerSecond: number = 30): number {
  if (timeMs <= 0) {
    return 0
  }
  return timeMs / 1000 * degreePerSecond
}

/**
 * 计算当前歌词行索引（二分查找最后一个 time <= currentTime 的索引）。
 * @param times 升序排列的歌词时间戳数组
 * @param currentTime 当前播放时间（毫秒）
 * @returns 命中的索引，未命中返回 -1
 */
export function computeLyricIndex(times: number[], currentTime: number): number {
  if (!times || times.length === 0) {
    return -1
  }
  let lo = 0
  let hi = times.length - 1
  let result = -1
  while (lo <= hi) {
    const mid = (lo + hi) >>> 1
    if (times[mid] <= currentTime) {
      result = mid
      lo = mid + 1
    } else {
      hi = mid - 1
    }
  }
  return result
}
