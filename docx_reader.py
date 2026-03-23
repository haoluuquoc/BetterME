import zipfile
import xml.etree.ElementTree as ET

def extract_text_from_docx(docx_path):
    try:
        with zipfile.ZipFile(docx_path) as docx:
            xml_content = docx.read('word/document.xml')
            tree = ET.fromstring(xml_content)
            ns = {'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
            text = []
            for p in tree.iterfind('.//w:p', ns):
                p_text = ''.join(node.text for node in p.iterfind('.//w:t', ns) if node.text)
                if p_text:
                    text.append(p_text)
            return '\n'.join(text)
    except Exception as e:
        return str(e)

print(extract_text_from_docx(r'C:\Users\haolu\Downloads\GiaiDoan3_NguyenXuanBach_226969.docx'))
