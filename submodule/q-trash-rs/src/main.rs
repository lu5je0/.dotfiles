mod backend;
mod commands;
mod model;
mod rm;

use std::env;
use std::process;

const VERSION: &str = concat!("0.1.0 (", env!("BUILD_TIME"), ")");

fn print_help() {
    println!(
        "Usage: q-trash <command> [options]

Commands:
  list [PATH]              list trashed files (optionally filter by original path)
  restore [PATTERN]        interactively restore trashed files
  empty [--days N]         permanently delete trashed files
  size                     show trash disk usage
  rm [OPTION]... [FILE]... move files to trash (rm-compatible)

Options:
  --help                   display this help
  --version                show version"
    );
}

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();

    if args.is_empty() || args[0] == "--help" || args[0] == "-h" {
        print_help();
        process::exit(0);
    }
    if args[0] == "--version" {
        println!("q-trash {}", VERSION);
        process::exit(0);
    }

    let cmd = &args[0];
    let cmd_args: Vec<String> = args[1..].to_vec();

    let code = match cmd.as_str() {
        "list" | "ls" => commands::cmd_list(cmd_args.first().map(|s| s.as_str())),
        "restore" => commands::cmd_restore(&cmd_args),
        "empty" => commands::cmd_empty(&cmd_args),
        "size" => commands::cmd_size(),
        "rm" => rm::run(&cmd_args),
        _ => {
            eprintln!(
                "q-trash: unknown command '{}'\nTry 'q-trash --help' for more information.",
                cmd
            );
            1
        }
    };

    process::exit(code);
}
