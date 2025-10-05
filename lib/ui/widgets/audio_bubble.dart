import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

class AudioBubble extends StatefulWidget {
  final String path;
  const AudioBubble({super.key, required this.path});

  @override
  State<AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<AudioBubble> {
  final _player = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _player.setFilePath(widget.path);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlayerState>(
      stream: _player.playerStateStream,
      builder: (ctx, snap) {
        final playing = snap.data?.playing ?? false;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                onPressed: () => playing ? _player.pause() : _player.play(),
              ),
              StreamBuilder<Duration?>(
                stream: _player.durationStream,
                builder: (ctx, durSnap) {
                  final total = durSnap.data ?? Duration.zero;
                  return StreamBuilder<Duration>(
                    stream: _player.positionStream,
                    builder: (ctx, posSnap) {
                      final pos = posSnap.data ?? Duration.zero;
                      final value = (total.inMilliseconds == 0)
                          ? 0.0
                          : pos.inMilliseconds / total.inMilliseconds;
                      return SizedBox(
                        width: 150,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            LinearProgressIndicator(value: value.clamp(0.0, 1.0)),
                            const SizedBox(height: 4),
                            Text('${_fmt(pos)} / ${_fmt(total)}',
                                style: Theme.of(context).textTheme.labelSmall),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
