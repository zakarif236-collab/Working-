import 'dart:io';

import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';

class MusicService {
  MusicService()
      : _query = OnAudioQuery(),
        _player = AudioPlayer();

  final OnAudioQuery _query;
  final AudioPlayer _player;

  SongModel? _currentSong;

  SongModel? get currentSong => _currentSong;
  AudioPlayer get player => _player;

  Future<void> initialize() async {
    if (!Platform.isAndroid) {
      throw const MusicServiceException(
        'Music library browsing is currently supported on Android in this build.',
      );
    }

    final granted = await _query.permissionsStatus();
    if (!granted) {
      final requested = await _query.permissionsRequest();
      if (!requested) {
        throw const MusicServiceException(
          'Music permission denied. Enable media access in settings to use your tracks.',
        );
      }
    }
  }

  Future<List<SongModel>> loadSongs() async {
    try {
      final songs = await _query.querySongs(
        sortType: SongSortType.DISPLAY_NAME,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
      );

      final playable = songs.where((song) {
        final uri = song.uri;
        return uri != null && uri.isNotEmpty && song.isMusic == true;
      }).toList();

      if (playable.isEmpty) {
        throw const MusicServiceException(
          'No playable songs found on your device yet.',
        );
      }

      return playable;
    } catch (e) {
      if (e is MusicServiceException) {
        rethrow;
      }
      throw MusicServiceException(
        'Unable to read your music library right now: $e',
      );
    }
  }

  Future<void> playSong(SongModel song) async {
    final uri = song.uri;
    if (uri == null || uri.isEmpty) {
      throw const MusicServiceException(
        'That track cannot be played because its file path is unavailable.',
      );
    }

    try {
      await _player.setAudioSource(AudioSource.uri(Uri.parse(uri)));
      await _player.play();
      _currentSong = song;
    } catch (e) {
      throw MusicServiceException('Playback failed: $e');
    }
  }

  Future<void> togglePlayPause() async {
    if (_player.playing) {
      await _player.pause();
      return;
    }

    if (_currentSong == null) {
      throw const MusicServiceException(
        'Pick a song first so we can start playback.',
      );
    }

    await _player.play();
  }

  Future<void> stop() async {
    await _player.stop();
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}

class MusicServiceException implements Exception {
  const MusicServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
