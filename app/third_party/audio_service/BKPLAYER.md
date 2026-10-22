# audio_service 0.18.19 (cópia com correção)

Cópia do pacote [audio_service](https://pub.dev/packages/audio_service) 0.18.19
(MIT, ver LICENSE), sem `example/` e `test/`, usada pelo `dependency_overrides`
do `app/pubspec.yaml`.

Duas mudanças, as duas em `AudioService.java` (Android):

1. `AudioService.onStartCommand`. Com o serviço fora do
primeiro plano (pausado, `androidStopForegroundOnPause: true`), um botão de mídia
que chega pelo `MediaButtonReceiver` inicia o serviço com
`startForegroundService()`, e o Android exige `startForeground()` em seguida
mesmo que o botão não faça tocar (anterior, parar, pausar de novo). Sem isso o
app levava ANR ou era derrubado (`ForegroundServiceDidNotStartInTimeException`).
A correção entra e sai do primeiro plano na hora nesse caso.

2. `AudioService.setMetadata` carrega a capa **fora** da trava (`synchronized`).
Na versão original o método inteiro era `synchronized` e abria a capa lá
dentro (por `content://`, o que no nosso provedor pode baixar da rede); a thread
principal pega a mesma trava para montar a notificação e ficava parada
esperando. Com a rede lenta: ANR "Input dispatching timed out" (3 vezes no M35
entre 19 e 20/10/2026, rastro em `dumpsys dropbox --print data_app_anr`). Um
número de sequência descarta a capa lenta que chegue depois da música seguinte.

Ao atualizar o audio_service: copiar a versão nova e reaplicar os trechos marcados
com "BKplayer:" em `android/src/main/java/com/ryanheise/audioservice/AudioService.java`.
