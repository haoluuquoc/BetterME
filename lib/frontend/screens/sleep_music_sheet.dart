import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SleepMusicSheet extends StatefulWidget {
  const SleepMusicSheet({super.key});

  @override
  State<SleepMusicSheet> createState() => _SleepMusicSheetState();
}

enum _PlaybackMode { all, one, shuffle }

class _SleepMusicSheetState extends State<SleepMusicSheet>
  with SingleTickerProviderStateMixin {
  static const String _customTracksKey = 'sleep_music_custom_tracks';

  final AudioPlayer _player = AudioPlayer();
  final List<_SleepTrack> _builtinTracks = const [
    _SleepTrack(
      title: 'Rain against window',
      subtitle: 'Wikimedia Commons • Public domain',
      url: 'https://upload.wikimedia.org/wikipedia/commons/4/41/Rain_against_the_window.ogg',
      isRecommended: true,
    ),
    _SleepTrack(
      title: 'Rain and thunder',
      subtitle: 'Wikimedia Commons • Public domain',
      url: 'https://upload.wikimedia.org/wikipedia/commons/4/42/Rain_and_thunder.ogg',
      isRecommended: true,
    ),
    _SleepTrack(
      title: 'Sound of rain',
      subtitle: 'Wikimedia Commons • CC BY-SA 3.0',
      url: 'https://upload.wikimedia.org/wikipedia/commons/8/8a/Sound_of_rain.ogg',
      isRecommended: true,
    ),
    _SleepTrack(
      title: 'Calm rain',
      subtitle: 'Wikimedia Commons • CC BY-SA 4.0',
      url: 'https://upload.wikimedia.org/wikipedia/commons/c/cf/Calm_rain.wav',
      isRecommended: true,
    ),
    _SleepTrack(
      title: 'Heavy rain in summer',
      subtitle: 'Wikimedia Commons • CC BY-SA 3.0',
      url: 'https://upload.wikimedia.org/wikipedia/commons/6/69/Heavy_Rain_in_Summer.ogg',
      isRecommended: false,
    ),
    _SleepTrack(
      title: 'Light rain distant thunder',
      subtitle: 'Wikimedia Commons • CC0',
      url: 'https://upload.wikimedia.org/wikipedia/commons/b/b6/Light_Rain_Distant_Thunder_July_5th_2016.wav',
      isRecommended: false,
    ),
    _SleepTrack(
      title: 'Rain on leaves',
      subtitle: 'Wikimedia Commons • CC BY 4.0',
      url: 'https://upload.wikimedia.org/wikipedia/commons/9/92/Rain_on_leaves_%28Gravity_Sound%29.wav',
      isRecommended: false,
    ),
    _SleepTrack(
      title: 'Rain drops',
      subtitle: 'Wikimedia Commons • CC BY 4.0',
      url: 'https://upload.wikimedia.org/wikipedia/commons/6/6b/Rain_drops_%28Gravity_Sound%29.wav',
      isRecommended: false,
    ),
    _SleepTrack(
      title: 'Rain veranda',
      subtitle: 'Wikimedia Commons • Public domain',
      url: 'https://upload.wikimedia.org/wikipedia/commons/7/7c/Rain_on_a_veranda_and_t.ogg',
      isRecommended: false,
    ),
    _SleepTrack(
      title: 'Rain thunder birds',
      subtitle: 'Wikimedia Commons • Public domain',
      url: 'https://upload.wikimedia.org/wikipedia/commons/a/ab/Rain_thunder_and_birds.ogg',
      isRecommended: false,
    ),
    _SleepTrack(
      title: 'River rain shower',
      subtitle: 'Wikimedia Commons • CC0',
      url: 'https://upload.wikimedia.org/wikipedia/commons/b/ba/River_Sounds_Rain_Shower.webm',
      isRecommended: false,
    ),
    _SleepTrack(
      title: 'River water shower',
      subtitle: 'Wikimedia Commons • CC0',
      url: 'https://upload.wikimedia.org/wikipedia/commons/a/a1/River_Water_Sounds_Rain_Shower_4.webm',
      isRecommended: false,
    ),
    _SleepTrack(
      title: 'Mua dem nhe',
      subtitle: 'Pixabay • Royalty-free',
      url:
          'https://cdn.pixabay.com/download/audio/2022/03/15/audio_c8ecf6f6c0.mp3?filename=calm-meditation-ambient-11157.mp3',
      isRecommended: true,
    ),
    _SleepTrack(
      title: 'Suoi rung',
      subtitle: 'Pixabay • Royalty-free',
      url:
          'https://cdn.pixabay.com/download/audio/2021/09/06/audio_1f5ddf4f8d.mp3?filename=forest-with-small-river-birds-and-nature-field-recording-6735.mp3',
      isRecommended: true,
    ),
    _SleepTrack(
      title: 'Brown noise',
      subtitle: 'Pixabay • Royalty-free',
      url:
          'https://cdn.pixabay.com/download/audio/2024/02/19/audio_6c5a6bf9f7.mp3?filename=brown-noise-192598.mp3',
      isRecommended: true,
    ),
  ];

  List<_SleepTrack> _customTracks = [];
  int? _selectedIndex;
  bool _isLoading = false;
  String? _playError;
  _PlaybackMode _playbackMode = _PlaybackMode.all;
  late final AnimationController _discController;

  List<_SleepTrack> get _allTracks => [..._builtinTracks, ..._customTracks];

  @override
  void initState() {
    super.initState();
    _discController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    );
    _player.playerStateStream.listen((state) {
      if (!mounted) return;

      if (_player.playing) {
        if (!_discController.isAnimating) {
          _discController.repeat();
        }
      } else {
        _discController.stop();
      }

      if (state.processingState == ProcessingState.completed) {
        _handleTrackCompleted();
      }

      setState(() {});
    });
    _loadCustomTracks();
  }

  @override
  void dispose() {
    _discController.dispose();
    _player.dispose();
    super.dispose();
  }

  String _modeLabel(_PlaybackMode mode) {
    switch (mode) {
      case _PlaybackMode.all:
        return 'All';
      case _PlaybackMode.one:
        return '1 bai';
      case _PlaybackMode.shuffle:
        return 'Random';
    }
  }

  IconData _modeIcon(_PlaybackMode mode) {
    switch (mode) {
      case _PlaybackMode.all:
        return Icons.repeat;
      case _PlaybackMode.one:
        return Icons.repeat_one;
      case _PlaybackMode.shuffle:
        return Icons.shuffle;
    }
  }

  Future<void> _loadCustomTracks() async {
    final prefs = await SharedPreferences.getInstance();
    final rows = prefs.getStringList(_customTracksKey) ?? [];
    final parsed = <_SleepTrack>[];

    for (final row in rows) {
      try {
        final map = jsonDecode(row);
        if (map is Map<String, dynamic>) {
          final title = (map['title'] ?? '').toString().trim();
          final url = (map['url'] ?? '').toString().trim();
          if (title.isNotEmpty && url.isNotEmpty) {
            parsed.add(
              _SleepTrack(
                title: title,
                subtitle: 'Ban da them',
                url: url,
                isRecommended: false,
              ),
            );
          }
        }
      } catch (_) {
        // Ignore malformed rows to keep music list resilient.
      }
    }

    if (!mounted) return;
    setState(() => _customTracks = parsed);
  }

  Future<void> _saveCustomTracks() async {
    final prefs = await SharedPreferences.getInstance();
    final rows = _customTracks
        .map(
          (track) => jsonEncode({
            'title': track.title,
            'url': track.url,
          }),
        )
        .toList();
    await prefs.setStringList(_customTracksKey, rows);
  }

  Future<void> _playTrack(int index) async {
    if (index < 0 || index >= _allTracks.length) return;
    final track = _allTracks[index];

    setState(() {
      _isLoading = true;
      _playError = null;
      _selectedIndex = index;
    });

    try {
      final source = AudioSource.uri(
        Uri.parse(track.url),
        tag: MediaItem(
          id: track.url,
          album: 'BetterMe Sleep',
          title: track.title,
          artist: track.subtitle,
        ),
      );
      await _player.setAudioSource(source);
      await _player.play();
    } catch (_) {
      if (!mounted) return;
      setState(() => _playError = 'Khong the phat bai nay, vui long thu link khac.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _togglePlayPause() async {
    if (_selectedIndex == null) {
      if (_allTracks.isEmpty) return;
      await _playTrack(0);
      return;
    }

    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }

    if (!mounted) return;
    setState(() {});
  }

  Future<void> _playPrevious() async {
    final total = _allTracks.length;
    if (total == 0) return;
    final current = _selectedIndex;
    if (current == null) {
      await _playTrack(0);
      return;
    }
    final prev = (current - 1 + total) % total;
    await _playTrack(prev);
  }

  Future<void> _playNext() async {
    final total = _allTracks.length;
    if (total == 0) return;
    final current = _selectedIndex;
    if (current == null) {
      await _playTrack(0);
      return;
    }

    int next = 0;
    if (_playbackMode == _PlaybackMode.shuffle) {
      if (total == 1) {
        next = 0;
      } else {
        final rand = Random();
        do {
          next = rand.nextInt(total);
        } while (next == current);
      }
    } else {
      next = (current + 1) % total;
    }
    await _playTrack(next);
  }

  Future<void> _seekBy(Duration offset) async {
    final duration = _player.duration;
    var next = _player.position + offset;
    if (next < Duration.zero) {
      next = Duration.zero;
    }
    if (duration != null && next > duration) {
      next = duration;
    }
    await _player.seek(next);
  }

  Future<void> _handleTrackCompleted() async {
    final current = _selectedIndex;
    if (current == null) return;

    if (_playbackMode == _PlaybackMode.one) {
      await _playTrack(current);
      return;
    }

    await _playNext();
  }

  Future<void> _showAddTrackDialog() async {
    final titleCtrl = TextEditingController();
    final urlCtrl = TextEditingController();

    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Them nhac ngu'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Ten bai',
                hintText: 'VD: Rain mix 45p',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlCtrl,
              decoration: const InputDecoration(
                labelText: 'Link audio (https)',
                hintText: 'https://...mp3',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Huy'),
          ),
          ElevatedButton(
            onPressed: () {
              final title = titleCtrl.text.trim();
              final url = urlCtrl.text.trim();
              final valid =
                  title.isNotEmpty && (url.startsWith('https://') || url.startsWith('http://'));
              if (!valid) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Them'),
          ),
        ],
      ),
    );

    if (added != true) return;

    final title = titleCtrl.text.trim();
    final url = urlCtrl.text.trim();

    if (!mounted) return;
    setState(() {
      _customTracks.add(
        _SleepTrack(
          title: title,
          subtitle: 'Ban da them',
          url: url,
          isRecommended: false,
        ),
      );
    });
    await _saveCustomTracks();
  }

  Future<void> _removeCustomTrack(int customIndex) async {
    if (customIndex < 0 || customIndex >= _customTracks.length) return;

    final absoluteIndex = _builtinTracks.length + customIndex;
    final wasSelected = _selectedIndex == absoluteIndex;

    if (!mounted) return;
    setState(() {
      _customTracks.removeAt(customIndex);
      if (wasSelected) {
        _selectedIndex = null;
        _playError = null;
      } else if (_selectedIndex != null && _selectedIndex! > absoluteIndex) {
        _selectedIndex = _selectedIndex! - 1;
      }
    });

    if (wasSelected) {
      await _player.stop();
    }

    await _saveCustomTracks();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedIndex != null && _selectedIndex! < _allTracks.length
        ? _allTracks[_selectedIndex!]
        : null;

    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF111318),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Nhac ngu',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _showAddTrackDialog,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Them'),
                  ),
                ],
              ),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Nguon de xuat: Wikimedia Commons (CC/PD) va Pixabay royalty-free',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C2028),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selected?.title ?? 'Chua chon bai',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      selected?.subtitle ?? 'Chon mot bai goi y hoac them link cua ban',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: RotationTransition(
                        turns: _discController,
                        child: Container(
                          width: 104,
                          height: 104,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF3A4254), Color(0xFF161B25)],
                            ),
                            border: Border.all(color: const Color(0xFF6EA3D8), width: 2),
                          ),
                          child: const Center(
                            child: CircleAvatar(
                              radius: 14,
                              backgroundColor: Color(0xFF6EA3D8),
                              child: Icon(Icons.music_note, color: Colors.white, size: 16),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_playError != null) ...[
                      const SizedBox(height: 8),
                      Text(_playError!, style: const TextStyle(color: Colors.orangeAccent)),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          onPressed: _isLoading ? null : _playPrevious,
                          icon: const Icon(Icons.skip_previous_rounded, color: Colors.white),
                          iconSize: 34,
                          tooltip: 'Bai truoc',
                        ),
                        IconButton(
                          onPressed: _isLoading ? null : () => _seekBy(const Duration(seconds: -5)),
                          icon: const Icon(Icons.replay_5_rounded, color: Colors.white),
                          iconSize: 30,
                          tooltip: 'Lui 5 giay',
                        ),
                        const SizedBox(width: 6),
                        ElevatedButton(
                          onPressed: _isLoading ? null : _togglePlayPause,
                          style: ElevatedButton.styleFrom(
                            shape: const CircleBorder(),
                            padding: const EdgeInsets.all(14),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Icon(
                                  _player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                  size: 30,
                                ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          onPressed: _isLoading ? null : () => _seekBy(const Duration(seconds: 5)),
                          icon: const Icon(Icons.forward_5_rounded, color: Colors.white),
                          iconSize: 30,
                          tooltip: 'Tua 5 giay',
                        ),
                        IconButton(
                          onPressed: _isLoading ? null : _playNext,
                          icon: const Icon(Icons.skip_next_rounded, color: Colors.white),
                          iconSize: 34,
                          tooltip: 'Bai tiep',
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (final mode in _PlaybackMode.values)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: ChoiceChip(
                              selected: _playbackMode == mode,
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(_modeIcon(mode), size: 16),
                                  const SizedBox(width: 4),
                                  Text(_modeLabel(mode)),
                                ],
                              ),
                              onSelected: (_) => setState(() => _playbackMode = mode),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton.icon(
                        onPressed: () async {
                          await _player.stop();
                          if (!mounted) return;
                          setState(() {
                            _selectedIndex = null;
                          });
                        },
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: const Text('Dung phat'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: _allTracks.length,
                  itemBuilder: (context, index) {
                    final item = _allTracks[index];
                    final selectedRow = _selectedIndex == index;
                    final isCustom = index >= _builtinTracks.length;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: selectedRow ? const Color(0xFF253047) : const Color(0xFF1A1E26),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selectedRow ? const Color(0xFF6EA3D8) : Colors.transparent,
                        ),
                      ),
                      child: ListTile(
                        onTap: () => _playTrack(index),
                        leading: Icon(
                          item.isRecommended ? Icons.nightlight_round : Icons.library_music,
                          color: item.isRecommended ? Colors.lightBlueAccent : Colors.white70,
                        ),
                        title: Text(
                          item.title,
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          item.subtitle,
                          style: const TextStyle(color: Colors.white60),
                        ),
                        trailing: isCustom
                            ? IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.white54),
                                onPressed: () => _removeCustomTrack(index - _builtinTracks.length),
                              )
                            : const Icon(Icons.play_circle_outline, color: Colors.white54),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SleepTrack {
  const _SleepTrack({
    required this.title,
    required this.subtitle,
    required this.url,
    required this.isRecommended,
  });

  final String title;
  final String subtitle;
  final String url;
  final bool isRecommended;
}
