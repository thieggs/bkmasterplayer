import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player_musica/data/settings.dart';
import 'package:player_musica/data/subsonic/subsonic_client.dart';
import 'package:player_musica/data/subsonic/subsonic_parse.dart';

void main() {
  group('SubsonicClient', () {
    test('normaliza a URL do servidor', () {
      expect(SubsonicClient.normalizeBaseUrl('musica.local:4533/'), 'http://musica.local:4533');
      expect(SubsonicClient.normalizeBaseUrl('https://x.com/rest/'), 'https://x.com');
      expect(SubsonicClient.normalizeBaseUrl(' https://x.com/navidrome '), 'https://x.com/navidrome');
    });

    test('token nunca contém a senha e usa md5(senha+salt)', () {
      final a = SubsonicAuth.fromPassword('ana', 'sesame');
      expect(a.salt, hasLength(12));
      expect(a.token, hasLength(32));
      expect(a.params.values.join(), isNot(contains('sesame')));
      final json = a.toJson();
      expect(json.values.join(), isNot(contains('sesame')));
      final back = SubsonicAuth.fromJson(json)!;
      expect(back.params, a.params);
    });

    test('token de senha com acento usa os bytes UTF-8', () {
      final a = SubsonicAuth.fromPassword('ana', 'coração');
      expect(a.token, md5.convert(utf8.encode('coração${a.salt}')).toString());
    });

    test('monta a URL de stream com autenticação', () {
      final c = SubsonicClient(
        baseUrl: 'http://h:4533',
        auth: const SubsonicAuth.token(username: 'u', token: 't', salt: 's'),
      );
      final uri = c.uri('stream', {'id': '42', 'format': 'raw', 'maxBitRate': null});
      expect(uri.path, '/rest/stream');
      expect(uri.queryParameters, containsPair('id', '42'));
      expect(uri.queryParameters, containsPair('u', 'u'));
      expect(uri.queryParameters.containsKey('maxBitRate'), isFalse);
    });
  });

  group('parser OpenSubsonic', () {
    test('música com campos OpenSubsonic', () {
      final s = parseSong({
        'id': 'KO2',
        'title': 'Névoa',
        'album': 'Ambiente',
        'albumId': 'al1',
        'artist': 'Onda Calma',
        'displayArtist': 'Onda Calma',
        'artists': [
          {'id': 'ar1', 'name': 'Onda Calma'}
        ],
        'track': 1,
        'duration': 49,
        'bpm': 0,
        'suffix': 'flac',
        'samplingRate': 44100,
        'bitDepth': 24,
        'replayGain': {'trackGain': -6.5, 'trackPeak': 0.98},
        'genres': [
          {'name': 'Ambient'}
        ],
      });
      expect(s.title, 'Névoa');
      expect(s.duration, const Duration(seconds: 49));
      expect(s.bpm, isNull, reason: 'bpm 0 significa desconhecido');
      expect(s.replayGain?.trackGain, -6.5);
      expect(s.genres, ['Ambient']);
      expect(s.artistId, 'ar1', reason: 'sem artistId, usa o primeiro de artists');
      expect(s.artists.first.id, 'ar1');
    });

    test('letras sincronizadas têm prioridade', () {
      final l = parseStructuredLyrics({
        'lyricsList': {
          'structuredLyrics': [
            {
              'synced': false,
              'line': [
                {'value': 'texto'}
              ]
            },
            {
              'synced': true,
              'offset': 100,
              'line': [
                {'start': 1000, 'value': 'um'},
                {'start': 2500, 'value': 'dois'}
              ]
            },
          ]
        }
      })!;
      expect(l.synced, isTrue);
      expect(l.offset, const Duration(milliseconds: 100));
      expect(l.lines[1].start, const Duration(milliseconds: 2500));
    });

    test('sonicMatch (extensão sonicSimilarity)', () {
      final m = parseSonicMatches({
        'sonicMatch': [
          {
            'entry': {'id': '1', 'title': 'A'},
            'similarity': 1.0
          },
          {
            'entry': {'id': '2', 'title': 'B'},
            'similarity': 0.45
          },
        ]
      });
      expect(m.map((e) => e.song.id), ['1', '2']);
      expect(m[1].similarity, 0.45);
    });

    test('extensões do servidor', () {
      final info = parseServerInfo(
        {'type': 'navidrome', 'serverVersion': '0.63.2', 'version': '1.16.1', 'openSubsonic': true},
        {
          'openSubsonicExtensions': [
            {'name': 'sonicSimilarity', 'versions': [1]},
            {'name': 'songLyrics', 'versions': [1, 2]},
          ]
        },
      );
      expect(info.sonicSimilarity, isTrue);
      expect(info.songLyrics, isTrue);
      expect(info.supports('songLyrics', 2), isTrue);
      expect(info.playbackReport, isFalse);
    });
  });

  test('configurações sobrevivem a JSON', () {
    const s = AppSettings(crossfadeSeconds: 6, replayGainMode: ReplayGainMode.album, notifications: false);
    final back = AppSettings.fromJson(s.toJson());
    expect(back.crossfadeSeconds, 6);
    expect(back.replayGainMode, ReplayGainMode.album);
    expect(back.notifications, isFalse);
  });
}
