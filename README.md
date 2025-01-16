# AiCherryTree
Status: Planning

### Description:
Supposedly its possible to modify CherryTree, to generate entire tree documents given source data. Below is some info...


Yes, while CherryTree itself doesn’t have built-in AI scripting, you can use Python to interact with CherryTree files and integrate AI models like OpenAI’s GPT or local models (Llama) to generate content. CherryTree saves its data in either **SQLite-based** (`.ctb`) or **XML-based** (`.ctz`) formats, which can be accessed and modified programmatically.

Here’s how you can implement AI scripting for CherryTree:

---

## **How AI Scripting for CherryTree Works**

1. **Use CherryTree File Format**:
   - `.ctb` (SQLite database): Can be manipulated using Python’s SQLite libraries.
   - `.ctz` (compressed XML): Can be managed using XML libraries in Python.

2. **Generate Content with AI**:
   - Use an AI model (like OpenAI, Llama, or other LLMs) to create content dynamically.
   - Populate the generated content into nodes in the CherryTree file.

3. **Automate Node Management**:
   - Create, update, and delete nodes (chapters, sections, subsections) in the tree structure.

4. **Export and View in CherryTree**:
   - Once the script modifies the CherryTree file, open it in CherryTree to view the changes.

---

## **Step-by-Step Guide to AI Scripting for CherryTree**

### **Step 1: Install Required Libraries**
Install Python and the following libraries:
```bash
pip install openai lxml sqlite3
```

### **Step 2: Generate AI Content**
Use an AI model to generate text for each node in the tree structure.

### **Step 3: Manipulate CherryTree Files**

#### **For `.ctb` (SQLite Database) Files**
You can directly modify the SQLite database used by CherryTree.

```python
import sqlite3
import openai

# Connect to the CherryTree .ctb file
db_path = "example.ctb"
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# Generate AI content
def generate_content(prompt):
    openai.api_key = "YOUR_API_KEY"
    response = openai.Completion.create(
        engine="text-davinci-003",
        prompt=prompt,
        max_tokens=500
    )
    return response["choices"][0]["text"].strip()

# Add a new node
node_title = "Chapter 1: Introduction"
node_content = generate_content(f"Write an introduction for {node_title}")

cursor.execute("""
    INSERT INTO node (name, txt, is_bold, father_id) 
    VALUES (?, ?, ?, ?)
""", (node_title, node_content, 0, 1))  # `father_id` links to the parent node

conn.commit()
conn.close()
print("Node added to CherryTree!")
```

#### **For `.ctz` (XML Files)**
You can parse and update the XML file using Python.

```python
from lxml import etree
import openai

# Load the CherryTree XML file
tree = etree.parse("example.ctz")
root = tree.getroot()

# Generate AI content
def generate_content(prompt):
    openai.api_key = "YOUR_API_KEY"
    response = openai.Completion.create(
        engine="text-davinci-003",
        prompt=prompt,
        max_tokens=500
    )
    return response["choices"][0]["text"].strip()

# Add a new node
node_title = "Chapter 1: Introduction"
node_content = generate_content(f"Write an introduction for {node_title}")

new_node = etree.Element("node", name=node_title)
rich_text = etree.SubElement(new_node, "rich_text")
rich_text.text = node_content

root.append(new_node)

# Save the updated CherryTree file
tree.write("updated_example.ctz", pretty_print=True, xml_declaration=True, encoding="UTF-8")
print("Node added to CherryTree!")
```

---

## **Step 4: Automate Tree-Document Creation**
Expand the script to:
1. Create multiple nodes (chapters, sections, subsections).
2. Dynamically generate content for each node.

Example:
```python
chapters = [
    {"title": "Chapter 1: Introduction", "sections": ["History of AI", "Modern AI Trends"]},
    {"title": "Chapter 2: Ethics in AI", "sections": ["Bias in AI", "Privacy Concerns"]}
]

for chapter in chapters:
    # Add chapter node
    chapter_content = generate_content(f"Write an overview for {chapter['title']}")
    # Add sections under the chapter
    for section in chapter["sections"]:
        section_content = generate_content(f"Write a detailed section about {section}")
```

---

## **Benefits of Using AI with CherryTree**
- **Automation**: No need to manually create and populate nodes.
- **Scalability**: Easily generate content for large projects like books or technical documentation.
- **Customization**: Tailor AI prompts to fit your book’s theme and style.

Would you like help setting up a script for your specific project?
