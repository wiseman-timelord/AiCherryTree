# ![LightSt0ne](https://github.com/wiseman-timelord/LightSt0ne/blob/main/media/lightstone.png)
Status: Planning

### Description:
A Program that is a AI enhanced Tree Document. The Ai is instructed through chat part of interface, then the AI will be able to manage nodes and fill out nodes with appropriate data, furthermore, the user will be able to tell it to research on the internet. The User is also able to manage and edit nodes. Program Loads on Open and Saves on Close. Ai will be generating text and the user will be doing the image editing. I am making this program for me, its better it just designed to run on my things, hence, I am not making it with install options, its `Cuda 11.8` ONLY, though I am sure it could easily be adapted, with a little edit of the installer, and im also sure if £500-1000 appeared in my bank, it would soon be made for cuda 12.

## Development
- Now using llama-box `https://github.com/gpustack/llama-box/releases/download/v0.0.107/llama-box-windows-amd64-cuda-11.8.zip`
- It will be designed to work on Windows ONLY. This is because Paint Shop Pro 9 is for windows; ALL other paint programs are not so good for quick editing of LOTS of images, and windows XP-10 compatible to boot.
- It would be nice to have both image generation. Image generation would remove requirement for image editing, to the users discretion of later replacement. [Flux v2 NSFW GGUF](https://huggingface.co/Anibaaal/Flux-Fusion-V2-4step-merge-gguf-nf4) is available and able to complete in 4 steps. Images would have to be, 200x200 for a scene or 100x200 for a person or 100x100 for an item, in pixels. I have found these sizes are optimal for LARGE tree documents. Somehow the text based model would have to be used to determine what the type is, that will then be used in the arguments sent with the prompt to the image model. Unfiltered GGUF image generation here `https://huggingface.co/Anibaaal/Flux-Fusion-V2-4step-merge-gguf-nf4`, filename `Llama-3.2-3b-NSFW_Aesir_Uncensored.gguf`, intended path `.\models\Llama-3.2-3b-NSFW_Aesir_Uncensored.gguf`
- text generation is being done with Llama 3.2 in 3b. I have found this capable of understanding complicated multi-line multi-format text. Cant wait for 3.3 unfiltered to hit. Unfiltered GGUF text generation here `https://huggingface.co/Novaciano/Llama-3.2-3b-NSFW_Aesir_Uncensored-GGUF`, filename `.\models\FluxFusionV2-Q6_K.gguf`.

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
- Inspired by an AI mod idea for [CherryTree](https://github.com/giuspen/cherrytree).
- Image processing by [ImageMagick](https://imagemagick.org/).
- Multi-platform interfaces by [Avalonia UI](https://avaloniaui.net/).
## Disclaimer:
- Wiseman-Timelord does not consent to, authorize, or empower any documents created by others using this program. Only the creators of those documents, who are not Wiseman-Timelord, hold responsibility and authority over them.
