# v

Open things from console. Uses associated application automatically. Examples:

    v ~/download/   # ==> nautilus ~/download/
    v ~/file.jpg    # ==> gwenview ~/file.jpg
    v ~/video.mp4   # ==> mplayer ~/video.mp4

Supports additional modifiers

    v movie.mkv 1.2x +10dB    # ==> mplayer -af volume=+10dB,scaletempo -speed 1.2 movie.mkv