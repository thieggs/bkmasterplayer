package io.github.playermusica.player_musica

import com.ryanheise.audioservice.AudioServiceActivity

// A activity compartilha o FlutterEngine com o serviço de mídia (audio_service):
// a música continua com a tela fechada, e os botões do fone/caixa Bluetooth, da
// notificação e da tela de bloqueio chegam ao app.
class MainActivity : AudioServiceActivity()
