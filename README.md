# LightSt0ne
Status: Planning

### Description:
A Program that is a AI enhanced Tree Document. The Ai is instructed through chat part of interface, then the AI will be able to manage nodes and fill out nodes with appropriate data, furthermore, the user will be able to tell it to research on the internet. The User is also able to manage and edit nodes. Program Loads on Open and Saves on Close. Ai will be generating text and the user will be doing the image editing. First priority is, stable with working tree document interface. I get that most of you will not understand the significance of this program or its purposes, but if you do, then support me, support me and support me some more, albeit let me move in and put my feet on the furniture.

## Development
- It will be designed to work on Windows ONLY. This is the case because Paint Shop Pro 9 is made for windows; ALL other paint programs I have ever tried are not so good for quick editing of images, and it stil works with up to windows 10 from my own experience.
- Avalonia UI for multi-platform interfaces.
- It would be nice to have both image recognition and generation. with image recognition, you could point it to a resource of images and state "make best use of the images in my tree". Image generation would remove requirement for image editing, but still the user is able to replace images if they dont completely approve of the given generated image.

### File Structure
Oh yes, it's getting serious now...
```
.
├── LightSt0ne.bat  # the user's entry point. 
├── installer.ps1  # Standalone script, separate from program - install the program and its requirements. 
├── launcher.ps1  # launch the program, entry point for other scripts.
├── scripts
│   ├── interface.ps1  # ALL interface code for `Avalonia UI` and any menus.
│   ├── utility.ps1  # the functions that dont fit better elsewhere. This should also contain `impexppsd1`.
│   ├── model.ps1  # the handling and prompting of models, as well as filtering input/output.
│   ├── internet.ps1  # the functions for web research, scraping.
├── data
│   ├── temporary.ps1  # location of ALL, globals, maps, lists, constants.
│   ├── persistent.psd1  # persistent settings able to be configured in interface, as well as other critical persistent information.
│   └── cudart-llama-bin-win-cu11.7  # contents of cudart-llama-bin-win-cu11.7-x64.zip
│   └── backup.ls0  # the last good version of the tree document upon loading, as a fallback for corrupt load file
│   └── default.ls0  # the default tree file, with critical information on using the program and its features. This is copied to `.\foliage\tree.ls0` upon first run.
│   └── ImageMagick  # folder for installed ImageMagick files.
├── foliage
│   └── tree.ls0  # the single individual tree that the user will work with, loaded upon running the program, and then saved to when, exiting the program or auto-save.
│   └── images  # the folder for the images indexed in the tree, files are saved in lossless jpg with a 8 character hash, ie `.\foliage\images\39ph490g.jpg`.  
│   └── texts  # the folder for the pages indexed in the tree, files are saved in txt with a 8 character hash, ie `.\foliage\text\390ef94i.txt`.  
└── temp  #  container for temporary files, ie downloads, website data, images being processed
```


## Notes
- Inspired by [CherryTree](https://github.com/giuspen/cherrytree)

## Disclaimer:
- Wiseman-Timelord does not consent to, authorize, or empower any documents created by others using this program. Only the creators of those documents, who are not Wiseman-Timelord, hold responsibility and authority over them.
