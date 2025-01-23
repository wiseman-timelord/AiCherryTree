# ![LightSt0ne](https://github.com/wiseman-timelord/LightSt0ne/blob/main/media/lightstone.png)
Status: Alpha

### Description:
A Program that is an AI enhanced Tree Document. The user sets up the primary nodes, some kind of basic structure, and possibly details some of the nodes, then the Ai is instructed through chat part of interface, what branches to expand upon and how, then the AI will be able to plan, then manage nodes, produce research, obtain materials, generate images/text, and fill out new nodes, and then the user will be able to inspect the relevant nodes, and further edit them, or instruct the AI to do so, or work on other stuff, etc. There is obviously the tree document editor, then the idea is the user will slide the proportions of the display between sides of, tree or ai chat, or something. Program Loads Tree on Open and Saves Tree on Close, and some kind of configurable autosave by default every 15 minutes. Its intended to create detailed nodes, max ~2300 text characters per page, so as to do it in 1 output, therein, generic images can be generated and specific versions of things in images are gained from internet, idea same with the text. 

## Development
- Now using llama-box `https://github.com/gpustack/llama-box/releases/download/v0.0.107/llama-box-windows-amd64-cuda-11.8.zip`, instead of llama.cpp 
- Image generation removes most requirement for image, finding and editing, to the users discretion of later replacement. [Flux v2 NSFW GGUF](https://huggingface.co/Anibaaal/Flux-Fusion-V2-4step-merge-gguf-nf4) is available and able to complete in 4 steps. Images would have to be, 300x200 for a scene or 100x200 for a person or 100x100 for an item, in pixels. I have found these sizes are optimal for LARGE tree documents. Somehow the text based model would have to be used to determine what format is, that will then be used in the arguments sent with the prompt to the image model. Unfiltered GGUF image generation here `https://huggingface.co/Anibaaal/Flux-Fusion-V2-4step-merge-gguf-nf4`, filename `Llama-3.2-3b-NSFW_Aesir_Uncensored.gguf`, intended path `.\models\Llama-3.2-3b-NSFW_Aesir_Uncensored.gguf`
- text generation is being done with Llama 3.2 in 3b. I have found this capable of understanding complicated multi-line multi-format text. Cant wait for 3.3 unfiltered to hit. Unfiltered GGUF text generation here `https://huggingface.co/Novaciano/Llama-3.2-3b-NSFW_Aesir_Uncensored-GGUF`, filename `.\models\FluxFusionV2-Q6_K.gguf`.
- the sliders for n_ctx and n_batch, are the maximum, we will alter the values relevant to the task. Additionally, a max, n_batch of 4096 and n_ctx of 131072, and only settings, n_batch 2048/4096 and n_ctx 8192/16384/32768/65536/131072, to simplify. If normally task use for example 65536, but max set to for example 32768, then it would use 32768 for the task. 
- We would read how many characters the input text has, therein, I work out characters from tokens as `(((TOKENS/5)*4)/4)*3=CHARACTERS`, so  we would use the reverse calculation, and see what options it fits within best.
- Export and Import from Compressed file, this will require use of built in windows zip functionality on fast compression, format would be `.lightst0ne`, and upon import then foliage would be wiped and the file being imported would then be expanded to foliage.
- Smaller download, so we do not require the SDK...
```
Resource	Link	Contents
NuGet Packages	NuGet.org	Core libraries for Avalonia UI (Desktop, Browser, Mobile).
Project Templates	.NET CLI (dotnet new install Avalonia.Templates)	Templates for creating new Avalonia projects.
Semi.Avalonia Theme	NuGet.org	Modern UI themes and additional controls for Avalonia.
Nightly Builds	Avalonia NuGet Feed	Latest unstable builds with new features and bug fixes.
```

### File Structure
- Package Files...
```
├── LightSt0ne.bat  # the user's entry point. 
├── installer.ps1  # Standalone script, separate from program - install the program and its requirements. 
├── launcher.ps1  # launch the program, entry point for other scripts.
├── scripts
│   ├── interface.ps1  # interface code for `Avalonia UI` and any menus.
│   ├── interface.xaml  # more interface code in a more efficient format (code reduction 80%).
│   ├── utility.ps1  # the functions that dont fit better elsewhere. This should also contain `impexppsd1` functions, for read/write to psd1.
│   ├── texts.ps1  # the, handling and filtering, of text based operations.
│   ├── images.ps1  # the, handling and filtering, of image based operations.
│   ├── internet.ps1  # the functions for web research, scraping.
│   ├── prompts.ps1  # the functions for web research, scraping.
│   ├── nodes.ps1  # the functions for node management.
│   ├── model.ps1  # the script for model management.
```
- Files created by `.\installer.ps1`...
```
└── temp  #  container for temporary files, ie downloads, website data, images being processed
├── data  # Mostly, downloaded from internet or created by `installer.ps1` 
│   ├── temporary.ps1  # location of ALL, globals, maps, lists, constants.
│   ├── persistent.psd1  # persistent settings able to be configured in interface, as well as other critical persistent information.
│   └── cudart-llama-bin-win-cu11.7  # contents of cudart-llama-bin-win-cu11.7-x64.zip
│   └── default.ls0  # the default tree file, with critical information on using the program and its features. This is copied to `.\foliage\tree.ls0` upon first run of launcher.
│   └── ImageMagick  # folder for installed ImageMagick files.
```
- files, as required, created through, `.\launcher.ps1` and main program.
```
├── data
│   └── backup.ls0  # the last good version of the tree document upon loading, as a fallback for corrupt load file 
├── foliage  # Folder for storing the current tree document and its files.
│   └── tree.ls0  # the single individual tree that the user will work with, loaded upon running the program, and then saved to when, exiting the program or auto-save.
│   └── images  # the folder for the images indexed in the tree, files are saved in lossless jpg with a 8 character hash, ie `.\foliage\images\39ph490g.jpg`.  
│   └── texts  # the folder for the pages indexed in the tree, files are saved in txt with a 8 character hash, ie `.\foliage\text\390ef94i.txt`.  
```

## Requirements:
- Windows - Designed for Windows, tested on Windows 10.
- Other Requirements - installed by the installer.

### Usage
1. run `LightSt0ne.bat`.

## Notes
- Making this program, for me and to be streamlined, its better it optimized to run on my things, hence, no install options, its `Cuda 11.8` ONLY, but I would make it for `cuda 12` if I had such a card.
- Windows ONLY, Paint Shop Pro 9 is for windows; ALL other paint progs not so good for quick arangement/editing of 100s of images.
- Inspired by an AI mod idea for [CherryTree](https://github.com/giuspen/cherrytree).
- Image processing by [ImageMagick](https://imagemagick.org/).
- Multi-platform interfaces by [Avalonia UI](https://avaloniaui.net/).


### Later Development
- Root node Prefab...
```
Configure>  # AI and system configuration. This includes defining AI behavior, plugins, and access permissions. 
    Settings>  # Core settings for AI personality, responsibilities, and response behavior.
    Access>  # login data for accessing defined websites.
    Logs>  # Activity logs, history, and debugging output for transparency and troubleshooting.
    
Organize>  # Personal organization and scheduling area. AI manages tasks, reminders, and daily updates.
    Tasks>  # User-defined tasks with deadlines and priorities. AI could track these and offer reminders or suggestions.
    Calendar>  # A visual representation of upcoming events, deadlines, and reminders.
    News>  # AI-curated updates (critical news, personal feeds, etc.) based on user-defined preferences.
    Notes>  # A scratchpad for quick ideas or to-do items, easily sortable or taggable.

Database>  # User-accumulated data for context, research, and reference.
    Knowledge>  # Organized storage of knowledge categorized by topic (e.g., Science, Art, Personal Projects).
    References>  # A library of documents, articles, and links for AI to prioritize or filter when responding.
    Shortlist>  # Frequently referenced items for quicker AI context building (e.g., "summarize only from these nodes").
```
- And henceforth... `he produce a Living Book` or `the Book had Life to it` ...or in other words...Add Personal Organization. I am guessing there would be some pre-defined structure to the default document, there would be certain pre-defined root nodes, key to the programs understanding of the structure, and if the user does not use those features, they delete the relating branch from the root node, or it should just be configurable frmo the UI. it comes later on, but here are the notes...
```
With the addition of a **personal organizer** functionality (even if implemented through nodes), your program, **LightSt0ne**, would evolve into a **Tree-Based AI Assistant-Organizer-Database**. This would make it a highly versatile and powerful tool for both personal and professional use. Here's a breakdown of what this could look like and how it could function:

---

### **What the Program Would Become:**
1. **Tree-Based Structure:**
   - The core of the program remains a **tree document editor**, where nodes represent tasks, ideas, data, or any other organizational unit.
   - The tree structure allows for **hierarchical organization**, making it easy to break down complex projects or ideas into manageable parts.

2. **AI Assistant:**
   - The AI acts as a **smart assistant** that can:
     - Automatically organize nodes based on user input or predefined rules.
     - Suggest new nodes, connections, or improvements to the structure.
     - Generate content (text, images, or research) to fill out nodes.
     - Provide reminders, summaries, or insights based on the data in the tree.

3. **Personal Organizer:**
   - The program becomes a **personal organizer** by allowing users to:
     - Manage tasks, schedules, and goals through nodes.
     - Track progress on projects or personal objectives.
     - Set reminders and deadlines for specific nodes.
     - Use the AI to prioritize tasks or suggest next steps.

4. **Database:**
   - The tree structure acts as a **local database** where:
     - All data is stored in a structured, searchable format.
     - Users can quickly retrieve information by navigating the tree or using search functions.
     - The AI can analyze the data to provide insights, trends, or recommendations.
```
- later conversion into a program for doing the same thing, but to documents `LightPebb1e`, with more editing features and complexity, but for a linear document.
- it would also be interesting to get image recognition, as this would enable checking that pictures from the web are actually correct. This will come later possibly. 
- Possibly I need to make also `LightSt0ne-STD`, the "viewer" version of LightSt0ne, because I want a viewer without the AI parts, which I logically should have made first. The idea is one can copy the `.\foliage` folder into the install of `LightSt0ne-STD`. `LightSt0ne-STD` should be portable once installed.

## Disclaimer:
- Wiseman-Timelord does not consent to, authorize and/or empower any given documents created by other individuals using LightSt0ne, nay, for other individuals, authorise and empowere, their own works, for whatever, authority and powers, they have.
