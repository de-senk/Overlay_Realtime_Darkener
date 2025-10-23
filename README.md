# Overlay_Realtime_Darkener
because dark mode extensions can't dark videos with white backgrounds, and they dont work most of the times anyways.
so the idea is:
- Capture a whole screenshot every frame
- Ovelay the screenshoot on top with click through enabled
- The overlayed screenshots require some analysis before dispalying, first I will try to detect too white pixels and exchange them with black
- First, the analysis will just bruteforce it, then maybe with Second I will create something more useful.
- Second, maybe I will try to use a kernel pass to detect text and inver the colors
