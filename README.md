setbg
=====

An alternative to using the Dock to display a desktop background on Mac OS X.

This was built as a solution for those that do not wish to use the Dock process (as that is in charge of the desktop background image too), want a little more control over what content they can display/how it will be displayed.

It allows for a variety of different display options, from specifying how the image should be sized, position, how it should fill the screen (single or tiled), to different kinds of content other than images (see todo), to timed sequences (displaying some content for a period of time, then displaying the next).

Other than visual options, it also allows for the focus to be set to a particular app. e.g. If you disable the Dock and Finder and wish to use this as the final backdrop, but want the focus to be kept on something else higher up you can.



Usage:
------
Use --help to get a list of commands. Will add the commands here later.

Some examples:
The order of commands can be thought of as as sequence of operations. Where the last set operation can then have additional options to define its usage.

setbg -i img1.png (Sets the background to img1.png)
setbg -i img1.png -isfixed (Sets the background to img1.png, without performing any resizing)
setbg -i img1.png -isset 16 16 -offbl -tiled (Sets the background to img1.png sized at 16*16, which tiles across the screen starting at the bottom left corner)
setbg -i img1.png -isset 16 16 -offbl (Sets the background to img1.png sized at 16*16, which originates at the bottom left corner)
setbg -i img1.png -t 2 -i img2.png -t 2 -i img3.png -t 2 -r (Sets the background to img1.png for 2 seconds, then to img2.png for 2 seconds, then to img3.png for 2 seconds, then back to img1.png for 2 seconds, etc.)



To-Do's
-------
 * Support plugins, these will most likely be Quartz Compositions. The plugin support is for content that is beyond a simple image or needs to be controlled in a specific way.

 * (also a bug) The app will need to be applied to the full screen of all screens. At the moment it currently sets the size of the app to the screen size of the current screen, which obviously may not be the size of all screens.

 * Specify background for specific screens.

 * Separate some of the functionality so some options can be used as toggles not resetting the current content pipeline.

 * (also a bug) Images currently get cached to whatever size will make them consume the least amount of memory but still avoid any scaling up (if possible). So assume an input image is 300*300, and it will be drawn as fixed, while the destination screen is only 100*100, as only a portion of the image will be drawn it will simply cache that portion and release the rest (so it doesn't need to keep unused image data in memory). But at the moment it simply does it based on the destination rect which is the current view's rect, meaning when multiple screens are supported properly the fix here would be to see what is the biggest screen it could be applied to and use that as the destination rect for the caching.

 * Workout the Dock's default image positioning and sizing. So it can provide an exact copy of what would normally happen.


Side notes:
While I kept it as a single file for simplicity reasons (completely self contained, and dead simple to compile), if more functionality needs to be added it may be turned into a properly organized project.