import test from 'node:test';
import assert from 'node:assert/strict';
import { shuffle, moveIndex, parseQQHotChart, parseKugouHotChart, chartPlayScore } from '../../../web/music/charts.mjs';

test('QQ hot chart response normalizes songs and artists', () => {
  assert.deepEqual(parseQQHotChart({ toplist: { data: { songInfoList: [
    { name: '歌名', singer: [{ name: '甲' }, { name: '乙' }] },
    { name: '', singer: [{ name: '无标题' }] },
  ] } } }), [{ title: '歌名', artist: '甲、乙', source: 'QQ 音乐热歌榜' }]);
});

test('Kugou chart response normalizes tracks for fallback playback', () => {
  assert.deepEqual(parseKugouHotChart({ data: { info: [
    { songname: '热歌', authors: [{ author_name: '歌手' }] },
  ] } }), [{ title: '热歌', artist: '歌手', source: '酷狗 TOP500' }]);
});

test('shuffle copies and permutes; queue navigation wraps in both directions', () => {
  const original = [1, 2, 3, 4];
  assert.deepEqual(shuffle(original, () => 0), [2, 3, 4, 1]);
  assert.deepEqual(original, [1, 2, 3, 4]);
  assert.equal(moveIndex(0, -1, 4), 3);
  assert.equal(moveIndex(3, 1, 4), 0);
  assert.equal(moveIndex(0, 1, 0), -1);
});

test('chart playback matching scores title agreement and artist agreement', () => {
  assert.equal(chartPlayScore({ title: 'A Song', artist: 'A Singer' }, { SONGNAME: 'A Song', ARTIST: 'A Singer' }), 15);
  assert.equal(chartPlayScore({ title: 'A Song', artist: 'A Singer' }, { SONGNAME: 'A Song', ARTIST: 'Other' }), 10);
  assert.equal(chartPlayScore({ title: 'A Song', artist: 'A Singer' }, { SONGNAME: 'Other', ARTIST: 'A Singer' }), 0);
});
