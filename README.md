# v

Open things from console. Uses associated application automatically. Examples (file associations for my system!):

    > v ~/download/   # ==> nautilus ~/download/
    > v ~/file.jpg    # ==> gwenview ~/file.jpg
    > v ~/video.mp4   # ==> mplayer ~/video.mp4

Supports additional modifiers

    > v movie.mkv 1.2x +10dB  
      ==> mplayer -af volume=+10dB,scaletempo -speed 1.2 movie.mkv

Smart mode for folders

    > ls music_cd/
      01.mp3
      02.mp3
      ...
      album.jpg
      songs.txt

    > v music_cd
      ==> will play mp3's with mplayer

    > ls dev_app/
      ...
      README.md
      ...

    > v dev_app/
      ==> open folder with sublime


# Requirements

`v` currently runs on Linux and requires:

* ruby and gems


# Installation

    > gem build *.gemspec && gem install *.gem

# Usage

Refer to:

    > v -h

# Default file associations

According to [Arch Linux wiki](https://wiki.archlinux.org/index.php/Default_Applications) applications should look inside 

* `/usr/share/applications/mimeapps.list` and 
* `~/.local/share/applications/mimeapps.list` 

for mime associations. These are the files `v` checks primarily, so it is recommended to edit them if you want adjustments. 

Here is an example, which uses `evince` for pdf, `sublime` for text files and `firefox` for htmls.

    > cat ~/.local/share/applications/mimeapps.list 

      [Default Applications]
      application/pdf=evince.desktop
      text/plain=sublime_text.desktop
      text/x-ruby=sublime_text.desktop
      text/html=chromium.desktop

An example `mimeapps.list` can be found in `examples/mimeapps.list`. It is configured to use firefox, sublime, evince, and mplayer.

# Changing file associations

I found that on a general Linux installation associations can be quite messed up. Here's how you should approach changing them:

1. Identify a file you want to change. Here, `v` misbehaves on `README.md`

        > v README.md   # ~> misbehaves

2. Find out how `v` handles this file.

        > v README.md -p -d
        .. got mime 'text/plain' for /t/README.md, validating...
        -- got mime 'text/plain' for /t/README.md
        .. desktop file 'cr3.desktop' found for 'text/plain' in 
           /usr/share/applications/mimeinfo.cache (key: 'MIME Cache')
        -- got runner 'cr3 %F' for /t/README.md
        -- run: cr3 "/t/README.md"

3. In this example `text/plain` was the identified mime type and it was associated to `cr3.desktop`. Let's change `text/plain` to work with `sublime` by default. You must find your program's desktop file:

        > ls /usr/share/applications
        ...
        sublime_text.desktop
        ...

    Sometimes these `.desktop` files are found in subfolders, e.g.

        /usr/share/applications/kde4/gwenview.desktop

    Use the subfolder as part of the name of the desktop file, i.e.

        kde4-gwenview.desktop

4. So the name I want is `sublime_text.desktop`. Now add it to my `mimeapps`. Edit

        ~/.local/share/applications/mimeapps.list 

    Under `Default Applications` add the association via the mime-type (`text/plain`) and the executable (`sublime_text.desktop`)

        [Default Applications]
        ...
        text/plain=sublime_text.desktop
        ...

5. Try it out

        > v README.md

    You can also view the new association

        > v README.md -p -d
        .. got mime 'text/plain' for /t/README.md, validating...
        -- got mime 'text/plain' for /t/README.md
        .. desktop file 'sublime_text.desktop' found for 'text/plain' in
           /home/me/.local/share/applications/mimeapps.list (key: 'Default Applications')
        -- got runner 'subl %U' for /t/README.md
        -- run: subl "/t/README.md"
