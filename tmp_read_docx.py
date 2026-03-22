import zipfile
import xml.etree.ElementTree as ET
import sys

def read_docx(path):
    try:
        z = zipfile.ZipFile(path)
        content = z.read('word/document.xml')
        root = ET.fromstring(content)
        texts = []
        for node in root.iter():
            if node.tag.endswith('}t') and node.text:
                texts.append(node.text)
        print('\n'.join(texts))
    except Exception as e:
        print(f"Error: {e}")

if __name__ == '__main__':
    read_docx(sys.argv[1])
