# LightSt0ne
Status: Planning

### Description:
A Program that is a AI enhanced Tree Document. The Ai is instructed through chat part of interface, then the AI will be able to manage nodes and fill out nodes with appropriate data, furthermore, the user will be able to tell it to research on the internet. The User is also able to manage and edit nodes. Program Loads on Open and Saves on Close. Ai will be generating text and the user will be doing the image editing. First priority is, stable with working tree document interface. I get that most of you will not understand the significance of this program or its purposes, but if you do, then support me, support me and support me some more, albeit let me move in and put my feet on the furniture, I will probably even let you be my pet servant if you prove loyal enough to my grand vision.

## Notes
- It will be designed to work on Windows ONLY. This is the case because Paint Shop Pro 9 is made for windows; ALL other paint programs I have ever tried are not so good for quick editing of images, and it stil works with up to windows 10 from my own experience.
- Avalonia UI for multi-platform interfaces.
- It would be nice to have both image recognition and generation.
- Inspired by [CherryTree](https://github.com/giuspen/cherrytree)

### File Structure
Oh yes, it's getting serious now...
```
.\LightSt0ne.bat  # file containing launch and install 
.\install_script.ps1  # powershell script for installing requirements
.\main_script.ps1   # main script containing core components.
.\scripts\interface.ps1   # main script containing any menus for main program and 
.\scripts\utility.ps1    # ALL code not fitting better elsewhere.
.\scripts\model.ps1   # ALL model related code.
.\scripts\internet.ps1   # ALL code related to searching/browsing/scraping websites for research.
.\data\temporary.ps1    # the file containing ALL of the, global variables, global constants, maps, lists. all such things in ONE place, avoiding any possibility of circular imports for such things.
.\data\persistent.psd1   # the file containing 
.\data\cudart-llama-bin-win-cu11.7\  # folder where llama is downloaded and 
.\data\backup.dat    # the default book file, that is copied to `.\foliage\tree.ls0` when the program starts for the first time where  `.\foliage\tree.ls0` is detected to be missing upon startup.
.\foliage\   # the folder where the tree and its files will be organized and kept
.\foliage\images   # the folder where the tree and its files will be organized and kept
.\temp\   # folder in which the program will be working upon files or storing files for processing. 
```
