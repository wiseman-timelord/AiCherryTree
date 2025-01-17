# ![LightSt0ne](https://github.com/wiseman-timelord/LightSt0ne/blob/main/media/lightstone.png)
Status: Planning

### Description:
A Program that is an AI enhanced Tree Document. The user sets up the primary nodes, some kind of basic structure, and possibly details some of the nodes, then the Ai is instructed through chat part of interface, what branches to expand upon and how, then the AI will be able to plan, then manage nodes, produce research, obtain materials, generate images/text, and fill out new nodes, and then the user will be able to inspect the relevant nodes, and further edit them, or instruct the AI to do so, or work on other stuff, etc. There is obviously the tree document editor, then the idea is the user will slide the proportions of the display between sides of, tree or ai chat, or something. Program Loads Tree on Open and Saves Tree on Close, and some kind of configurable autosave by default every 15 minutes.

## Development
- Now using llama-box `https://github.com/gpustack/llama-box/releases/download/v0.0.107/llama-box-windows-amd64-cuda-11.8.zip`, instead of llama.cpp 
- Image generation would remove requirement for image editing, to the users discretion of later replacement. [Flux v2 NSFW GGUF](https://huggingface.co/Anibaaal/Flux-Fusion-V2-4step-merge-gguf-nf4) is available and able to complete in 4 steps. Images would have to be, 200x200 for a scene or 100x200 for a person or 100x100 for an item, in pixels. I have found these sizes are optimal for LARGE tree documents. Somehow the text based model would have to be used to determine what the type is, that will then be used in the arguments sent with the prompt to the image model. Unfiltered GGUF image generation here `https://huggingface.co/Anibaaal/Flux-Fusion-V2-4step-merge-gguf-nf4`, filename `Llama-3.2-3b-NSFW_Aesir_Uncensored.gguf`, intended path `.\models\Llama-3.2-3b-NSFW_Aesir_Uncensored.gguf`
- text generation is being done with Llama 3.2 in 3b. I have found this capable of understanding complicated multi-line multi-format text. Cant wait for 3.3 unfiltered to hit. Unfiltered GGUF text generation here `https://huggingface.co/Novaciano/Llama-3.2-3b-NSFW_Aesir_Uncensored-GGUF`, filename `.\models\FluxFusionV2-Q6_K.gguf`.
- it would also be interesting to get image recognition, as this would enable checking that pictures from the web are actually correct. This will come later possibly. 
- I need to make also `LightSt0ne-STD`, or make this project `LightSt0ne-AI`, then make `LightSt0ne`, because I want a viewer/editor without the AI parts, which I logically should have made first.   

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
│   ├── texts.ps1  # the handling and prompting of text based model, as well as filtering input/output.
│   ├── images.ps1  # the handling and prompting of image model, as well as filtering input.
│   ├── internet.ps1  # the functions for web research, scraping.
│   ├── prompts.ps1  # the functions for web research, scraping.
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

## Requirements:
- Windows - Designed and tested on windows 10.
- Other Requirements - installed by the installer.

### Usage
1. run `LightSt0ne.bat`.

## Notes
- Making this program, for me and to be streamlined, its better it optimized to run on my things, hence, no install options, its `Cuda 11.8` ONLY, but I would make it for `cuda 12` if I had such a card.
- Windows ONLY, Paint Shop Pro 9 is for windows; ALL other paint progs not so good for quick arangement/editing of 100s of images.
- Inspired by an AI mod idea for [CherryTree](https://github.com/giuspen/cherrytree).
- Image processing by [ImageMagick](https://imagemagick.org/).
- Multi-platform interfaces by [Avalonia UI](https://avaloniaui.net/).
## Disclaimer:
- Wiseman-Timelord does not consent to, authorize, or empower any documents created by others using this program. Only the creators of those documents, who are not Wiseman-Timelord, hold responsibility and authority over them.
