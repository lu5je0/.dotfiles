import pysrt
import os
import argparse
import asstosrt

def read_ass_template(ass_file):
    with open(ass_file, 'r', encoding='utf-8') as f:
        lines = f.readlines()
        return "".join(lines)

def is_chinese_line(line):
    for char in line:
        if '\u4e00' <= char <= '\u9fff':
            return True
    return False

def srt_to_ass(source_sub_file_path: str, ass_template: str, output_ass_file, args):
    """将 .srt 文件转换为 .ass 格式，并使用给定的样式"""
    if source_sub_file_path.endswith("ass"):
        with open(source_sub_file_path) as source_ass_file:
            subs = pysrt.from_string(asstosrt.convert(source_ass_file))
    else:
        subs = pysrt.open(source_sub_file_path)
    
    with open(output_ass_file, 'w', encoding='utf-8') as ass_file:
        # 写入 .ass 文件的基本信息和样式
        ass_file.write(ass_template)
        ass_file.write("\n")
        ass_file.write("[Events]\n")
        ass_file.write("Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n\n")
        
        # 将每个字幕条目转换为 .ass 格式
        for sub in subs:
            start_time = sub.start.to_time()
            end_time = sub.end.to_time()
            start = f"{start_time.hour:01}:{start_time.minute:02}:{start_time.second:02}.{int(start_time.microsecond / 10000):02}"
            end = f"{end_time.hour:01}:{end_time.minute:02}:{end_time.second:02}.{int(end_time.microsecond / 10000):02}"

            # 写入字幕事件
            if args.english_standone_font:
                eng_font = 'Eng'
            else:
                eng_font = 'Default'
                
            if args.split_zh_and_en_lines:
                lines = sub.text.split('\n')
                sub.text = ""
                append_newline = False
                for line in lines:
                    if is_chinese_line(line):
                        sub.text = sub.text + ("" if sub.text == "" else " ") + line
                    else:
                        if not append_newline and sub.text != "":
                            sub.text += f"\\N{{\\r{eng_font}}}"
                            append_newline = True
                        sub.text = sub.text + (" " if sub.text == "" else "") + line
            else:
                sub.text = sub.text.replace("\n", f"\\N{{\\r{eng_font}}}")
            
            ass_file.write(f"Dialogue: 0,{start},{end},Default,,0,0,0,,{sub.text}\n")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate run.sh script for a Python project.")
    parser.add_argument('files', nargs='+')
    parser.add_argument("-s", "--split-zh-and-en-lines", action="store_true")
    parser.add_argument("-e", "--english-standone-font", action="store_true")
    
    template_path = os.path.split(os.path.realpath(__file__))[0] + "/template/"
    parser.add_argument("-t", "--template-name", default="1", choices=[x.split(".")[0] for x in sorted(os.listdir(template_path))])
    
    args = parser.parse_args()
    
    ass_template_file = template_path + f"{args.template_name}.ass"
    for source_sub_file in args.files:
        if not (source_sub_file.endswith("srt") or source_sub_file.endswith("ass")):
            print(f'ingore {source_sub_file}')
            continue
        ass_template = read_ass_template(ass_template_file)
        output_ass_file = ".".join(os.path.basename(source_sub_file).split('.')[:-1]) + ".ass"
        srt_to_ass(source_sub_file, ass_template, output_ass_file, args)
