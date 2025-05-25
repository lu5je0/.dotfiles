import os
import re
from datetime import datetime, timezone, timedelta
import piexif
import argparse
import subprocess
import sys

# 终端颜色
def color_filename(filename):
    if sys.stdout.isatty():
        # 蓝色加粗
        return f"\033[1;34m{filename}\033[0m"
    return filename

def color_status(status):
    if not sys.stdout.isatty():
        return status
    if status == "success":
        return f"\033[1;32m{status}\033[0m"  # 绿色
    elif status == "ignore":
        return f"\033[1;33m{status}\033[0m"  # 黄色
    elif status == "error":
        return f"\033[1;31m{status}\033[0m"  # 红色
    return status

def log(filename, status, msg):
    print(f"[{color_filename(filename)}] [{color_status(status)}] {msg}")

def extract_datetime_from_filename(filename):
    # 1. 匹配时间戳（10位或13位数字）
    ts_match = re.search(r'(\d{10,13})', filename)
    if ts_match:
        ts_str = ts_match.group(1)
        if len(ts_str) == 13:
            ts = int(ts_str) // 1000
        else:
            ts = int(ts_str)
        try:
            dt = datetime.fromtimestamp(ts, tz=timezone(timedelta(hours=8)))
            return dt
        except Exception:
            pass

    # 2. 匹配yyyy-mm-dd_hh-mm-ss、yyyy-mm-dd hh:mm:ss、yyyy-mm-dd hhmmss、yyyy-mm-dd-hhmmss
    date_patterns = [
        r'(\d{4}-\d{2}-\d{2})[ _-](\d{2}[-:]\d{2}[-:]\d{2})',   # 2023-04-07_10-20-30 或 2023-04-07-10-20-30
        r'(\d{4}-\d{2}-\d{2})[ _T]?(\d{2}:\d{2}:\d{2})',        # 2023-04-07 10:20:30
        r'(\d{4}-\d{2}-\d{2})[ _-]?(\d{6})',                    # 2024-07-22 223056、2024-07-22_223056、2024-07-22-223056
    ]
    for pattern in date_patterns:
        match = re.search(pattern, filename)
        if match:
            date_part, time_part = match.groups()
            # 处理 223056 形式
            if len(time_part) == 6 and ':' not in time_part and '-' not in time_part:
                time_part = f"{time_part[:2]}:{time_part[2:4]}:{time_part[4:6]}"
            else:
                time_part = time_part.replace('-', ':')
            try:
                dt = datetime.strptime(f"{date_part} {time_part}", "%Y-%m-%d %H:%M:%S")
                dt = dt.replace(tzinfo=timezone(timedelta(hours=8)))
                return dt
            except Exception:
                continue

    # 3. 匹配20190807_161503 或 20190807-161503
    match = re.search(r'(\d{8})[ _-](\d{6})', filename)
    if match:
        date_str, time_str = match.groups()
        try:
            dt = datetime.strptime(f"{date_str} {time_str}", "%Y%m%d %H%M%S")
            dt = dt.replace(tzinfo=timezone(timedelta(hours=8)))
            return dt
        except Exception:
            pass

    # 4. 兜底只识别日期
    # 匹配 20190807
    match = re.search(r'(\d{8})', filename)
    if match:
        date_str = match.group(1)
        try:
            dt = datetime.strptime(date_str, "%Y%m%d")
            dt = dt.replace(hour=0, minute=0, second=0, tzinfo=timezone(timedelta(hours=8)))
            return dt
        except Exception:
            pass
    # 匹配 2019-08-07 或 2019_08_07（横杠或下划线分隔）
    match = re.search(r'(\d{4})[-_](\d{2})[-_](\d{2})', filename)
    if match:
        year, month, day = match.groups()
        try:
            dt = datetime(int(year), int(month), int(day), 0, 0, 0, tzinfo=timezone(timedelta(hours=8)))
            return dt
        except Exception:
            pass

    return None

def datetime_in_valid_range(dt):
    dt = dt.astimezone(timezone(timedelta(hours=8)))
    start = datetime(2010, 1, 1, tzinfo=timezone(timedelta(hours=8)))
    end = datetime(2030, 12, 31, 23, 59, 59, tzinfo=timezone(timedelta(hours=8)))
    return start <= dt <= end

def has_exif_datetime(image_path):
    try:
        exif_dict = piexif.load(image_path)
        dt_bytes = exif_dict['Exif'].get(piexif.ExifIFD.DateTimeOriginal)
        if dt_bytes:
            dt_str = dt_bytes.decode(errors="ignore")
            # 验证是否为有效时间
            try:
                datetime.strptime(dt_str, "%Y:%m:%d %H:%M:%S")
                return True
            except Exception:
                return False
    except Exception:
        pass
    return False

def set_exif_datetime(image_path, dt):
    exif_dict = piexif.load(image_path)
    dt_str = dt.strftime("%Y:%m:%d %H:%M:%S")
    exif_dict['Exif'][piexif.ExifIFD.DateTimeOriginal] = dt_str.encode()
    exif_dict['0th'][piexif.ImageIFD.DateTime] = dt_str.encode()
    exif_bytes = piexif.dump(exif_dict)
    piexif.insert(exif_bytes, image_path)

def set_video_creation_time(file_path, dt):
    dt_str = dt.strftime('%Y:%m:%d %H:%M:%S')
    cmd = [
        'exiftool',
        '-overwrite_original',
        f'-CreateDate={dt_str}',
        f'-ModifyDate={dt_str}',
        f'-TrackCreateDate={dt_str}',
        f'-MediaCreateDate={dt_str}',
        file_path
    ]
    try:
        subprocess.run(cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        log(file_path, "success", f"set video datetime: {dt_str}")
    except Exception as e:
        log(file_path, "error", f"failed to set video datetime: {e}")

def process_directory(directory, force_write_exif):
    photo_exts = {'.jpg', '.jpeg', '.png', '.JPG', '.JPEG', '.PNG'}
    video_exts = {'.mp4', '.mov', '.avi', '.MP4', '.MOV', '.AVI', '.mkv', '.MKV'}
    for root, dirs, files in os.walk(directory):
        for fname in files:
            _, ext = os.path.splitext(fname)
            full_path = os.path.join(root, fname)
            dt = extract_datetime_from_filename(fname)
            if ext in photo_exts:
                if not force_write_exif and has_exif_datetime(full_path):
                    log(full_path, "ignore", "skip: already has EXIF datetime")
                    continue
                if dt:
                    if datetime_in_valid_range(dt):
                        try:
                            set_exif_datetime(full_path, dt)
                            log(full_path, "success", f"write EXIF datetime: {dt}")
                        except Exception as e:
                            log(full_path, "error", f"failed to write EXIF: {e}")
                    else:
                        log(full_path, "error", f"time {dt} is out of 2010-2030 range, skip")
                else:
                    log(full_path, "error", "no valid datetime found in filename")
            elif ext in video_exts:
                if dt:
                    if datetime_in_valid_range(dt):
                        set_video_creation_time(full_path, dt)
                    else:
                        log(full_path, "error", f"time {dt} is out of 2010-2030 range, skip")
                else:
                    log(full_path, "error", "no valid datetime found in filename")

def main():
    parser = argparse.ArgumentParser(description="Write datetime to EXIF (for images) or metadata (for videos) from filename in specified directory and its subdirectories.")
    parser.add_argument("directory", type=str, nargs="?", default=".", help="Directory to process (default: current directory)")
    parser.add_argument("-f", "--force-write-exif", action="store_true", help="Force write datetime for images even if EXIF already exists.")
    args = parser.parse_args()
    process_directory(args.directory, args.force_write_exif)

if __name__ == "__main__":
    main()
