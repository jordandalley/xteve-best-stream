# yt-dlp-wrapper.sh

When using proxy mode in xteve and threadfin, ffmpeg effectively pulls all streams available in the manifest. This is not optimal, as typically only one stream is viewed by the client.

This script utilises 'yt-dlp' to download, and cache the the highest quality HLS streams before passing it off to ffmpeg.

When using docker, you'll need to download a yt-dlp binary and include it into your xteve/threadfin container. I generally map the binary to /usr/sbin/yt-dlp.

To add the script to xteve/threadfin, the following config can be used. No proxy support as yet, but this isn't hard to implement.

![image](https://github.com/user-attachments/assets/8a848442-174b-4519-97fd-33be363bcdfe)
