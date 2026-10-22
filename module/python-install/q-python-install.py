#!/usr/bin/env python3

import os
import sys
import argparse
import shlex
import textwrap
from pathlib import Path


DOTFILES_ROOT = Path(__file__).resolve().parents[2]

def source_shell_file(lines):
    target = {}
    for line in lines:
        # 忽略注释和空行
        if line.startswith('#') or not line.strip():
            continue
        # 解析变量
        key, _, value = line.partition('=')
        target[key] = value.strip()
    return target

# Function to generate run.sh script
def generate_run_script(script_path, script_name, output_dir, output_name=None):
    script_path = Path(script_path).resolve()
    output_dir = Path(output_dir).resolve()
    # Get base name of Python script to name the run.sh
    script_name = os.path.basename(script_name)
    target_name = f"{os.path.splitext(script_name)[0]}"

    # 入口先解析符号链接，再按生成时的目录关系定位仓库，不依赖 sudo 下的 HOME。
    dotfiles_relative_path = shlex.quote(os.path.relpath(DOTFILES_ROOT, output_dir))
    run_script_content = f"""
    #!/bin/bash
    if [ -z "${{DOTFILES_DIR:-}}" ]; then
      launcher_path=${{BASH_SOURCE[0]}}
      while [ -L "$launcher_path" ]; do
        launcher_dir=$(CDPATH= cd -P -- "$(dirname -- "$launcher_path")" && pwd) || exit 1
        launcher_path=$(readlink "$launcher_path") || exit 1
        [[ $launcher_path = /* ]] || launcher_path=$launcher_dir/$launcher_path
      done
      DOTFILES_DIR=$(CDPATH= cd -P -- "$(dirname -- "$launcher_path")"/{dotfiles_relative_path} && pwd) || exit 1
      unset launcher_path launcher_dir
    fi
    SCRIPT_PATH={rewrite_path_with_dotfiles(script_path)}
    SCRIPT_NAME={shlex.quote(script_name)}
    """
    run_script_content = run_script_content[1:]
    run_script_content = textwrap.dedent(run_script_content)

    if (script_path / '.script').exists():
        with open(script_path / '.script') as script:
            lines = script.readlines()
            ext_script = "".join(lines)
            if ext_script:
                run_script_content += '\n' + ext_script

            # set target_name
            ext_script_map = source_shell_file(lines)
            if 'TARGET_NAME' in ext_script_map:
                target_name = ext_script_map['TARGET_NAME']

    if output_name:
        target_name = output_name

    run_script_content += '\nsource "$DOTFILES_DIR/module/python-install/runner.sh"\n'

    # Ensure output directory exists
    os.makedirs(output_dir, exist_ok=True)

    run_script_path = os.path.join(output_dir, target_name)
    with open(run_script_path, "w") as run_script_file:
        run_script_file.write(run_script_content)

    # Make run.sh executable
    os.chmod(run_script_path, 0o755)
    print(f"run.sh script generated at {run_script_path}")

def rewrite_path_with_dotfiles(path):
    path = Path(path).resolve()
    try:
        relative_path = path.relative_to(DOTFILES_ROOT)
    except ValueError:
        return shlex.quote(str(path))
    return '"$DOTFILES_DIR"/' + shlex.quote(str(relative_path))

def main():
    parser = argparse.ArgumentParser(description="Generate run.sh script for a Python project.")
    parser.add_argument("python_script", help="The Python script that will be run by the generated run.sh.")
    parser.add_argument("-o", "--output-dir", default=str(DOTFILES_ROOT / "bin/common"), help="Directory to place the generated run.sh script (default: repository's bin/common).")
    parser.add_argument("--output-name", help="Name of the generated launcher script.")

    args = parser.parse_args()

    script_file = Path(args.python_script).resolve()
    if not script_file.is_file():
        print(f"Error: Python script '{args.python_script}' does not exist.")
        sys.exit(1)

    # Determine paths
    output_dir = args.output_dir

    # Generate run.sh script
    generate_run_script(
        script_file.parent,
        script_file.name,
        output_dir,
        output_name=args.output_name,
    )

if __name__ == "__main__":
    main()
