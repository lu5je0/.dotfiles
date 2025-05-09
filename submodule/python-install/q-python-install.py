#!/usr/bin/env python3

import os
import sys
import argparse
import textwrap

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
def generate_run_script(script_path, script_name, output_dir):
    # Get base name of Python script to name the run.sh
    script_name = os.path.basename(script_name)
    target_name = f"{os.path.splitext(script_name)[0]}"
    
    run_script_content = f"""
    #!/bin/bash
    INSTALL_PATH=$(dirname "$(realpath "${{BASH_SOURCE[0]}}")")
    SCRIPT_PATH={script_path}
    SCRIPT_NAME={script_name}
    """
    run_script_content = run_script_content[1:]
    run_script_content = textwrap.dedent(run_script_content)

    script_path = os.path.expanduser(script_path)
    if os.path.exists(script_path + '/.script'):
        with open(script_path + '/.script') as script:
            lines = script.readlines()
            ext_script = "".join(lines)
            run_script_content += ext_script
            
            # set target_name
            ext_script_map = source_shell_file(lines)
            if 'TARGET_NAME' in ext_script_map:
                target_name = ext_script_map['TARGET_NAME']

    run_script_content += '\nsource ${INSTALL_PATH}/../submodule/python-install/runner.sh'
        
    # Ensure output directory exists
    os.makedirs(output_dir, exist_ok=True)

    run_script_path = os.path.join(output_dir, target_name)
    with open(run_script_path, "w") as run_script_file:
        run_script_file.write(run_script_content)

    # Make run.sh executable
    os.chmod(run_script_path, 0o755)
    print(f"run.sh script generated at {run_script_path}")

def replace_home_with_tilde(path):
    home_dir = os.path.expanduser("~")
    if path.startswith(home_dir + "/.dotfiles"):
        return path.replace(home_dir + "/.dotfiles", "${INSTALL_PATH}/..", 1)
    return path

def main():
    parser = argparse.ArgumentParser(description="Generate run.sh script for a Python project.")
    parser.add_argument("python_script", help="The Python script that will be run by the generated run.sh.")
    parser.add_argument("-o", "--output-dir", default=os.path.expanduser("~/.dotfiles/bin"), help="Directory to place the generated run.sh script (default: '~/.dotfiles/bin').")
    
    args = parser.parse_args()

    script_name = args.python_script
    if not os.path.exists(script_name):
        print(f"Error: Python script '{script_name}' does not exist.")
        sys.exit(1)

    # Determine paths
    output_dir = args.output_dir

    # Generate run.sh script
    generate_run_script(replace_home_with_tilde(os.getcwd()), script_name, output_dir)

if __name__ == "__main__":
    main()
