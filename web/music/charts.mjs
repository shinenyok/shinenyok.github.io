export function shuffle(items, random = Math.random) {
  const result = [...items];
  for (let i = result.length - 1; i > 0; i--) {
    const j = Math.floor(random() * (i + 1));
    [result[i], result[j]] = [result[j], result[i]];
  }
  return result;
}

export function moveIndex(index, direction, length) {
  if (length < 1) return -1;
  return (index + direction + length) % length;
}

export function parseQQHotChart(body) {
  const songs = body?.toplist?.data?.songInfoList;
  if (!Array.isArray(songs)) return [];
  return songs.map(song => ({
    title: String(song?.name || song?.title || '').trim(),
    artist: Array.isArray(song?.singer)
      ? song.singer.map(item => item?.name).filter(Boolean).join('、')
      : String(song?.singer || ''),
    source: 'QQ 音乐热歌榜',
  })).filter(song => song.title && song.artist);
}

export function parseKugouHotChart(body) {
  const songs = body?.data?.info;
  if (!Array.isArray(songs)) return [];
  return songs.map(song => ({
    title: String(song?.songname || song?.song_name || '').trim(),
    artist: Array.isArray(song?.authors)
      ? song.authors.map(item => item?.author_name).filter(Boolean).join('、')
      : String(song?.singername || ''),
    source: '酷狗 TOP500',
  })).filter(song => song.title && song.artist);
}

export function chartPlayScore(chartTrack, searchTrack) {
  const normalize = value => String(value || '').toLowerCase().replace(/[\s\p{P}\p{S}]/gu, '');
  const title = normalize(chartTrack.title);
  const foundTitle = normalize(searchTrack.SONGNAME || searchTrack.NAME);
  const artist = normalize(chartTrack.artist);
  const foundArtist = normalize(searchTrack.ARTIST);
  if (!title || !foundTitle || !(title === foundTitle || title.includes(foundTitle) || foundTitle.includes(title))) return 0;
  return 10 + (artist && foundArtist && (artist.includes(foundArtist) || foundArtist.includes(artist)) ? 5 : 0);
}
