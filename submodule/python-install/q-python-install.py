#!/usr/bin/env python3

import os
import sys
import argparse

# Function to generate run.sh script
def generate_run_script(script_path, script_name, run_script_name, output_dir):
    with open(os.path.split(os.path.realpath(__file__))[0] + "/runner.sh") as f:
        run_script_content = "".join(f.readlines())
        run_script_content = run_script_content.format(
                script_path=script_path,
                script_name=script_name
                )
    # Ensure output directory exists
    os.makedirs(output_dir, exist_ok=True)

    run_script_path = os.path.join(output_dir, run_script_name)
    with open(run_script_path, "w") as run_script_file:
        run_script_file.write(run_script_content)

    # Make run.sh executable
    os.chmod(run_script_path, 0o755)
    print(f"run.sh script generated at {run_script_path}")

def replace_home_with_tilde(path):
    home_dir = os.path.expanduser("~")
    if path.startswith(home_dir):
        return path.replace(home_dir, "~", 1)
    return path

def main():
    parser = argparse.ArgumentParser(description="Generate run.sh script for a Python project.")
    parser.add_argument("python_script", help="The Python script that will be run by the generated run.sh.")
    parser.add_argument("-o", "--output-dir", default=os.path.expanduser("~/.dotfiles/bin"), help="Directory to place the generated run.sh script (default: '~/.dotfiles/bin').")
    
    args = parser.parse_args()

    python_script = args.python_script
    if not os.path.exists(python_script):
        print(f"Error: Python script '{python_script}' does not exist.")
        sys.exit(1)

    # Get base name of Python script to name the run.sh
    script_name = os.path.basename(python_script)
    run_script_name = f"{os.path.splitext(script_name)[0]}"

    # Determine paths
    output_dir = args.output_dir

    # Generate run.sh script
    generate_run_script(replace_home_with_tilde(os.getcwd()), python_script, run_script_name, output_dir)

if __name__ == "__main__":
    main()
