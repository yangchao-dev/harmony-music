import { describe, beforeAll, it, expect } from '@ohos/hypium';
import {
  formatDuration,
  formatCount,
  timeToRecordAngle,
  computeLyricIndex
} from '../main/ets/utils/Formatter';

export default function localUnitTest() {
  describe('formatterTest', () => {
    beforeAll(() => {
    });

    // ===== formatDuration：毫秒 → mm:ss =====
    it('formatDuration_zero', 0, () => {
      expect(formatDuration(0)).assertEqual('00:00');
    });

    it('formatDuration_negative', 0, () => {
      expect(formatDuration(-100)).assertEqual('00:00');
    });

    it('formatDuration_secondsOnly', 0, () => {
      // 35000ms = 35s
      expect(formatDuration(35000)).assertEqual('00:35');
    });

    it('formatDuration_overOneMinute', 0, () => {
      // 65000ms = 1:05
      expect(formatDuration(65000)).assertEqual('01:05');
    });

    it('formatDuration_exactlyOneMinute', 0, () => {
      // 60000ms = 1:00
      expect(formatDuration(60000)).assertEqual('01:00');
    });

    // ===== formatCount：≥1万 → x.x万 =====
    it('formatCount_small', 0, () => {
      expect(formatCount(999)).assertEqual('999');
    });

    it('formatCount_belowTenThousand', 0, () => {
      expect(formatCount(9999)).assertEqual('9999');
    });

    it('formatCount_tenThousand', 0, () => {
      expect(formatCount(10000)).assertEqual('1.0万');
    });

    it('formatCount_large', 0, () => {
      expect(formatCount(123456)).assertEqual('12.3万');
    });

    // ===== timeToRecordAngle：时间换算唱片角度 =====
    it('timeToRecordAngle_zero', 0, () => {
      expect(timeToRecordAngle(0)).assertEqual(0);
    });

    it('timeToRecordAngle_negative', 0, () => {
      expect(timeToRecordAngle(-500)).assertEqual(0);
    });

    it('timeToRecordAngle_oneSecond', 0, () => {
      // 1000ms * 30°/s = 30°
      expect(timeToRecordAngle(1000)).assertEqual(30);
    });

    it('timeToRecordAngle_customSpeed', 0, () => {
      // 2000ms, 60°/s = 120°
      expect(timeToRecordAngle(2000, 60)).assertEqual(120);
    });

    // ===== computeLyricIndex：二分查找歌词行 =====
    const times: number[] = [0, 5000, 12000, 20000, 30000];

    it('computeLyricIndex_empty', 0, () => {
      expect(computeLyricIndex([], 100)).assertEqual(-1);
    });

    it('computeLyricIndex_beforeFirst', 0, () => {
      // 时间早于首行（0ms）不命中 → -1
      expect(computeLyricIndex(times, -1)).assertEqual(-1);
    });

    it('computeLyricIndex_exactFirst', 0, () => {
      expect(computeLyricIndex(times, 0)).assertEqual(0);
    });

    it('computeLyricIndex_between', 0, () => {
      // 8000ms 落在 5000(idx1) 与 12000(idx2) 之间 → idx1
      expect(computeLyricIndex(times, 8000)).assertEqual(1);
    });

    it('computeLyricIndex_exactMatch', 0, () => {
      expect(computeLyricIndex(times, 12000)).assertEqual(2);
    });

    it('computeLyricIndex_afterLast', 0, () => {
      // 99999ms 超过最后一行 → 最后索引
      expect(computeLyricIndex(times, 99999)).assertEqual(4);
    });

    it('computeLyricIndex_lastExact', 0, () => {
      expect(computeLyricIndex(times, 30000)).assertEqual(4);
    });
  });
}
