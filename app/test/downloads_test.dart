import 'package:flutter_test/flutter_test.dart';
import 'package:player_musica/data/offline_store.dart';
import 'package:player_musica/data/settings.dart';
import 'package:player_musica/domain/models.dart';

void main() {
  test('tamanho da música sobrevive à lista offline salva (o total de MB depende dele)', () {
    const s = Song(id: 's1', title: 'Um', size: 8912345);
    expect(Song.fromJson(s.toJson()).size, 8912345);
    expect(Song.fromJson(const Song(id: 's2', title: 'Dois').toJson()).size, isNull);
  });

  test('downloads ao mesmo tempo ficam entre 1 e 8', () {
    const d = AppSettings();
    expect(d.downloadParallel, 3);
    expect(d.copyWith(downloadParallel: 0).downloadParallel, 1);
    expect(d.copyWith(downloadParallel: 20).downloadParallel, 8);
    expect(AppSettings.fromJson({'downloadParallel': 99}).downloadParallel, 8);
    expect(AppSettings.fromJson(d.copyWith(downloadParallel: 5).toJson()).downloadParallel, 5);
  });

  test('coleção baixada guarda a qualidade; as antigas eram o original', () {
    const songs = [Song(id: 's1', title: 'Um')];
    const c = OfflineCollection(type: 'album', id: 'a', name: 'A', songs: songs, account: 'x', bitRate: 320);
    expect(OfflineCollection.fromJson(c.toJson()).bitRate, 320);
    final velha = c.toJson()..remove('bitRate');
    expect(OfflineCollection.fromJson(velha).bitRate, 0);
  });
}
