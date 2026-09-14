# audio_service 0.18.19 (cópia com correção)

Cópia do pacote [audio_service](https://pub.dev/packages/audio_service) 0.18.19
(MIT, ver LICENSE), sem `example/` e `test/`, usada pelo `dependency_overrides`
do `app/pubspec.yaml`.

Única mudança: `AudioService.onStartCommand` (Android). Com o serviço fora do
primeiro plano (pausado, `androidStopForegroundOnPause: true`), um botão de mídia
que chega pelo `MediaButtonReceiver` inicia o serviço com
`startForegroundService()`, e o Android exige `startForeground()` em seguida
mesmo que o botão não faça tocar (anterior, parar, pausar de novo). Sem isso o
app levava ANR ou era derrubado (`ForegroundServiceDidNotStartInTimeException`).
A correção entra e sai do primeiro plano na hora nesse caso.

Ao atualizar o audio_service: copiar a versão nova e reaplicar o trecho marcado
com "BKplayer:" em `android/src/main/java/com/ryanheise/audioservice/AudioService.java`.
